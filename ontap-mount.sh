#!/bin/bash
# FSx for NetApp ONTAP Mount Script for SageMaker Hyperpod

# Enable error logging
set -e
exec > >(tee /var/log/fsx-ontap-mount.log) 2>&1

echo "Starting FSx for NetApp ONTAP mount process at $(date)"

# Configuration variables - MODIFY THESE
FSX_DNS_NAME="management.fs-0cd1ef29e47ff068a.fsx.us-east-1.amazonaws.com"
VOLUME_JUNCTION_PATH="/hyperpod"
MOUNT_POINT="/mnt/fsx-ontap"
NFS_OPTIONS="rw,hard,rsize=1048576,wsize=1048576,timeo=600,retrans=2,noresvport"

# Install NFS client if not already present
echo "Installing NFS utilities..."
if [ -f /etc/debian_version ]; then
    apt-get update && apt-get install -y nfs-common
elif [ -f /etc/redhat-release ]; then
    yum install -y nfs-utils
else
    echo "Unsupported OS. Please install NFS client manually."
    exit 1
fi

# Create mount directory if it doesn't exist
echo "Creating mount point at $MOUNT_POINT..."
mkdir -p $MOUNT_POINT

# Check if already mounted
if mount | grep -q "$MOUNT_POINT"; then
    echo "FSx for ONTAP is already mounted at $MOUNT_POINT"
else
    # Mount the FSx for ONTAP volume
    echo "Mounting FSx for ONTAP volume..."
    mount -t nfs -o $NFS_OPTIONS ${FSX_DNS_NAME}:${VOLUME_JUNCTION_PATH} $MOUNT_POINT
    
    if [ $? -eq 0 ]; then
        echo "Mount successful at $(date)"
    else
        echo "Mount failed at $(date)"
        exit 1
    fi
fi

# Make mount persistent across reboots
echo "Adding entry to /etc/fstab..."
if ! grep -q "$MOUNT_POINT" /etc/fstab; then
    echo "${FSX_DNS_NAME}:${VOLUME_JUNCTION_PATH} $MOUNT_POINT nfs $NFS_OPTIONS,_netdev 0 0" >> /etc/fstab
    echo "Added fstab entry"
else
    echo "fstab entry already exists"
fi

# Set appropriate permissions
echo "Setting permissions on mount point..."
chmod 777 $MOUNT_POINT

# Create a test file to verify write access
echo "Testing write access..."
echo "FSx for ONTAP mount test - $(date)" > $MOUNT_POINT/mount-test.txt

if [ $? -eq 0 ]; then
    echo "Write test successful"
else
    echo "Write test failed"
    exit 1
fi

# Display mount information
echo "Mount details:"
df -h $MOUNT_POINT

echo "FSx for NetApp ONTAP mount process completed successfully at $(date)"
