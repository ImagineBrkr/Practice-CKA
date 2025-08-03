#!/bin/bash

terraform version || { echo "Terraform is not installed"; exit 1; }
terragrunt -v || { echo "Terragrunt is not installed"; exit 1; }

source ./variables.sh

export TG_WORKING_DIR=$PWD/infra/terragrunt-deploy
export TG_NO_AUTO_INIT=true
export TG_NON_INTERACTIVE=true

# terragrunt destroy --all
terragrunt destroy --working-dir "infra/terragrunt-deploy/cluster" -auto-approve
