remote_state {
  backend = "azurerm"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    resource_group_name  = "devops-iac"
    storage_account_name = "devopsiactf"
    container_name       = "terragrunt-test-dev"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF

terraform {
  required_version = "~> 1.12.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.30.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4.0"
    }
  }
}

provider "azurerm" {
  features {}
  # subscription_id = var.subscription_id
}
EOF
}

locals {
  source = "../..//modules"
  root_tags = {
    Project    = "Practice-CKA"
    ProvidedBy = "Terraform"
  }
  resource_group_name = "devops-iac"
  location = "eastus"
}
