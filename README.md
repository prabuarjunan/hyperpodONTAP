# AWS SageMaker HyperPod with FSx for ONTAP

This repository contains instructions and scripts for creating an AWS SageMaker HyperPod cluster with FSx for ONTAP storage integration.

## Prerequisites

- AWS CLI installed and configured
- Appropriate IAM permissions to create SageMaker HyperPod clusters and FSx file systems
- An Amazon S3 bucket to store the lifecycle configuration scripts

## Architecture Overview

The solution creates a SageMaker HyperPod cluster with:
- Compute instances for ML workloads
- FSx for ONTAP for high-performance, scalable storage
- VPC endpoints for secure network connectivity

## Setup Instructions

### 1. Prepare Your VPC

Ensure your VPC has the necessary endpoints for HyperPod to function properly:

```bash
# Create SSM endpoints (required for SSH connectivity)
aws ec2 create-vpc-endpoint --vpc-id YOUR_VPC_ID \
  --service-name com.amazonaws.YOUR_REGION.ssm \
  --vpc-endpoint-type Interface \
  --subnet-ids YOUR_PRIVATE_SUBNET_IDS \
  --security-group-ids YOUR_SECURITY_GROUP_ID

# Create SSM messages endpoint
aws ec2 create-vpc-endpoint --vpc-id YOUR_VPC_ID \
  --service-name com.amazonaws.YOUR_REGION.ssmmessages \
  --vpc-endpoint-type Interface \
  --subnet-ids YOUR_PRIVATE_SUBNET_IDS \
  --security-group-ids YOUR_SECURITY_GROUP_ID

# Create S3 endpoint (required for script access)
aws ec2 create-vpc-endpoint --vpc-id YOUR_VPC_ID \
  --service-name com.amazonaws.YOUR_REGION.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids YOUR_ROUTE_TABLE_ID
```

### 2. Create FSx for ONTAP File System

```bash
aws fsx create-file-system \
  --file-system-type ONTAP \
  --ontap-configuration '{
    "DeploymentType": "MULTI_AZ_1",
    "AutomaticBackupRetentionDays": 7,
    "DailyAutomaticBackupStartTime": "01:00",
    "WeeklyMaintenanceStartTime": "7:01:00",
    "ThroughputCapacity": 512,
    "PreferredSubnetId": "SUBNET_ID_1",
    "RouteTableIds": ["ROUTE_TABLE_ID"],
    "FsxAdminPassword": "PASSWORD"
  }' \
  --subnet-ids SUBNET_ID_1 SUBNET_ID_2 \
  --security-group-ids SECURITY_GROUP_ID \
  --storage-capacity 1024 \
  --tags Key=Name,Value=HyperPod-ONTAP
```

Note the file system ID that's returned.

### 3. Create FSx for ONTAP SVM and Volume

```bash
# Create SVM
aws fsx create-storage-virtual-machine \
  --file-system-id YOUR_FSX_ID \
  --name hyperpod-svm \
  --root-volume-security-style UNIX

# Create volume
aws fsx create-volume \
  --volume-type ONTAP \
  --name hyperpod-vol \
  --ontap-configuration '{
    "JunctionPath": "/hyperpod",
    "SizeInMegabytes": 102400,
    "StorageVirtualMachineId": "YOUR_SVM_ID",
    "StorageEfficiencyEnabled": true,
    "TieringPolicy": {
      "Name": "AUTO",
      "CoolingPeriod": 31
    }
  }'
```

### 4. Prepare FSx Mount Script

Create a file named `fsx-ontap-mount.sh` with the following content:

```bash
#!/bin/bash

# Mount FSx for ONTAP to HyperPod cluster
# This script runs as part of the HyperPod lifecycle

set -ex

# Configuration
FSX_DNS_NAME="YOUR_FSX_DNS_NAME"  # e.g., svm-abcdef01234567890.fs-abcdef01234567890.fsx.us-west-2.amazonaws.com
MOUNT_POINT="/fsx"
EXPORT_PATH="/hyperpod"

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

### 5. Upload Script to S3

```bash
aws s3 cp fsx-ontap-mount.sh s3://YOUR_BUCKET_NAME/scripts/
```

### 6. Create HyperPod Cluster

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
    "vpcId": "YOUR_VPC_ID",
    "subnetIds": ["SUBNET_ID_1", "SUBNET_ID_2"],
    "securityGroupIds": ["SG_ID"]
  }'
```

## Connecting to Your HyperPod Cluster

Use the provided `easy-ssh.sh` script to connect to your HyperPod cluster:

```bash
./easy-ssh.sh -p AWS_PROFILE -r REGION YOUR_CLUSTER_NAME
```

If you encounter connection issues, make sure:
1. Your VPC has the necessary endpoints (SSM, SSM Messages)
2. Your IAM role has permission to use SSM
3. The instance is running and the SSM agent is active

## Verifying FSx Mount

After connecting to the cluster, verify that FSx is correctly mounted:

```bash
df -h | grep fsx
```

You should see output showing your FSx filesystem mounted at `/fsx`.

## Troubleshooting

### Common Issues:

1. **SSM Connection Failures**
   - Ensure VPC endpoints for SSM and SSM Messages are created
   - Check IAM permissions for SSM
   - Verify the instance is running and has network connectivity

2. **FSx Mount Issues**
   - Check the NFS export policy on the FSx for ONTAP SVM
   - Verify network connectivity between the HyperPod instances and FSx
   - Check CloudWatch logs for mount script execution errors

3. **Performance Issues**
   - Adjust the NFS mount options for optimal performance
   - Consider FSx for ONTAP performance capacity adjustments
   - Verify network bandwidth between compute instances and FSx

## Additional Resources

- [AWS SageMaker HyperPod Documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod.html)
- [FSx for ONTAP User Guide](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/what-is-fsx-ontap.html)
- [Optimizing NFS Performance with FSx for ONTAP](https://aws.amazon.com/blogs/storage/optimize-nfs-performance-with-fsx-for-ontap/)
