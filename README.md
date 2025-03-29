# AWS SageMaker HyperPod with Existing FSx for ONTAP

This repository documents how to create an AWS SageMaker HyperPod cluster that connects to an existing FSx for ONTAP file system.

## Prerequisites

- AWS CLI installed and configured
- Appropriate IAM permissions to create SageMaker HyperPod clusters
- An existing FSx for ONTAP file system
- An Amazon S3 bucket to store the lifecycle configuration script

## Architecture Overview

This solution connects a SageMaker HyperPod cluster to:
- An existing FSx for ONTAP file system
- Using the same VPC and subnet as the FSx for ONTAP
- With VPC endpoints for secure network connectivity

## Setup Instructions

### 1. Configure VPC Endpoints (Critical)

To ensure connectivity to your HyperPod cluster, you must create these VPC endpoints in the same VPC as your FSx for ONTAP:

```bash
# Create an S3 Gateway endpoint for script access
aws ec2 create-vpc-endpoint \
  --vpc-id YOUR_VPC_ID \
  --service-name com.amazonaws.YOUR_REGION.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids YOUR_ROUTE_TABLE_ID

# Create an SSM Messages Interface endpoint for session connectivity
aws ec2 create-vpc-endpoint \
  --vpc-id YOUR_VPC_ID \
  --service-name com.amazonaws.YOUR_REGION.ssmmessages \
  --vpc-endpoint-type Interface \
  --subnet-ids YOUR_SUBNET_IDS \
  --security-group-ids YOUR_SECURITY_GROUP_ID
```

> **Note:** Without these VPC endpoints, you won't be able to connect to your HyperPod cluster or access your S3-hosted scripts.

### 2. Prepare FSx Mount Script

Create a file named `fsx-ontap-mount.sh` with the following content:

```bash
#!/bin/bash

# Mount existing FSx for ONTAP to HyperPod cluster

set -ex

# Configuration - Update these values for your environment
FSX_DNS_NAME="YOUR_SVM_DNS_NAME"  # e.g., svm-123456789.fs-123456789.fsx.us-east-1.amazonaws.com
MOUNT_POINT="/fsx"
EXPORT_PATH="/your_volume_junction_path"

# Create mount point if it doesn't exist
mkdir -p $MOUNT_POINT

# Install NFS client if needed
apt-get update
apt-get install -y nfs-common

# Mount the FSx for ONTAP filesystem
mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${FSX_DNS_NAME}:${EXPORT_PATH} ${MOUNT_POINT}

# Add to fstab for persistence across reboots
echo "${FSX_DNS_NAME}:${EXPORT_PATH} ${MOUNT_POINT} nfs nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" >> /etc/fstab

# Set appropriate permissions
chmod 777 $MOUNT_POINT

# Verify mount
df -h | grep $MOUNT_POINT
```

### 3. Upload Script to S3

```bash
aws s3 cp fsx-ontap-mount.sh s3://YOUR_BUCKET_NAME/scripts/
```

### 4. Create HyperPod Cluster Using Existing FSx VPC and Subnet

```bash
aws sagemaker create-cluster \
  --cluster-name YOUR_CLUSTER_NAME \
  --instance-groups '[
    {
      "instanceGroupName": "controller-machine",
      "instanceType": "ml.c5.4xlarge",
      "instanceCount": 1,
      "lifecycleConfig": {
        "sourceS3Uri": "s3://YOUR_BUCKET_NAME/scripts/fsx-ontap-mount.sh",
        "onStart": {
          "scriptName": "fsx-ontap-mount.sh"
        }
      }
    },
    {
      "instanceGroupName": "ex2-worker-group",
      "instanceType": "ml.p4d.24xlarge",
      "instanceCount": 2,
      "lifecycleConfig": {
        "sourceS3Uri": "s3://YOUR_BUCKET_NAME/scripts/fsx-ontap-mount.sh",
        "onStart": {
          "scriptName": "fsx-ontap-mount.sh"
        }
      }
    }
  ]' \
  --virtual-private-cloud '{
    "vpcId": "YOUR_FSX_VPC_ID",
    "subnetIds": ["YOUR_FSX_SUBNET_ID"],
    "securityGroupIds": ["YOUR_SECURITY_GROUP_ID"]
  }'
```

> **Important:** Use the same VPC, subnet(s), and security groups as your FSx for ONTAP file system.

## Connecting to Your HyperPod Cluster

Once the VPC endpoints are properly configured, you can connect directly using:

```bash
aws ssm start-session \
  --target s
