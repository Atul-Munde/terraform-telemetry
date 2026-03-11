# ---------------------------------------------------------------------------
# VMServiceScrape — ScyllaDB Native Metrics
#
# Tells VMAgent (selectAllByDefault = true) to pull /metrics from ScyllaDB's
# built-in Prometheus endpoint exposed on port 9180.
# No separate exporter sidecar is required — Scylla exposes metrics natively.
#
# Namespace scope : when scylladb_exporter_namespace is empty ("") the selector
#                   uses any: true — scraping every namespace in the cluster.
#                   Set scylladb_exporter_namespace to restrict to one namespace.
# Label selector  : matchLabels on app.kubernetes.io/name=scylla — matches all
#                   ScyllaDB Services created by the Scylla Operator.
# Port            : targetPort 9180 (Scylla built-in native Prometheus port)
# ---------------------------------------------------------------------------

locals {
  # Same jsondecode/jsonencode pattern as mongodb/postgres namespace selectors —
  # both branches must produce the same Terraform type ("any" via JSON roundtrip).
  scylladb_namespace_selector = jsondecode(
    var.scylladb_exporter_namespace == "" ?
    jsonencode({ any = true }) :
    jsonencode({ matchNames = [var.scylladb_exporter_namespace] })
  )
}

resource "kubectl_manifest" "vmsscrape_scylladb" {
  count = var.scylladb_scrape_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "scylladb-native"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "scylladb-exporter"
      })
    }
    spec = {
      selector = {
        matchLabels = var.scylladb_exporter_service_labels
      }
      namespaceSelector = local.scylladb_namespace_selector
      endpoints = [
        {
          # 9180 is ScyllaDB's built-in native Prometheus endpoint.
          # Using targetPort (integer) because the Service port may carry
          # different names across clusters managed by the Scylla Operator.
          targetPort = var.scylladb_exporter_port
          path       = "/metrics"
          interval   = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.vm_operator]
}
