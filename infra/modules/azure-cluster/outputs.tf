output "master_node_ssh_command" {
  value = "ssh -i ${var.private_key_path} ${var.admin_username}@${azurerm_public_ip.master_node_public_ip.ip_address}"
}
