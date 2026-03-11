# ---------------------------------------------------------------------------
# VMServiceScrape — Redis Exporter
#
# Tells VMAgent (selectAllByDefault = true) to pull /metrics from the
# redis-exporter sidecar running alongside Redis pods.
#
# Namespace scope : when redis_exporter_namespace is empty ("") the selector
#                   uses any: true — scraping every namespace in the cluster.
#                   Set redis_exporter_namespace to restrict to one namespace.
# Label selector  : matchLabels on release=kube-prometheus-stack — matches the
#                   redis-exporter Services deployed alongside the kube-prometheus-stack.
# Port            : targetPort 9121 (standard redis-exporter container port)
# ---------------------------------------------------------------------------

locals {
  # Same jsondecode/jsonencode pattern as mongodb/postgres/scylladb namespace selectors —
  # both branches must produce the same Terraform type ("any" via JSON roundtrip).
  redis_namespace_selector = jsondecode(
    var.redis_exporter_namespace == "" ?
    jsonencode({ any = true }) :
    jsonencode({ matchNames = [var.redis_exporter_namespace] })
  )
}

resource "kubectl_manifest" "vmsscrape_redis" {
  count = var.redis_scrape_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "redis-exporter"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "redis-exporter"
      })
    }
    spec = {
      selector = {
        matchLabels = var.redis_exporter_service_labels
      }
      namespaceSelector = local.redis_namespace_selector
      endpoints = [
        {
          # 9121 is the standard prometheus redis-exporter container port.
          # Using targetPort (integer) because the Service port may have a
          # different name across clusters.
          targetPort = var.redis_exporter_port
          path       = "/metrics"
          interval   = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.vm_operator]
}
