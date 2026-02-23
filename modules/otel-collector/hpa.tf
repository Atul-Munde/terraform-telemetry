resource "kubernetes_horizontal_pod_autoscaler_v2" "otel_collector" {
  count = var.hpa_enabled ? 1 : 0

  metadata {
    name      = "${local.name}-hpa"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.otel_collector.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_cpu_threshold
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_memory_threshold
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }
      }

      scale_up {
        stabilization_window_seconds = 60
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 60
        }
        policy {
          type           = "Pods"
          value          = 2
          period_seconds = 60
        }
        select_policy = "Max"
      }
    }
  }
}
