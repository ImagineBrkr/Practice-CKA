#!/bin/bash

terraform version || { echo "Terraform is not installed"; exit 1; }
terragrunt -v || { echo "Terragrunt is not installed"; exit 1; }

source ./variables.sh

KUBECONFIG_PATH="$PWD/admin.kubeconfig"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export TG_WORKING_DIR="$SCRIPT_DIR/infra/terragrunt-deploy"
export TG_NO_AUTO_INIT=true
export TG_NON_INTERACTIVE=true
export TF_VAR_private_key_path="$SCRIPT_DIR/private_key.pem"
export TF_VAR_request_kubeconfig_user_private_key_path="$SCRIPT_DIR/request_kubeconfig_user_private_key.pem"

# terragrunt init --all 

terragrunt hcl fmt
terraform fmt -recursive

# terragrunt apply --all
terragrunt apply --working-dir "infra/terragrunt-deploy/cluster-configuration" -auto-approve
