variable "project_name" {
  description = "Name of the Azure project that will be used as a prefix for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name where the resources will be created"
  type        = string
}

variable "location" {
  description = "Azure location where the resources will be created"
  type        = string
}

variable "woker_node_count" {
  description = "Number of worker nodes in the Azure cluster"
  type        = number
  default     = 1
  validation {
    condition     = var.woker_node_count >= 0 && floor(var.woker_node_count) == var.woker_node_count
    error_message = "Worker node count must be a positive integer (0 or greater)."
  }
}

variable "master_node_vm_size" {
  description = "VM size for the master node"
  type        = string
  default     = "Standard_B2s"
}

variable "worker_nodes_vm_size" {
  description = "VM size for the worker nodes"
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "VM Admin username"
  type        = string
  default     = "cluster_admin"
}

variable "master_node_disk_size" {
  description = "VM for master node Disk Size"
  type        = number
  default     = 30
}

variable "source_image_reference" {
  description = "Source image reference for VMs"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

variable "worker_nodes_disk_size" {
  description = "VM for worker nodes Disk Size"
  type        = number
  default     = 30
}

variable "private_key_path" {
  description = "Path where the private key will be stored"
  type        = string
  default     = "~/.ssh/azure_cluster_private_key.pem"
}

variable "etcd_version" {
  description = "etcd version to be installed on master node"
  type        = string
  default     = "v3.6.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version to be installed on the nodes"
  type        = string
  default     = "v1.33.1"
}

variable "default_tags" {
  type    = map(string)
  default = {}
}
