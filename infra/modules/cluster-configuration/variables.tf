variable "nginx_chart_version" {
  description = "Version of the NGINX Ingress Controller Helm chart to deploy"
  type        = string
  default     = "4.12.1"
}

variable "nginx_chart_values" {
  description = "Custom values for the NGINX Ingress Controller"
  type        = string
  default     = ""
}