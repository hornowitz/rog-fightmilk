#!/bin/bash

# =============================================================================
# Script Name: rog-create-zfs-swap.sh
# Version: 1.8
# Author: Dominic Horn
# Date: 2024-09-20
#
# Description:
# This script manages swap file creation and configuration on multiple ZFS datasets
# to avoid ZFS and swap deadlocks. It can create and configure multiple ZFS datasets
# with customizable attributes, and dynamically assign loop devices for swap files.
#
# Requirements:
# - Multiple ZFS datasets with specific options (can be created by this script).
# 
# Usage:
# ./rog-create-zfs-swap.sh -z <zpool1,zpool2,...> -d <dataset> -s <swap_size> [-c] [options]
# Example: ./rog-create-zfs-swap.sh -z zfspool1,zfspool2 -d swap -s 7G -c -D off -C zle -L throughput -A off -R off -x 8k -S always
# =============================================================================

# Exit the script immediately if any command fails
set -e

# Default ZFS dataset attributes
DEFAULT_DEDUP="off"
DEFAULT_COMPRESSION="zle"
DEFAULT_LOGBIAS="throughput"
DEFAULT_ATIME="off"
DEFAULT_RELATIME="off"
DEFAULT_RECORDSIZE="8k"
DEFAULT_AUTO_SNAPSHOT="false"  # Changed to 'false'
DEFAULT_CHECKSUM="fletcher4"
DEFAULT_PRIMARYCACHE="none"
DEFAULT_SECONDARYCACHE="none"
DEFAULT_SYNC="always"

# Function to log messages
log_message() {
    local MESSAGE="$1"
    logger -t rog-create-zfs-swap.sh "$MESSAGE"
    echo "$MESSAGE"
}

# Function to handle errors with specific messages
error_exit() {
    local EXIT_CODE=$?
    local LINE_NUM=$1
    local CMD="${BASH_COMMAND}"
    log_message "Error on line $LINE_NUM: Command '$CMD' exited with status $EXIT_CODE"
    exit $EXIT_CODE
}

# Trap errors and call the error_exit function
trap 'error_exit $LINENO' ERR

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    log_message "This script must be run as root. Exiting."
    exit 1
fi

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 -z <zpool1,zpool2,...> -d <dataset> -s <swap_size> [-c] [options]
Example: $0 -z zfspool1,zfspool2 -d swap -s 7G -c -D off -C zle -L throughput -A off -R off -x 8k -S always

  -z <zpool1,zpool2,...> : ZFS pool names (comma-separated)
  -d <dataset>           : ZFS dataset name
  -s <swap_size>         : Swap file size (e.g., 7G)
  -c                     : Create the ZFS dataset if it does not exist
  -D <dedup>             : Set deduplication (default: $DEFAULT_DEDUP)
  -C <compression>       : Set compression (default: $DEFAULT_COMPRESSION)
  -L <logbias>           : Set logbias (default: $DEFAULT_LOGBIAS)
  -A <atime>             : Set atime (default: $DEFAULT_ATIME)
  -R <relatime>          : Set relatime (default: $DEFAULT_RELATIME)
  -x <recordsize>        : Set recordsize (default: $DEFAULT_RECORDSIZE)
  -S <sync>              : Set sync (default: $DEFAULT_SYNC)
  -H <checksum>          : Set checksum (default: $DEFAULT_CHECKSUM)
  -P <primarycache>      : Set primarycache (default: $DEFAULT_PRIMARYCACHE)
  -Q <secondarycache>    : Set secondarycache (default: $DEFAULT_SECONDARYCACHE)
  -Y <auto_snapshot>     : Set auto-snapshot (default: $DEFAULT_AUTO_SNAPSHOT)

EOF
    exit 1
}

# Parse command-line arguments
CREATE_DATASET=false
while getopts "z:d:s:cD:C:L:A:R:x:S:H:P:Q:Y:" opt; do
    case $opt in
        z) ZPOOLS="$OPTARG" ;;
        d) DATASET="$OPTARG" ;;
        s) SWAP_SIZE="$OPTARG" ;;
        c) CREATE_DATASET=true ;;
        D) DEFAULT_DEDUP="$OPTARG" ;;
        C) DEFAULT_COMPRESSION="$OPTARG" ;;
        L) DEFAULT_LOGBIAS="$OPTARG" ;;
        A) DEFAULT_ATIME="$OPTARG" ;;
        R) DEFAULT_RELATIME="$OPTARG" ;;
        x) DEFAULT_RECORDSIZE="$OPTARG" ;;
        S) DEFAULT_SYNC="$OPTARG" ;;
        H) DEFAULT_CHECKSUM="$OPTARG" ;;
        P) DEFAULT_PRIMARYCACHE="$OPTARG" ;;
        Q) DEFAULT_SECONDARYCACHE="$OPTARG" ;;
        Y) DEFAULT_AUTO_SNAPSHOT="$OPTARG" ;;
        *) usage ;;
    esac
done

# Check if required arguments are provided
if [ -z "$ZPOOLS" ] || [ -z "$DATASET" ] || [ -z "$SWAP_SIZE" ]; then
    usage
fi

# Convert comma-separated ZPOOLS into an array
IFS=',' read -r -a ZPOOL_ARRAY <<< "$ZPOOLS"

# Function to find the next available loop device
get_next_available_loop_device() {
    for i in $(seq 0 255); do
        LOOP_DEVICE="/dev/loop$i"
        if ! losetup "$LOOP_DEVICE" >/dev/null 2>&1; then
            echo "$LOOP_DEVICE"
            return
        fi
    done
    log_message "No available loop devices. Exiting."
    exit 1
}

# Function to create or check the ZFS dataset
create_or_check_dataset() {
    local ZPOOL=$1
    if $CREATE_DATASET; then
        if zfs list "$ZPOOL/$DATASET" >/dev/null 2>&1; then
            log_message "ZFS dataset $ZPOOL/$DATASET already exists."
        else
            log_message "Creating ZFS dataset $ZPOOL/$DATASET"
            zfs create -o mountpoint=/swap -o dedup="$DEFAULT_DEDUP" -o compression="$DEFAULT_COMPRESSION" \
                -o logbias="$DEFAULT_LOGBIAS" -o atime="$DEFAULT_ATIME" -o relatime="$DEFAULT_RELATIME" \
                -o recordsize="$DEFAULT_RECORDSIZE" -o com.sun:auto-snapshot="$DEFAULT_AUTO_SNAPSHOT" \
                -o checksum="$DEFAULT_CHECKSUM" -o primarycache="$DEFAULT_PRIMARYCACHE" \
                -o secondarycache="$DEFAULT_SECONDARYCACHE" -o sync="$DEFAULT_SYNC" "$ZPOOL/$DATASET"
            log_message "ZFS dataset $ZPOOL/$DATASET created."
        fi
    fi
}

# Main logic to handle multiple zpools
for ZPOOL in "${ZPOOL_ARRAY[@]}"; do
    log_message "Processing ZFS pool: $ZPOOL"

    # Create or check the dataset
    create_or_check_dataset "$ZPOOL"

    # Check if /swap is a mount point
    if mountpoint -q /swap; then
        log_message "/swap is a mount point."

        # Remove the existing swap file if necessary
        rm -f /swap/swapfile
        log_message "Removed existing /swap/swapfile"

        # Allocate a new swap file with the specified size
        fallocate -l "$SWAP_SIZE" /swap/swapfile
        log_message "Allocated a new $SWAP_SIZE /swap/swapfile"

        # Set the correct permissions
        chmod 0600 /swap/swapfile
        log_message "Set permissions on /swap/swapfile to 0600"

        # Create a swap area
        mkswap /swap/swapfile
        log_message "Created swap area on /swap/swapfile"

        # Get the next available loop device
        LOOP_DEVICE=$(get_next_available_loop_device)
        log_message "Using loop device: $LOOP_DEVICE"

        # Set up a loop device for the swap file
        losetup "$LOOP_DEVICE" /swap/swapfile
        log_message "Loop device $LOOP_DEVICE set up for /swap/swapfile"

        # Enable the swap file
        swapon "$LOOP_DEVICE"
        log_message "Swap enabled on $LOOP_DEVICE"
    else
        log_message "/swap is not a mount point. Exiting."
        exit 1
    fi
done
