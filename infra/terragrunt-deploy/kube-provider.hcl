generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF

terraform {
  required_version = "~> 1.12.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kube_config_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kube_config_path
    config_context = var.kube_context
  }
}

variable "kube_config_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "kube_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "default"
}
EOF
}
