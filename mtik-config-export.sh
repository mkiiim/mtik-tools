#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 -ip <router-ip-address> [-u <username>] [-d <export-directory>]"
    exit 1
}

# Default values
USERNAME="admin"
EXPORT_DIR="./exports"  # Default export directory
DELETE_DELAY=2  # Delay in seconds before attempting to delete the file

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -ip) ROUTER="$2"; shift ;;
        -u) USERNAME="$2"; shift ;;
        -d) EXPORT_DIR="$2"; shift ;;
        *) usage ;;  # If an unknown option is passed, show usage
    esac
    shift
done

# Check if mandatory parameter is provided
if [[ -z "$ROUTER" ]]; then
    usage
fi

# Get the hostname of the router
HOSTNAME=$(ssh "$USERNAME@$ROUTER" "system identity print" | grep name | awk -F': ' '{print $2}' | tr -d '\r')

# If hostname retrieval fails, use the IP address as the hostname
if [[ -z "$HOSTNAME" ]]; then
    HOSTNAME=$ROUTER
fi

# Strip all non-alphanumeric characters from the hostname and IP address
CLEAN_HOSTNAME=$(echo "$HOSTNAME" | tr -cd '[:alnum:]')
CLEAN_IP=$(echo "$ROUTER" | tr -cd '[:alnum:]')

# Create a timestamp
TIMESTAMP=$(date +"%Y%m%d-%H%M")

# Prefix for the filenames
FILE_PREFIX="mikrotik-${CLEAN_HOSTNAME}${CLEAN_IP}-${TIMESTAMP}"

# Create the exports directory if it doesn't exist
mkdir -p "$EXPORT_DIR"

# Define the list of configurations to export with their corresponding context paths
configs=(
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
)

# Iterate over each configuration and export to a file
for config in "${configs[@]}"; do
    # Split the config into name and path
    config_name="${config%%:*}"
    config_path="${config##*:}"
    
    echo "Exporting $config_name configuration from $config_path..."
    
    # Run the export command and check for errors
    ssh "$USERNAME@$ROUTER" "$config_path export file=$FILE_PREFIX-$config_name" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to export $config_name configuration."
        continue
    fi
    
    # Download the file and check for errors
    scp "$USERNAME@$ROUTER:$FILE_PREFIX-$config_name.rsc" "$EXPORT_DIR/$FILE_PREFIX-$config_name.rsc" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download $config_name configuration."
        continue
    fi
    
    # Introduce a delay before attempting to delete the file
    echo "Waiting $DELETE_DELAY seconds before deleting the file..."
    sleep $DELETE_DELAY
    
    # Remove the file using a wildcard pattern
    ssh "$USERNAME@$ROUTER" "file remove [find name~\"$FILE_PREFIX-$config_name*\"]" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to remove $config_name configuration from the router."
    else
        echo "$config_name configuration file removed successfully from the router."
    fi
done

echo "All configurations have been exported to $EXPORT_DIR."