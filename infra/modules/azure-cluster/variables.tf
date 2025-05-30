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
}




variable "default_tags" {
  type    = map(string)
  default = {}
}
