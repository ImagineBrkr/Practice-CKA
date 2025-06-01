remote_state {
  backend = "azurerm"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    resource_group_name  = "kube-cluster-cka"
    storage_account_name = "kubeclusterckatf"
    container_name       = "practice-cka-tf"
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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
  }
}

provider "azurerm" {
  features {}
  use_cli = false
  use_msi       = false
  resource_provider_registrations = "none"
}

provider "tls" {}

provider "local" {}
EOF
}

locals {
  source = "../..//modules"
  root_tags = {
    Project    = "Practice-CKA"
    ProvidedBy = "Terraform"
  }
  resource_group_name = "kube-cluster-cka"
  location            = "eastus"
}
