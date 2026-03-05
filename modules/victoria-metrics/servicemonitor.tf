# ServiceMonitor resources for kube-prometheus-stack (when kube_prometheus_enabled = true)
# VMServiceScrape CRDs for VictoriaMetrics Operator (always created — the operator
# picks them up via vmagent's selectAllByDefault = true).
#
# Component ports:
#   vmstorage      :8482  — /metrics
#   vminsert       :8480  — /metrics
#   vmselect       :8481  — /metrics
#   otel-gateway   :8889  — /metrics (collector self-telemetry only; app metrics pushed via prometheusremotewrite)
# The VictoriaMetrics Operator itself (deployed via Helm) is scraped via its own
# ServiceMonitor bundled with the Helm chart; we only scrape the VMCluster components here.

# ---------------------------------------------------------------------------
# VMServiceScrape — vmstorage
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "vmsscrape_vmstorage" {
  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "vmstorage"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmstorage" })
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vmstorage"
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.vmcluster]
}

# ---------------------------------------------------------------------------
# VMServiceScrape — vminsert
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "vmsscrape_vminsert" {
  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "vminsert"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vminsert" })
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vminsert"
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.vmcluster]
}

# ---------------------------------------------------------------------------
# VMServiceScrape — vmselect
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "vmsscrape_vmselect" {
  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "vmselect"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmselect" })
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vmselect"
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.vmcluster]
}

# ---------------------------------------------------------------------------
# ServiceMonitor — vmstorage (for kube-prometheus-stack Prometheus)
# Only created when kube_prometheus_enabled = true because kube-prometheus uses a
# different CRD (monitoring.coreos.com/v1) and a separate Prometheus instance.
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "svcmonitor_vmstorage" {
  count = var.kube_prometheus_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "vmstorage"
      namespace = var.namespace
      labels = merge(local.common_labels, {
        "app.kubernetes.io/component" = "vmstorage"
        # kube-prometheus-stack selects ServiceMonitors with this label
        "release" = "kube-prometheus-stack"
      })
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vmstorage"
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.vmcluster]
}

# ---------------------------------------------------------------------------
# ServiceMonitor — vminsert
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "svcmonitor_vminsert" {
  count = var.kube_prometheus_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "vminsert"
      namespace = var.namespace
      labels = merge(local.common_labels, {
        "app.kubernetes.io/component" = "vminsert"
        "release"                     = "kube-prometheus-stack"
      })
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vminsert"
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.vmcluster]
}

# ---------------------------------------------------------------------------
# ServiceMonitor — vmselect
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "svcmonitor_vmselect" {
  count = var.kube_prometheus_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "vmselect"
      namespace = var.namespace
      labels = merge(local.common_labels, {
        "app.kubernetes.io/component" = "vmselect"
        "release"                     = "kube-prometheus-stack"
      })
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vmselect"
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.vmcluster]
}

# ---------------------------------------------------------------------------
# VMServiceScrape — OTel Gateway collector self-metrics (:8889)
#
# The OTel Gateway PUSHES application metrics to vminsert via
# prometheusremotewrite. This scrape target is ONLY for the collector's own
# operational telemetry: queue depth, dropped items, export errors, memory.
# VMAgent discovers this via Kubernetes service discovery + selectAllByDefault.
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "vmsscrape_otel_gateway" {
  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "otel-gateway"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "otel-gateway" })
    }
    spec = {
      # Matches the Service the OTel Operator creates for the gateway StatefulSet.
      # app.kubernetes.io/component=otel-gateway is set by the OTel Operator
      # based on the OpenTelemetryCollector CR name "otel-gateway".
      selector = {
        matchLabels = {
          "app.kubernetes.io/component" = "otel-gateway"
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          # OTel Operator exposes the prometheus exporter port (8889) as "monitoring"
          port     = "monitoring"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  # VMServiceScrape CRD is registered by the Helm chart — must wait for it.
  depends_on = [helm_release.vm_operator]
}
