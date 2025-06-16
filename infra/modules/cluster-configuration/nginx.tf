resource "helm_release" "ingress_nginx" {
  name      = "ingress-nginx"
  namespace = kubernetes_namespace.ingress_nginx.metadata[0].name
  chart     = "https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-${var.nginx_chart_version}/ingress-nginx-${var.nginx_chart_version}.tgz"

  # https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml
  values = [
    file("${path.module}/resources/nginx-values.yaml"),
    var.nginx_chart_values
  ]
}