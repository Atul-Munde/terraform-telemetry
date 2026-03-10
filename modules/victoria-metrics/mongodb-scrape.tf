# ---------------------------------------------------------------------------
# VMServiceScrape — MongoDB Exporter
#
# Tells VMAgent (selectAllByDefault = true) to pull /metrics from the
# mongodb-exporter sidecar running alongside MongoDB replica-set pods.
#
# Namespace scope : when mongodb_exporter_namespace is empty ("") the selector
#                   uses any: true — scraping every namespace in the cluster.
#                   Set mongodb_exporter_namespace to restrict to one namespace.
# Label selector  : uses only stable labels shared by ALL mongodb exporter
#                   services (app.kubernetes.io/component + app.kubernetes.io/name)
#                   so every MongoDB cluster is discovered automatically.
# Port name       : http-metrics  (→ targetPort: metrics / 9216)
# ---------------------------------------------------------------------------

locals {
  # Terraform ternary requires both branches to have the same object shape.
  # { any = true } vs { matchNames = [...] } differ in keys and value types,
  # so we use a jsondecode/jsonencode roundtrip which returns type "any"
  # and bypasses the type-consistency constraint.
  mongodb_namespace_selector = jsondecode(
    var.mongodb_exporter_namespace == "" ?
    jsonencode({ any = true }) :
    jsonencode({ matchNames = [var.mongodb_exporter_namespace] })
  )
}

resource "kubectl_manifest" "vmsscrape_mongodb" {
  count = var.mongodb_scrape_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "mongodb-exporter"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "mongodb-exporter"
      })
    }
    spec = {
      selector = {
        matchLabels = var.mongodb_exporter_service_labels
      }
      namespaceSelector = local.mongodb_namespace_selector
      endpoints = [
        {
          port     = var.mongodb_exporter_port
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.vm_operator]
}
