#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 -ip <router-ip-address> [-full] [-u <username>] [-d <export-directory>] [-f <filename>] [-c <comment>]"
    exit 1
}

# Function to check if the user has "full" rights
check_user_rights() {
    local user_info=$(ssh "$USERNAME@$ROUTER" "user print where name=$USERNAME" | grep "$USERNAME")
    if [[ "$user_info" == *"full"* ]]; then
        echo "User $USERNAME has full rights."
        echo
    else
        echo "Error: User $USERNAME does not have full rights. Exiting."
        exit 1
    fi
}

# Function to format the comment parameter: remove leading/trailing spaces and replace spaces with underscores, remove any other non-alphanumeric characters
format_comment() {
    local comment="$1"
    # Remove leading/trailing spaces
    comment=$(echo "$comment" | xargs)
    # Replace spaces with underscores
    comment=$(echo "$comment" | tr ' ' '_')
    # Remove all non-alphanumeric characters, except underscores
    comment=$(echo "$comment" | tr -cd '[:alnum:]_')
    echo "$comment"
}

# Default values
USERNAME="backupuser"
EXPORT_DIR="./exports"  # Default export directory
DELETE_DELAY=1  # Delay in seconds before attempting to delete the file
EXPORT_FILENAME=""  # Default empty, will be generated if not provided

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -ip) ROUTER="$2"; shift ;;
        -u) USERNAME="$2"; shift ;;
        -d) EXPORT_DIR="$2"; shift ;;
        -f) EXPORT_FILENAME=$(basename "$2"); shift ;;  # Ensure only the filename is used
        -c) COMMENT="$2"; shift ;;
        -full) FULL_BACKUP="true" ;;
        *) usage ;;  # If an unknown option is passed, show usage
    esac
    shift
done

# Check if mandatory parameter is provided
if [[ -z "$ROUTER" ]]; then
    usage
fi

# Check if the user has the required rights
check_user_rights

# Attempt to get the hostname of the router
HOSTNAME=$(ssh "$USERNAME@$ROUTER" "system identity print" | grep name | awk -F': ' '{print $2}' | tr -d '\r')

# If hostname retrieval fails, use the IP address as the hostname
if [[ -z "$HOSTNAME" ]]; then
    HOSTNAME=$ROUTER
fi

CLEAN_HOSTNAME=$(echo "$HOSTNAME" | tr -cd '[:alnum:]')
echo "Hostname: $HOSTNAME"

CLEAN_IP=$(echo "$ROUTER" | tr '.' '_')
echo "IP addr: $CLEAN_IP"

CLEAN_HW=$(ssh "$USERNAME@$ROUTER" "system resource print" | grep 'board-name' | awk -F': ' '{print $2}' | tr -d '\r')
echo "Hardware: $CLEAN_HW"

CLEAN_SW=$(ssh "$USERNAME@$ROUTER" "system resource print" | grep 'version' | awk -F': ' '{print $2}' | tr -d '\r') 
CLEAN_SW=$(echo "$CLEAN_SW" | tr '.' '_')
CLEAN_SW=$(echo "$CLEAN_SW" | tr -cd '[:alnum:]_')
echo "Software: $CLEAN_SW"

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
echo "Timestamp: $TIMESTAMP"

# Format the comment parameter if provided
if [[ -n "$COMMENT" ]]; then
    COMMENT=$(format_comment "$COMMENT")
fi
echo "Comment: $COMMENT"

# Create the backup filename if not provided
if [[ -z "$EXPORT_FILENAME" ]]; then
    FILE_PREFIX="${CLEAN_HOSTNAME}-${CLEAN_IP}-${CLEAN_HW}-${CLEAN_SW}-${TIMESTAMP}"
else
    FILE_PREFIX="${EXPORT_FILENAME}-${TIMESTAMP}"
fi

if [[ -n "$COMMENT" ]]; then
    FILE_PREFIX="${FILE_PREFIX}-${COMMENT}"
fi

# Prefix for the filenames
echo "Export Filename: $FILE_PREFIX"

# Create the exports directory if it doesn't exist
EXPORT_DIR="$EXPORT_DIR/$(echo "$TIMESTAMP" | cut -d'-' -f1)/${CLEAN_HOSTNAME}-${CLEAN_IP}"
mkdir -p "$EXPORT_DIR"
echo "Export Directory: $EXPORT_DIR"

# Define the list of configurations to export with their corresponding context paths
if [[ -n "$FULL_BACKUP" ]]; then
    # Full backup: export all configurations
    configs=(
        "full_export:"
    )
else
    configs=(
        "wireguard:/interface wireguard"
        "firewall:/ip firewall"
        "ip:/ip address"
        "dhcp-server:/ip dhcp-server"
        "routing:/ip route"
        "user:/user"
        "interface_wireless:/interface wireless"
        "queue:/queue"
        "bridge:/interface bridge"
        "interface:/interface"
        "system_script:/system script"
        "ppp_profile:/ppp profile"
    )
fi

# Iterate over each configuration and export to a file
echo

for config in "${configs[@]}"; do
    # Split the config into name and path
    config_name="${config%%:*}"
    config_path="${config##*:}"
    
    echo "Exporting $config_name configuration from $config_path..."
    
    # Run the export command and check for errors
    ssh "$USERNAME@$ROUTER" "$config_path export file=$FILE_PREFIX-$config_name" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to export $config_name configuration."
        echo
        continue
    fi
    
    # Download the file and check for errors
    scp "$USERNAME@$ROUTER:$FILE_PREFIX-$config_name.rsc" "$EXPORT_DIR/$FILE_PREFIX-$config_name.rsc" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download $config_name configuration."
        echo
        continue
    else
        echo "SUCCESS: $config_name configuration saved successfully."
    fi
    
    # # Introduce a delay before attempting to delete the file
    # echo "Waiting $DELETE_DELAY seconds before deleting the file..."
    # echo
    # sleep $DELETE_DELAY
    
    # # Remove the file using a wildcard pattern
    # ssh "$USERNAME@$ROUTER" "file remove [find name~\"$FILE_PREFIX-$config_name*\"]" > /dev/null 2>&1
    # if [ $? -ne 0 ]; then
    #     echo "ERROR: Failed to remove $config_name configuration from the router."
    #     continue
    # else
    #     echo "SUCCESS: $config_name configuration file removed successfully from the router."
    # fi

    DEL_RETRY=5  # Number of times to retry deletion
    DEL_RETRY_INTERVAL=2  # Time to wait (in seconds) between retries
    DEL_ATTEMPTS=0

    # Introduce a delay before attempting to delete the file
    sleep $DEL_RETRY_INTERVAL

    # Attempt to remove the file from the router
    echo
    echo "Attempting to remove $config_name configuration file: $FILE_PREFIX-$config_name.rsc"

    while true; do
        ssh "$USERNAME@$ROUTER" "file remove $FILE_PREFIX-$config_name.rsc" && break
        ((DEL_ATTEMPTS++))

        if [[ $DEL_ATTEMPTS -ge $DEL_RETRY ]]; then
            echo "Failed to remove $config_name configuration file: $FILE_PREFIX-$config_name.rsc after $DEL_RETRY attempts."
            echo
            break
        fi

        echo "Retrying to remove $config_name configuration file in $DEL_RETRY_INTERVAL seconds..."
        sleep $DEL_RETRY_INTERVAL
    done

    echo "SUCCESS: $config_name configuration file removed from the router."


    echo
done

echo
echo "SUCCESS: All configuration exports attempted, successful exports saved to $EXPORT_DIR."