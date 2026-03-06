# ---------------------------------------------------------------------------
# VMServiceScrape — MongoDB Exporter
#
# Tells VMAgent (selectAllByDefault = true) to pull /metrics from the
# bitnami-mongodb-exporter sidecar (port 9216) running alongside the
# MongoDB replica-set pods.
#
# Target Service  : intangles-mongo-gen-obs-mongodb-metrics
# Target Namespace: var.mongodb_exporter_namespace  (e.g. atomsphere-kl-111)
# Port name       : http-metrics  (→ targetPort: metrics / 9216)
# ---------------------------------------------------------------------------

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
      namespaceSelector = {
        matchNames = [var.mongodb_exporter_namespace]
      }
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
