#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 -u <username> -ip <router-ip-address> [-keyfile <public-key-filename>]"
    exit 1
}

# Initialize variables
PUBLIC_KEY_FILE="~/.ssh/id_rsa.pub"  # Default public key file
ADMIN_USERNAME="admin"  # Admin username is fixed
MAX_RETRIES=5  # Maximum number of retries to check for the key file on the router
SLEEP_INTERVAL=2  # Time to wait (in seconds) between retries

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -u) USERNAME="$2"; shift ;;
        -ip) ROUTER="$2"; shift ;;
        -keyfile) PUBLIC_KEY_FILE="$2"; shift ;;
        *) usage ;;  # If an unknown option is passed, show usage
    esac
    shift
done

# Check if required parameters are provided
if [[ -z "$USERNAME" || -z "$ROUTER" ]]; then
    usage
fi

# Expand tilde in PUBLIC_KEY_FILE if present
PUBLIC_KEY_FILE="${PUBLIC_KEY_FILE/#\~/$HOME}"

# Check if the public key file exists
if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
    echo "Public key file '$PUBLIC_KEY_FILE' not found!"
    exit 1
fi

# If the username is "admin", prompt for the password
if [[ "$USERNAME" == "$ADMIN_USERNAME" ]]; then
    read -s -p "Enter your admin password: " ADMIN_PASSWORD
    echo  # To move to a new line after password input
fi

# Prompt user to confirm details
echo "Please confirm the following details:"
echo "------------------------------------"
echo "Username: $USERNAME"
echo "Router IP/Hostname: $ROUTER"
echo "Public Key File: $PUBLIC_KEY_FILE"
echo "------------------------------------"
read -p "Are these details correct? (y/n): " CONFIRM

# If user confirms, proceed with copying the key and setting up SSH
if [[ $CONFIRM == "y" || $CONFIRM == "Y" ]]; then
    # Copy the public key file to the router using SCP
    scp "$PUBLIC_KEY_FILE" "$ADMIN_USERNAME@$ROUTER:/id_rsa.pub"

    # Wait until the key file is available on the router before importing
    RETRIES=0
    while true; do
        FILE_EXISTS=$(ssh "$ADMIN_USERNAME@$ROUTER" "file print where name=id_rsa.pub" | grep -q "id_rsa.pub" && echo "yes" || echo "no")
        if [[ "$FILE_EXISTS" == "yes" ]]; then
            echo "Public key file found on router. Proceeding with import..."
            break
        fi
        
        if [[ $RETRIES -ge $MAX_RETRIES ]]; then
            echo "Failed to find public key file on the router after $MAX_RETRIES attempts. Aborting."
            exit 1
        fi

        echo "Public key file not found on router. Retrying in $SLEEP_INTERVAL seconds..."
        sleep $SLEEP_INTERVAL
        ((RETRIES++))
    done

    # Execute the command to import the SSH key and set SSH to allow password login
    if [[ "$USERNAME" == "$ADMIN_USERNAME" ]]; then
        ssh "$ADMIN_USERNAME@$ROUTER" "/user ssh-keys import public-key-file=id_rsa.pub user=$USERNAME; /ip ssh set always-allow-password-login=yes" <<< "$ADMIN_PASSWORD"
    else
        ssh "$ADMIN_USERNAME@$ROUTER" "/user ssh-keys import public-key-file=id_rsa.pub user=$USERNAME; /ip ssh set always-allow-password-login=yes"
    fi

    # Remove the public key file from the router (optional)
    ssh "$ADMIN_USERNAME@$ROUTER" "/file remove id_rsa.pub"

    echo "SSH key imported for user '$USERNAME' and password login setting updated on $ROUTER."
else
    echo "Operation canceled."
    exit 0
fi
