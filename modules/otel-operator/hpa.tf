# HPA for Gateway Collector
# Targets the OpenTelemetryCollector CRD directly (Operator manages the StatefulSet).
# minReplicas: 2 enforced — single replica = SPOF for all telemetry.
# Validation in variables.tf also rejects values < 2.

resource "kubernetes_horizontal_pod_autoscaler_v2" "otel_gateway" {
  metadata {
    name      = "otel-gateway-hpa"
    namespace = var.namespace
    labels    = merge(local.common_labels, {
      "app.kubernetes.io/component" = "otel-gateway"
    })
  }

  spec {
    min_replicas = var.gateway_min_replicas
    max_replicas = var.gateway_max_replicas

    scale_target_ref {
      api_version = "opentelemetry.io/v1beta1"
      kind        = "OpenTelemetryCollector"
      name        = kubernetes_manifest.otel_gateway.manifest.metadata.name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Max"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }

      scale_up {
        stabilization_window_seconds = 60
        select_policy                = "Max"
        policy {
          type           = "Pods"
          value          = 2
          period_seconds = 60
        }
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 60
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.otel_gateway]
}
