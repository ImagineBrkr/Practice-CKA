#!/bin/bash
set -e

SSH_KEY_PATH=$1
SSH_USER=$2
SSH_HOST=$3

# Validate required parameters
if [ -z "$SSH_KEY_PATH" ] || [ -z "$SSH_USER" ] || [ -z "$SSH_HOST" ]; then
    echo "Usage: $0 <key-path> <user> <host>"
    exit 1
fi

# Validate SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH key file not found at $SSH_KEY_PATH"
    exit 1
fi

# Retry configuration
max_attempts=10
delay=10
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt/$max_attempts: Trying to obtain kubeconfig..."
    if ssh -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        "${SSH_USER}@${SSH_HOST}" > "${TF_VAR_kube_config_path}"; then
        
        echo "Successfully obtained kubeconfig"
        exit 0
    fi
    
    echo "Failed to obtain kubeconfig, waiting $delay seconds before retry..."
    sleep $delay
    attempt=$((attempt + 1))
done

echo "Error: Failed to obtain kubeconfig after $max_attempts attempts"
exit 1
