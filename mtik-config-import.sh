#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 -ip <router-ip-address> [-u <username>] -in <rsc-file>"
    exit 1
}

# Default values
USERNAME="admin"
RSC_FILE=""
ROUTER=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -ip) ROUTER="$2"; shift ;;
        -u) USERNAME="$2"; shift ;;
        -in) RSC_FILE="$2"; shift ;;
        *) usage ;;  # If an unknown option is passed, show usage
    esac
    shift
done

# Check if mandatory parameters are provided
if [[ -z "$ROUTER" || -z "$RSC_FILE" ]]; then
    usage
fi

# Check if the RSC file exists
if [[ ! -f "$RSC_FILE" ]]; then
    echo "Error: The specified file does not exist: $RSC_FILE"
    exit 1
fi

# Extract the base filename from the full path
BASE_NAME=$(basename "$RSC_FILE")

# Extract model and serial number from the RouterOS device and trim spaces
ROUTER_MODEL=$(ssh "$USERNAME@$ROUTER" "system routerboard print" | grep 'model:' | awk -F': ' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | tr -d '\r')
ROUTER_SERIAL=$(ssh "$USERNAME@$ROUTER" "system routerboard print" | grep 'serial-number:' | awk -F': ' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | tr -d '\r')

# Extract model and serial number from the .rsc file and trim spaces
RSC_MODEL=$(grep -i 'model =' "$RSC_FILE" | awk -F'=' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | tr -d '\r')
RSC_SERIAL=$(grep -i 'serial number =' "$RSC_FILE" | awk -F'=' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | tr -d '\r')

# Output the model and serial number values
echo "Router Model: '$ROUTER_MODEL', Router Serial: '$ROUTER_SERIAL'"
echo "RSC Model: '$RSC_MODEL', RSC Serial: '$RSC_SERIAL'"

# Check if any model or serial number is empty (blank)
if [[ -z "$ROUTER_MODEL" || -z "$ROUTER_SERIAL" || -z "$RSC_MODEL" || -z "$RSC_SERIAL" ]]; then
    echo "Error: One or more required fields (model or serial number) are empty."
    exit 1
fi

# Check if model or serial number is present and matches
if [[ "$ROUTER_MODEL" != "$RSC_MODEL" || "$ROUTER_SERIAL" != "$RSC_SERIAL" ]]; then
    echo "Warning: The model and/or serial number in the .rsc file do not match the router."
    read -p "Do you want to continue with the import? (yes/no) " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Import canceled."
        exit 0
    fi
fi

# Upload the RSC file to the router
scp "$RSC_FILE" "$USERNAME@$ROUTER:$BASE_NAME" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to upload the configuration file to the router."
    exit 1
fi

# Prompt the user to confirm proceeding with the import
echo "The file $BASE_NAME has been successfully uploaded to the router."
read -p "Do you want to proceed with the import? (yes/no) " CONFIRM_IMPORT
if [[ "$CONFIRM_IMPORT" != "yes" ]]; then
    echo "Import canceled."
    ssh "$USERNAME@$ROUTER" "file remove $BASE_NAME" > /dev/null 2>&1
    exit 0
fi

# Import the configuration file
echo "Importing configuration from $BASE_NAME..."
ssh "$USERNAME@$ROUTER" "import file=$BASE_NAME" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to import the configuration."
    exit 1
else
    echo "Configuration imported successfully."
fi

# Remove the RSC file from the router after import
ssh "$USERNAME@$ROUTER" "file remove $BASE_NAME" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Warning: Failed to remove the configuration file from the router."
else
    echo "Configuration file removed from the router."
fi