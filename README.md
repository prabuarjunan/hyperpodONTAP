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

Create a file named `fsx-ontap-mount.sh` with the following content, 
The shell script can be found at the following location:

[fsx-ontap-mount.sh]([scripts/example.py](https://github.com/prabuarjunan/hyperpodONTAP/blob/main/fsx-ontap-mount.sh))


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
