# ServiceMonitor — Prometheus scrapes Gateway metrics on port 8889
# Only created when kube_prometheus_enabled = true
# Label release: kube-prometheus-stack ensures the Prometheus Operator picks it up

resource "kubernetes_manifest" "otel_gateway_service_monitor" {
  count = var.kube_prometheus_enabled ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "otel-gateway"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "otel-gateway"
        # Must match Prometheus Operator serviceMonitorSelector — default kube-prometheus-stack label
        "release" = "kube-prometheus-stack"
      })
    }
    spec = {
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      selector = {
        matchLabels = {
          # Use the headless service only — it resolves directly to pod IPs (no ClusterIP VIP).
          # OTel Operator creates 3 services for each collector; all share app.kubernetes.io/name
          # but only the headless one has collector-service-type=headless.
          # Targeting only headless avoids 4 duplicate scrape targets (2 services × 2 pods).
          "app.kubernetes.io/name"                              = "otel-gateway-collector"
          "app.kubernetes.io/managed-by"                        = "opentelemetry-operator"
          "operator.opentelemetry.io/collector-service-type"    = "headless"
        }
      }
      endpoints = [
        {
          port     = "prometheus"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.otel_gateway]
}

# ServiceMonitor for infra-metrics collector (when enabled)
resource "kubernetes_manifest" "otel_infra_service_monitor" {
  count = var.kube_prometheus_enabled && var.infra_metrics_enabled ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "otel-infra-metrics"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "otel-infra-metrics"
        "release"                     = "kube-prometheus-stack"
      })
    }
    spec = {
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      selector = {
        matchLabels = {
          # OTel Operator sets app.kubernetes.io/name=<CR-name>-collector on the service
          "app.kubernetes.io/name"       = "otel-infra-metrics-collector"
          "app.kubernetes.io/managed-by" = "opentelemetry-operator"
        }
      }
      endpoints = [
        {
          port     = "prometheus"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.otel_infra_metrics]
}
