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

ssh -i "$SSH_KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${SSH_USER}@${SSH_HOST}" \
    > "${TF_VAR_kube_config_path}"
