output "master_node_ssh_command" {
  value = "ssh -i ${local_file.private_key.filename} ${var.admin_username}@${azurerm_public_ip.master_node_public_ip.ip_address}"
}

output "request_kubeconfig" {
  value = "ssh -i ${local_file.request_kubeconfig_user_private_key.filename} ${local.request_kubeconfig_user}@${azurerm_public_ip.master_node_public_ip.ip_address}"
}

output "request_kubeconfig_user_private_key_path" {
  value = local_file.request_kubeconfig_user_private_key.filename
}

output "request_kubeconfig_user" {
  value = local.request_kubeconfig_user
}

output "master_node_public_ip_address" {
  value = azurerm_public_ip.master_node_public_ip.ip_address
}

output "worker_node_private_ip_addressess" {
  value = azurerm_network_interface.worker_node_network_interface[*].private_ip_address
}
