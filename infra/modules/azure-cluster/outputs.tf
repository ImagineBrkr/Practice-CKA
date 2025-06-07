output "master_node_ssh_command" {
  value = "ssh -i ${var.private_key_path} ${var.admin_username}@${azurerm_public_ip.master_node_public_ip.ip_address}"
}

output "master_node_public_ip_address" {
  value = azurerm_public_ip.master_node_public_ip.ip_address
}

output "worker_node_private_ip_addressess" {
  value = azurerm_network_interface.worker_node_network_interface[*].private_ip_address
}

output "kubeconfig_scp_command" {
  value = "scp -i ${local_file.private_key.filename} ${var.admin_username}@${azurerm_public_ip.master_node_public_ip.ip_address}:/home/${var.admin_username}/kubeconfig kubeconfig"
}

output "user_kubeconfig_scp_command" {
  value = "kubectl --kubeconfig=kubeconfig"
}
