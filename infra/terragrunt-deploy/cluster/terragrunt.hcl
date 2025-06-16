terraform {
  source = "${local.root_locals.locals.source}/azure-cluster"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}


locals {
  root_locals = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  tags = {
    TerragruntUnit = "cluster"
  }
  default_tags = merge(local.root_locals.locals.root_tags,
  local.tags)
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


inputs = {
  project_name        = "azure-kubernetes-cluster"
  resource_group_name = local.root_locals.locals.resource_group_name
  location            = local.root_locals.locals.location
  woker_node_count    = 1

  private_key_path                         = "${get_terragrunt_dir()}/../../../private_key.pem"
  request_kubeconfig_user_private_key_path = "${get_terragrunt_dir()}/../../../request_kubeconfig_user_private_key.pem"

  default_tags = local.default_tags
}
