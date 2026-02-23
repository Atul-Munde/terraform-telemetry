locals {
  release_name = "jaeger"
  chart_repo   = "https://jaegertracing.github.io/helm-charts"
}

# Jaeger Helm Release
resource "helm_release" "jaeger" {
  name       = local.release_name
  repository = local.chart_repo
  chart      = "jaeger"
  version    = var.chart_version
  namespace  = var.namespace
  timeout    = 600

  values = [
    templatefile("${path.module}/templates/values.yaml.tpl", {
      storage_type       = var.storage_type
      elasticsearch_host = var.elasticsearch_host
      elasticsearch_port = var.elasticsearch_port
      collector_replicas = var.collector_replicas
      query_replicas     = var.query_replicas
      environment        = var.environment
      node_selector      = var.node_selector
      tolerations        = var.tolerations
    })
  ]
}
