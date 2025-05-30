data "azurerm_resource_group" "main_resource_group" {
  name = var.resource_group_name
}

locals {
  master_node_name = "${var.project_name}-master-node"
  worker_node_name = "${var.project_name}-worker-node"
}
