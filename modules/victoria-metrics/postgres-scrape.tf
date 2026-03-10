# ---------------------------------------------------------------------------
# VMServiceScrape — PostgreSQL / TimescaleDB Exporter
#
# Tells VMAgent (selectAllByDefault = true) to pull /metrics from the
# postgres-exporter sidecar running alongside PostgreSQL/TimescaleDB pods.
#
# Namespace scope : when postgres_exporter_namespace is empty ("") the selector
#                   uses any: true — scraping every namespace in the cluster.
#                   Set postgres_exporter_namespace to restrict to one namespace.
# Label selector  : uses matchExpressions with operator: Exists on the key
#                   "pg-exporter-service" — the key is constant across all
#                   clusters but the value differs per cluster, so Exists
#                   matches every postgres-exporter service regardless of value.
# Port            : targetPort 9187 (standard prometheus-postgres-exporter port)
# ---------------------------------------------------------------------------

locals {
  # Same jsondecode/jsonencode pattern as mongodb_namespace_selector —
  # both branches must produce the same Terraform type ("any" via JSON roundtrip).
  postgres_namespace_selector = jsondecode(
    var.postgres_exporter_namespace == "" ?
    jsonencode({ any = true }) :
    jsonencode({ matchNames = [var.postgres_exporter_namespace] })
  )
}

resource "kubectl_manifest" "vmsscrape_postgres" {
  count = var.postgres_scrape_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "postgres-timescale-exporter"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "postgres-exporter"
      })
    }
    spec = {
      selector = {
        # matchExpressions with Exists matches the label key "pg-exporter-service"
        # on ANY value — every postgres-timescale cluster has this key but with
        # a different value (e.g. eoldb, another-db), so matchLabels would miss them.
        matchExpressions = [
          {
            key      = var.postgres_exporter_label_key
            operator = "Exists"
          }
        ]
      }
      namespaceSelector = local.postgres_namespace_selector
      endpoints = [
        {
          # 9187 is the standard prometheus-postgres-exporter container port.
          # Using targetPort (integer) because the Service port may have a
          # different name or no name across clusters.
          targetPort = var.postgres_exporter_port
          path       = "/metrics"
          interval   = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.vm_operator]
}
