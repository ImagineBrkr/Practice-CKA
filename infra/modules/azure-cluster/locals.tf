data "azurerm_resource_group" "main_resource_group" {
  name = var.resource_group_name
}

locals {
  master_node_name        = "${var.project_name}-master-node"
  worker_node_name_prefix = "${var.project_name}-worker-node"

  master_security_group_name = "${local.master_node_name}-asg"
  worker_security_group_name = "${local.worker_node_name_prefix}-asg"

  master_network_interface_name        = "${local.master_node_name}-nic"
  worker_network_interface_name_prefix = "${local.worker_node_name_prefix}-nic"

  master_node_private_ip = "10.0.0.4"

  public_ip_name = "${var.project_name}-public_ip"

  # generate_worker_certs script
  generate_certs_user = "certs-user"

  # Requesting cluster kubeconfig
  request_kubeconfig_user = "kubeconfig-user"
}
