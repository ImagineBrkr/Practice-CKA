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


inputs = {
  project_name        = "azure-kubernetes-cluster"
  resource_group_name = local.root_locals.locals.resource_group_name
  location            = local.root_locals.locals.location
  woker_node_count    = 1

  private_key_path = "${get_parent_terragrunt_dir()}/../../private_key.pem"

  default_tags = local.default_tags
}
