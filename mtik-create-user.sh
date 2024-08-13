#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 -u <new-username> -ip <router-ip-address> [-p <password>] [-g <group>]"
    exit 1
}

# Initialize variables
GROUP="read"  # Default group is 'read'

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -u) NEW_USERNAME="$2"; shift ;;
        -ip) ROUTER="$2"; shift ;;
        -p) PASSWORD="$2"; shift ;;
        -g) GROUP="$2"; shift ;;
        *) usage ;;  # If an unknown option is passed, show usage
    esac
    shift
done

# Check if required parameters are provided
if [[ -z "$NEW_USERNAME" || -z "$ROUTER" ]]; then
    usage
fi

# Prompt for password if not provided
if [[ -z "$PASSWORD" ]]; then
    read -s -p "Enter password: " PASSWORD
    echo
fi

# Prompt user to confirm details
echo "Please confirm the following details:"
echo "------------------------------------"
echo "Router IP/Hostname: $ROUTER"
echo "New Username: $NEW_USERNAME"
echo "Group: $GROUP"
echo "------------------------------------"
read -p "Are these details correct? (y/n): " CONFIRM

# If user confirms, proceed with creating the user
if [[ $CONFIRM == "y" || $CONFIRM == "Y" ]]; then
    # SSH into the MikroTik router and create the new user
    ssh admin@$ROUTER << EOF
/user add name=$NEW_USERNAME group=$GROUP password=$PASSWORD
EOF

    # Verify if the user was created successfully
    if ssh admin@$ROUTER "/user print" | grep -q "$NEW_USERNAME"; then
        echo "User '$NEW_USERNAME' created successfully on router '$ROUTER' with group '$GROUP'."
    else
        echo "Failed to create user '$NEW_USERNAME' on router '$ROUTER'."
    fi
else
    echo "Operation canceled."
    exit 0
fi
