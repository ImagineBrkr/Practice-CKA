resource "helm_release" "cert_manager" {
  name      = "cert-manager"
  namespace = kubernetes_namespace.ingress_nginx.metadata[0].name
  chart     = "https://charts.jetstack.io/charts/cert-manager-v${var.cert_manager_chart_version}.tgz"

  # https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml
  values = [
    file("${path.module}/resources/cert-manager-values.yaml"),
    var.cert_manager_chart_values
  ]
}
