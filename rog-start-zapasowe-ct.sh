#!/bin/bash

# Script Header
# Author: Dominic Horn
# Version: 1.1
# Date: 2024-08-19
# Description: Opens a LUKS-encrypted volume, imports a ZFS pool,
# mounts a ZFS filesystem, and starts a container. Logs all operations to syslog.

# Configuration
KEY_FILE="/root/rogaliki-lnp-key"
LUKS_NAME="rog-zapasowe-luks"
DISK_ID="/dev/disk/by-id/ata-WDC_WD60EZAZ-00SF3B0_WD-WX22DA1LTKJE"
POOL_NAME="rog-zapasowe"
FILESYSTEM="rog-zapasowe/urbackup"
CONTAINER_ID="10197005"
SCRIPT_NAME="rog-start-zapasowe-ct"

# Log function
log_message() {
    local level="$1"
    local message="$2"
    logger -t "$SCRIPT_NAME" -p "$level" "$message"
}

# Run command and log result
run_command() {
    local command="$1"
    local success_message="$2"
    local error_message="$3"

    if eval "$command"; then
        log_message "info" "$success_message"
    else
        log_message "err" "$error_message"
        exit 1
    fi
}

# Main execution
log_message "info" "Starting script..."

# Open the LUKS-encrypted volume
log_message "info" "Opening LUKS-encrypted volume..."
run_command "cryptsetup luksOpen '$DISK_ID' '$LUKS_NAME' --key-file='$KEY_FILE'" \
    "LUKS volume opened successfully." \
    "Failed to open LUKS volume. Exiting."

# Import the ZFS pool
log_message "info" "Importing ZFS pool..."
run_command "zpool import -N '$POOL_NAME' -f" \
    "ZFS pool imported successfully." \
    "Failed to import ZFS pool. Exiting."

# Mount the ZFS filesystem
log_message "info" "Mounting ZFS filesystem..."
run_command "zfs mount '$FILESYSTEM'" \
    "ZFS filesystem mounted successfully." \
    "Failed to mount ZFS filesystem. Exiting."

# Start the container
log_message "info" "Starting the container..."
run_command "pct start '$CONTAINER_ID'" \
    "Container started successfully." \
    "Failed to start container. Exiting."

log_message "info" "Script completed successfully."

