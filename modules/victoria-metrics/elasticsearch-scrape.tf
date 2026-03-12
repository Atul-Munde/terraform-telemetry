# ---------------------------------------------------------------------------
# VMServiceScrape — Elasticsearch Cluster Metrics
#
# Tells VMAgent (selectAllByDefault = true) to pull /_prometheus/metrics
# from each Elasticsearch node group (master, data, coordinating).
#
# The ES chart 8.5.1 exposes the built-in Prometheus exporter at
# /_prometheus/metrics when xpack.security is enabled (requires basic auth).
#
# Namespace scope : restricts to the telemetry namespace where ES is deployed.
# Label selector  : matches the chart-default label app=<clusterName>-<nodeGroup>
# Port            : targetPort 9200 (ES HTTP port)
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "vmsscrape_elasticsearch" {
  count = var.elasticsearch_scrape_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "elasticsearch-metrics"
      namespace = var.namespace
      labels = merge(local.common_labels, {
        "app.kubernetes.io/component" = "elasticsearch"
      })
    }
    spec = {
      selector = {
        matchLabels = var.elasticsearch_service_labels
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/_prometheus/metrics"
          interval = "30s"
          scheme   = "https"
          tlsConfig = {
            insecureSkipVerify = true
          }
          basicAuth = {
            username = {
              name = "elasticsearch-credentials"
              key  = "username"
            }
            password = {
              name = "elasticsearch-credentials"
              key  = "ELASTIC_PASSWORD"
            }
          }
        }
      ]
    }
  })

  depends_on = [helm_release.vm_operator]
}
