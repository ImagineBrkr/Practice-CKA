#!/bin/bash

terraform version || { echo "Terraform is not installed"; exit 1; }
terragrunt -v || { echo "Terragrunt is not installed"; exit 1; }

source ./variables.sh

export TG_WORKING_DIR=$PWD/infra/terragrunt-deploy
export TG_NO_AUTO_INIT=true
export TG_NON_INTERACTIVE=true

terragrunt destroy --all -target azurerm_linux_virtual_machine.master_node_vm
terragrunt apply --all

$MASTER_NODE_PUBLIC_IP=$(terragrunt output --all master_node_public_ip_address --log-level error)

ssh-keygen -f "~/.ssh/known_hosts" -R $MASTER_NODE_PUBLIC_IP
