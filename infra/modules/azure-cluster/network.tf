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

# SECURITY GROUPS FOR THE NODES

resource "azurerm_network_security_group" "cluster_network_security_group" {
  name                = "cluster-nsg"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name
}

# Application Security Groups logically separate the nodes so we only apply security rules to one subset of nodes.
resource "azurerm_application_security_group" "master_node_application_security_group" {
  name                = "${local.master_node_name}-nsg"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  tags = var.default_tags
}

resource "azurerm_network_security_rule" "master_node_security_group_allow_ssh" {
  name                                       = "${local.master_node_name}-asg-allow-ssh"
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
  name                                       = "${local.master_node_name}-asg-allow-http"
  priority                                   = 101
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
  name                                       = "${local.master_node_name}-asg-allow-https"
  priority                                   = 102
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


resource "azurerm_application_security_group" "worker_node_application_security_group" {
  name                = "${local.worker_node_name}-asg"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  tags = var.default_tags
}

resource "azurerm_network_security_rule" "worker_node_security_group_allow_ssh" {
  name                                       = "local.worker_node_name-asg-allow-ssh"
  priority                                   = 100
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


# NETWORK INTERFACES FOR THE NODES


resource "azurerm_network_interface" "master_node_network_interface" {
  name                = "${var.project_name}-nic"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main_resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.nodes_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}