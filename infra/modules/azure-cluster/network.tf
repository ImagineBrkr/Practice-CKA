# VIRTUAL NETWORK AND SUBNETS FOR THE CLUSTER

resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-network"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  tags = var.default_tags
}

resource "azurerm_subnet" "nodes_subnet" {
  name                 = "${var.project_name}-nodes-subnet"
  resource_group_name  = data.azurerm_resource_group.main_resource_group.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/24"]

  default_outbound_access_enabled = true
}


# PUBLIC IP

resource "azurerm_public_ip" "master_node_public_ip" {
  name                = local.public_ip_name
  resource_group_name = data.azurerm_resource_group.main_resource_group.name
  location            = var.location
  allocation_method   = "Static"

  tags = var.default_tags
}


# NETWORK INTERFACES FOR THE NODES


resource "azurerm_network_interface" "master_node_network_interface" {
  name                = local.master_network_interface_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.nodes_subnet.id
    private_ip_address_allocation = "Static"
    primary                       = true
    private_ip_address            = local.master_node_private_ip
  }

  ip_configuration {
    name                          = "external"
    subnet_id                     = azurerm_subnet.nodes_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.master_node_public_ip.id
  }
}


resource "azurerm_network_interface" "worker_node_network_interface" {
  count               = var.woker_node_count
  name                = "${local.worker_network_interface_name_prefix}-${count.index}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.nodes_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
  depends_on = [
    azurerm_network_interface.master_node_network_interface
  ]
}


# SECURITY GROUPS FOR THE NODES

resource "azurerm_network_security_group" "cluster_network_security_group" {
  name                = "cluster-nsg"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  tags = var.default_tags
}

# Application Security Groups logically separate the nodes so we only apply security rules to one subset of nodes.
resource "azurerm_application_security_group" "master_node_application_security_group" {
  name                = local.master_security_group_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  tags = var.default_tags
}

resource "azurerm_network_security_rule" "master_node_security_group_allow_ssh" {
  name                                       = "${local.master_security_group_name}-allow-ssh"
  priority                                   = 100
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "22"
  source_address_prefix                      = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.master_node_application_security_group.id]
  resource_group_name                        = data.azurerm_resource_group.main_resource_group.name
  network_security_group_name                = azurerm_network_security_group.cluster_network_security_group.name
}

resource "azurerm_network_security_rule" "master_node_security_group_allow_http" {
  name                                       = "${local.master_security_group_name}-allow-http"
  priority                                   = 200
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "80"
  source_address_prefix                      = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.master_node_application_security_group.id]
  resource_group_name                        = data.azurerm_resource_group.main_resource_group.name
  network_security_group_name                = azurerm_network_security_group.cluster_network_security_group.name
}

resource "azurerm_network_security_rule" "master_node_security_group_allow_https" {
  name                                       = "${local.master_security_group_name}-allow-https"
  priority                                   = 300
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "443"
  source_address_prefix                      = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.master_node_application_security_group.id]
  resource_group_name                        = data.azurerm_resource_group.main_resource_group.name
  network_security_group_name                = azurerm_network_security_group.cluster_network_security_group.name
}

resource "azurerm_network_security_rule" "master_node_security_group_allow_kube_apiserver" {
  name                                       = "${local.master_security_group_name}-allow-kube-api-server"
  priority                                   = 600
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "6443"
  source_address_prefix                      = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.master_node_application_security_group.id]
  resource_group_name                        = data.azurerm_resource_group.main_resource_group.name
  network_security_group_name                = azurerm_network_security_group.cluster_network_security_group.name
}

# Worker Nodes
resource "azurerm_application_security_group" "worker_node_application_security_group" {
  name                = local.worker_security_group_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  tags = var.default_tags
}

resource "azurerm_network_security_rule" "worker_node_security_group_allow_ssh" {
  name                                       = "${local.worker_security_group_name}-allow-ssh"
  priority                                   = 500
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "22"
  source_application_security_group_ids      = [azurerm_application_security_group.master_node_application_security_group.id]
  destination_application_security_group_ids = [azurerm_application_security_group.worker_node_application_security_group.id]
  resource_group_name                        = data.azurerm_resource_group.main_resource_group.name
  network_security_group_name                = azurerm_network_security_group.cluster_network_security_group.name
}


# ASSOCIATIONS WITH NETWORK INTERFACES


# Master node
resource "azurerm_network_interface_security_group_association" "cluster_network_security_group_association_master_node" {
  network_interface_id      = azurerm_network_interface.master_node_network_interface.id
  network_security_group_id = azurerm_network_security_group.cluster_network_security_group.id
}

resource "azurerm_network_interface_application_security_group_association" "master_application_security_group_association_master_node" {
  network_interface_id          = azurerm_network_interface.master_node_network_interface.id
  application_security_group_id = azurerm_application_security_group.master_node_application_security_group.id
}


# Worker nodes
resource "azurerm_network_interface_security_group_association" "cluster_network_security_group_association_worker_nodes" {
  count                     = var.woker_node_count
  network_interface_id      = azurerm_network_interface.worker_node_network_interface[count.index].id
  network_security_group_id = azurerm_network_security_group.cluster_network_security_group.id
}

resource "azurerm_network_interface_application_security_group_association" "master_application_security_group_association_worker_node" {
  count                         = var.woker_node_count
  network_interface_id          = azurerm_network_interface.worker_node_network_interface[count.index].id
  application_security_group_id = azurerm_application_security_group.master_node_application_security_group.id
}
