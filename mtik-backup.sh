#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 -ip <router-ip-address> [-u <username>] [-d <backup-directory>] [-f <filename>] [-c <comment>]"
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
BACKUP_DIR="./backups"  # Default backup directory
MAX_RETRIES=5  # Maximum number of retries to check for the backup file on the router
SLEEP_INTERVAL=5  # Time to wait (in seconds) between retries
BACKUP_FILENAME=""  # Default empty, will be generated if not provided

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -ip) ROUTER="$2"; shift ;;
        -u) USERNAME="$2"; shift ;;
        -d) BACKUP_DIR="$2"; shift ;;
        -f) BACKUP_FILENAME=$(basename "$2"); shift ;;  # Ensure only the filename is used
        -c) COMMENT="$2"; shift ;;
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
if [[ -z "$BACKUP_FILENAME" ]]; then
    BACKUP_FILENAME="${CLEAN_HOSTNAME}-${CLEAN_IP}-${CLEAN_HW}-${CLEAN_SW}-${TIMESTAMP}"
fi

if [[ -n "$COMMENT" ]]; then
    BACKUP_FILENAME="${BACKUP_FILENAME}-${COMMENT}.backup"
else
    BACKUP_FILENAME="${BACKUP_FILENAME}.backup"
fi
echo "Backup Filename: $BACKUP_FILENAME"

# Create the backups directory if it doesn't exist
BACKUP_DIR="$BACKUP_DIR/$(echo "$TIMESTAMP" | cut -d'-' -f1)/${CLEAN_HOSTNAME}-${CLEAN_IP}"
mkdir -p "$BACKUP_DIR"
echo "Backup Directory: $BACKUP_DIR"

# Create the backup on the router
echo
ssh "$USERNAME@$ROUTER" "system backup save name=$BACKUP_FILENAME"

# Wait until the backup file is available on the router before downloading
echo
RETRIES=0
while true; do
    FILE_OUTPUT=$(ssh "$USERNAME@$ROUTER" "file print where name=$BACKUP_FILENAME")
    FILE_LINES=$(echo "$FILE_OUTPUT" | wc -l)
    
    if [[ $FILE_LINES -ge 2 ]]; then
        echo "Backup file found on router. Proceeding with download..."
        break
    fi
    
    if [[ $RETRIES -ge $MAX_RETRIES ]]; then
        echo "Failed to find backup file on the router after $MAX_RETRIES attempts. Aborting."
        exit 1
    fi

    echo "Backup file not found on router. Retrying in $SLEEP_INTERVAL seconds..."
    sleep $SLEEP_INTERVAL
    ((RETRIES++))
done

# Download the backup file to the specified directory
scp "$USERNAME@$ROUTER:$BACKUP_FILENAME" "$BACKUP_DIR/"

DEL_RETRY=5  # Number of times to retry deletion
DEL_RETRY_INTERVAL=2  # Time to wait (in seconds) between retries
DEL_ATTEMPTS=0

# Introduce a short delay before attempting to remove the file
sleep $DEL_RETRY_INTERVAL

# Attempt to remove the backup file from the router, and add debugging
echo
echo "Attempting to remove backup file: $BACKUP_FILENAME"

while true; do
    ssh "$USERNAME@$ROUTER" "file remove $BACKUP_FILENAME" && break
    ((DEL_ATTEMPTS++))
    
    if [[ $DEL_ATTEMPTS -ge $DEL_RETRY ]]; then
        echo "Failed to remove backup file: $BACKUP_FILENAME after $DEL_RETRY attempts."
        break
    fi
    
    echo "Retrying to remove backup file in $DEL_RETRY_INTERVAL seconds..."
    sleep $DEL_RETRY_INTERVAL
done

echo
echo "SUCCESS: Backup completed and saved as $BACKUP_DIR/$BACKUP_FILENAME"
# echo "Backup completed and saved as $BACKUP_DIR/$BACKUP_FILENAME"