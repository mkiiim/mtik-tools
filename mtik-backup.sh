#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 -ip <router-ip-address> [-u <username>] [-d <backup-directory>] [-f <filename>]"
    exit 1
}

# Function to check if the user has "full" rights
check_user_rights() {
    local user_info=$(ssh "$USERNAME@$ROUTER" "user print where name=$USERNAME" | grep "$USERNAME")
    if [[ "$user_info" == *"full"* ]]; then
        echo "User $USERNAME has full rights."
    else
        echo "Error: User $USERNAME does not have full rights. Exiting."
        exit 1
    fi
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

# Strip all non-alphanumeric characters from the hostname
CLEAN_HOSTNAME=$(echo "$HOSTNAME" | tr -cd '[:alnum:]')

# Strip all non-alphanumeric characters from the IP address
CLEAN_IP=$(echo "$ROUTER" | tr -cd '[:alnum:]')

# Combine the cleaned hostname and IP if no filename is provided
if [[ -z "$BACKUP_FILENAME" ]]; then
    CLEAN_NAME="${CLEAN_HOSTNAME}${CLEAN_IP}"
    # Create a timestamp for the backup filename
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    # Create the backup filename
    BACKUP_FILENAME="mikrotik-${CLEAN_NAME}-${TIMESTAMP}.backup"
else
    # Append ".backup" extension if it's not already included
    if [[ "$BACKUP_FILENAME" != *.backup ]]; then
        BACKUP_FILENAME="${BACKUP_FILENAME}.backup"
    fi
fi

# Create the backups directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create the backup on the router
ssh "$USERNAME@$ROUTER" "system backup save name=$BACKUP_FILENAME"

# Wait until the backup file is available on the router before downloading
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

# Introduce a short delay before attempting to remove the file
sleep 2

# Attempt to remove the backup file from the router, and add debugging
echo "Attempting to remove backup file: $BACKUP_FILENAME"
ssh "$USERNAME@$ROUTER" "file remove $BACKUP_FILENAME" || echo "Failed to remove backup file: $BACKUP_FILENAME"

echo "Backup completed and saved as $BACKUP_DIR/$BACKUP_FILENAME"