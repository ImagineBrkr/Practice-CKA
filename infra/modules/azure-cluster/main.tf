resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.vm_ssh_key.private_key_pem
  filename        = var.private_key_path
  file_permission = "0600"
}

resource "azurerm_linux_virtual_machine" "master_node_vm" {
  name                = local.master_node_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name
  size                = var.master_node_vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.master_node_network_interface.id
  ]

  allow_extension_operations = false

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.vm_ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.master_node_disk_size
  }

  source_image_reference {
    publisher = var.source_image_reference.publisher
    offer     = var.source_image_reference.offer
    sku       = var.source_image_reference.sku
    version   = var.source_image_reference.version
  }

  user_data = base64encode(templatefile("${path.module}/scripts/master_node.sh", {
    ETCD_VER               = var.etcd_version,
    KUBE_VER               = var.kubernetes_version,
    MASTER_NODE_PRIVATE_IP = local.master_node_private_ip,
    MASTER_NODE_PUBLIC_IP  = azurerm_public_ip.master_node_public_ip.ip_address,
    CLUSTER_ADMIN          = var.admin_username,
    CLUSTER_NAME           = var.project_name
  }))
}

resource "azurerm_linux_virtual_machine" "worker_node_vm" {
  count               = var.woker_node_count
  name                = "${local.worker_node_name_prefix}-${count.index}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name
  size                = var.worker_nodes_vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.worker_node_network_interface[count.index].id
  ]

  allow_extension_operations = false

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.vm_ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.worker_nodes_disk_size
  }

  source_image_reference {
    publisher = var.source_image_reference.publisher
    offer     = var.source_image_reference.offer
    sku       = var.source_image_reference.sku
    version   = var.source_image_reference.version
  }
}
