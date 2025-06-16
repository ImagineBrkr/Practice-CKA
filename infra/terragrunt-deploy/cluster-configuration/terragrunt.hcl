terraform {
  source = "${local.root_locals.locals.source}/cluster-configuration"
  before_hook "obtain_kubeconfig" {
    commands = ["apply", "plan", "destroy"]
    execute  = ["${get_terragrunt_dir()}/../scripts/obtain_kubeconfig.sh", dependency.azure-cluster.outputs.request_kubeconfig_user_private_key_path, dependency.azure-cluster.outputs.request_kubeconfig_user, dependency.azure-cluster.outputs.master_node_public_ip_address]
  }
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "kube-provider" {
  path = find_in_parent_folders("kube-provider.hcl")
}

dependency "azure-cluster" {
  config_path = "../cluster"

  mock_outputs = {
    request_kubeconfig_user_private_key_path = "${get_terragrunt_dir()}/request_kubeconfig_user_private_key.pem"
    request_kubeconfig_user                  = "kubeconfig-user"
    master_node_public_ip_address            = "127.0.0.1"
  }

  mock_outputs_allowed_terraform_commands = ["plan", "validate", "import", "state", "init"]
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
  kube_config_path = "${get_terragrunt_dir()}/../../../admin.kubeconfig"

  default_tags = local.default_tags
}
