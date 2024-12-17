#!/bin/bash

KEY_NAME="my-key-pair"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"

# Check if the key pair already exists in AWS
EXISTING_KEY=$(aws ec2 describe-key-pairs --key-name $KEY_NAME --query 'KeyPairs[0].KeyName' --output text 2>/dev/null)

if [ "$EXISTING_KEY" == "$KEY_NAME" ]; then
    echo "Key pair $KEY_NAME already exists in AWS."
else
    echo "Creating new key pair $KEY_NAME."
    aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_FILE
    chmod 400 $KEY_FILE
    echo "Key pair created and saved to $KEY_FILE."
fi
