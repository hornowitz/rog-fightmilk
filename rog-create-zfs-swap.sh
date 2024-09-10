#!/bin/bash

# =============================================================================
# Script Name: rog-create-zfs-swap.sh
# Version: 1.6
# Author: Dominic Horn
# Date: 2024-08-19
#
# Description:
# This script manages swap file creation and configuration on a ZFS dataset
# to avoid ZFS and swap deadlocks. It also allows creating and configuring
# the ZFS dataset with customizable attributes.
#
# Requirements:
# - A ZFS dataset with specific options (can be created by this script).
# 
# Usage:
# ./rog-create-zfs-swap.sh -z <zpool> -d <dataset> -s <swap_size> [-c] [options]
# Example: ./rog-create-zfs-swap.sh -z zfspool -d swap -s 7G -c -D off -C zle -L throughput -A off -R off -x 8k -S off -H fletcher4 -P none -Q none -Y always
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
DEFAULT_AUTO_SNAPSHOT="false"
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
Usage: $0 -z <zpool> -d <dataset> -s <swap_size> [-c] [options]
Example: $0 -z zfspool -d swap -s 7G -c -D off -C zle -L throughput -A off -R off -x 8k -S off -H fletcher4 -P none -Q none -Y always
  -z <zpool>            : ZFS pool name
  -d <dataset>          : ZFS dataset name
  -s <swap_size>        : Swap file size (e.g., 7G)
  -c                    : Create the ZFS dataset if it does not exist
  -D <dedup>            : Dataset deduplication (default: $DEFAULT_DEDUP)
  -C <compression>      : Dataset compression (default: $DEFAULT_COMPRESSION)
  -L <logbias>          : Dataset log bias (default: $DEFAULT_LOGBIAS)
  -A <atime>            : Dataset atime (default: $DEFAULT_ATIME)
  -R <relatime>         : Dataset relatime (default: $DEFAULT_RELATIME)
  -x <recordsize>       : Dataset record size (default: $DEFAULT_RECORDSIZE)
  -S <auto_snapshot>    : Dataset auto snapshot (default: $DEFAULT_AUTO_SNAPSHOT)
  -H <checksum>         : Dataset checksum (default: $DEFAULT_CHECKSUM)
  -P <primarycache>     : Dataset primary cache (default: $DEFAULT_PRIMARYCACHE)
  -Q <secondarycache>   : Dataset secondary cache (default: $DEFAULT_SECONDARYCACHE)
  -Y <sync>             : Dataset sync (default: $DEFAULT_SYNC)
EOF
    exit 1
}

# Parse command-line arguments
CREATE_DATASET=false
while getopts "z:d:s:cD:C:L:A:R:x:S:H:P:Q:Y:" opt; do
    case $opt in
        z) ZPOOL="$OPTARG" ;;
        d) DATASET="$OPTARG" ;;
        s) SWAP_SIZE="$OPTARG" ;;
        c) CREATE_DATASET=true ;;
        D) DEDUP="$OPTARG" ;;
        C) COMPRESSION="$OPTARG" ;;
        L) LOGBIAS="$OPTARG" ;;
        A) ATIME="$OPTARG" ;;
        R) RELATIME="$OPTARG" ;;
        x) RECORDSIZE="$OPTARG" ;;
        S) AUTO_SNAPSHOT="$OPTARG" ;;
        H) CHECKSUM="$OPTARG" ;;
        P) PRIMARYCACHE="$OPTARG" ;;
        Q) SECONDARYCACHE="$OPTARG" ;;
        Y) SYNC="$OPTARG" ;;
        *) usage ;;
    esac
done

# Set default values if not overridden
DEDUP=${DEDUP:-$DEFAULT_DEDUP}
COMPRESSION=${COMPRESSION:-$DEFAULT_COMPRESSION}
LOGBIAS=${LOGBIAS:-$DEFAULT_LOGBIAS}
ATIME=${ATIME:-$DEFAULT_ATIME}
RELATIME=${RELATIME:-$DEFAULT_RELATIME}
RECORDSIZE=${RECORDSIZE:-$DEFAULT_RECORDSIZE}
AUTO_SNAPSHOT=${AUTO_SNAPSHOT:-$DEFAULT_AUTO_SNAPSHOT}
CHECKSUM=${CHECKSUM:-$DEFAULT_CHECKSUM}
PRIMARYCACHE=${PRIMARYCACHE:-$DEFAULT_PRIMARYCACHE}
SECONDARYCACHE=${SECONDARYCACHE:-$DEFAULT_SECONDARYCACHE}
SYNC=${SYNC:-$DEFAULT_SYNC}

# Check if required arguments are provided
if [ -z "$ZPOOL" ] || [ -z "$DATASET" ] || [ -z "$SWAP_SIZE" ]; then
    usage
fi

# Function to create or check the ZFS dataset
create_or_check_dataset() {
    if $CREATE_DATASET; then
        if zfs list "$ZPOOL/$DATASET" >/dev/null 2>&1; then
            log_message "ZFS dataset $ZPOOL/$DATASET already exists."
            
            # Check if the mountpoint is correct
            local MOUNTPOINT=$(zfs get -H -o value mountpoint "$ZPOOL/$DATASET")
            if [ "$MOUNTPOINT" != "/swap" ]; then
                log_message "Incorrect mountpoint for $ZPOOL/$DATASET. Expected /swap but found $MOUNTPOINT."
                exit 1
            fi

            log_message "ZFS dataset $ZPOOL/$DATASET is correctly mounted at $MOUNTPOINT."

            # Check if the swap file exists and continue
            if [ -f /swap/swapfile ]; then
                log_message "Swap file /swap/swapfile already exists."
                return
            else
                log_message "Swap file /swap/swapfile does not exist. Creating it now."
            fi
        else
            log_message "Creating ZFS dataset $ZPOOL/$DATASET with attributes:"
            log_message "  dedup=$DEDUP"
            log_message "  compression=$COMPRESSION"
            log_message "  logbias=$LOGBIAS"
            log_message "  atime=$ATIME"
            log_message "  relatime=$RELATIME"
            log_message "  recordsize=$RECORDSIZE"
            log_message "  auto_snapshot=$AUTO_SNAPSHOT"
            log_message "  checksum=$CHECKSUM"
            log_message "  primarycache=$PRIMARYCACHE"
            log_message "  secondarycache=$SECONDARYCACHE"
            log_message "  sync=$SYNC"

            zfs create -o mountpoint=/swap -o dedup="$DEDUP" -o compression="$COMPRESSION" \
            -o logbias="$LOGBIAS" -o atime="$ATIME" -o relatime="$RELATIME" -o recordsize="$RECORDSIZE" \
            -o com.sun:auto-snapshot="$AUTO_SNAPSHOT" -o checksum="$CHECKSUM" -o primarycache="$PRIMARYCACHE" \
            -o secondarycache="$SECONDARYCACHE" -o sync="$SYNC" "$ZPOOL/$DATASET"

            log_message "ZFS dataset $ZPOOL/$DATASET created."
        fi
    fi
}

# Run the dataset creation or check function
create_or_check_dataset

# Check if /swap is a mount point
if mountpoint -q /swap; then
    log_message "/swap is a mount point."

    # Remove the existing swap file
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

    # Set up a loop device for the swap file
    losetup /dev/loop1907 /swap/swapfile
    log_message "Loop device /dev/loop1907 set up for /swap/swapfile"

    # Enable the swap file
    swapon /dev/loop1907
    log_message "Swap enabled on /dev/loop1907"
else
    log_message "/swap is not a mount point. Exiting."
    echo "/swap is not a mount point. Exiting."
fi

