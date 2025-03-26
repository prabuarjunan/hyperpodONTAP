#!/bin/bash
set -e

# Set environment variables
export PROVISIONING_PARAMETERS_PATH="./provisioning_params.json"
export RESOURCE_CONFIG_PATH="/opt/ml/config/resource_config.json"

# Execute the lifecycle script
python3 ./lifecycle_script.py -rc $RESOURCE_CONFIG_PATH -pp $PROVISIONING_PARAMETERS_PATH
