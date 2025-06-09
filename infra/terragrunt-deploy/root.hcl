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

locals {
  source = "../..//modules"
  root_tags = {
    Project    = "Practice-CKA"
    ProvidedBy = "Terraform"
  }
  resource_group_name = "kube-cluster-cka"
  location            = "eastus"
}
