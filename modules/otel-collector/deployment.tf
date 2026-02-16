# ServiceAccount for OTel Collector
resource "kubernetes_service_account" "otel_collector" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
}

# ClusterRole for K8s attributes processor
resource "kubernetes_cluster_role" "otel_collector" {
  metadata {
    name   = "${local.name}-${var.namespace}"
    labels = local.labels
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces", "nodes"]
    verbs      = ["get", "watch", "list"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets", "deployments"]
    verbs      = ["get", "list", "watch"]
  }
}

# ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "otel_collector" {
  metadata {
    name   = "${local.name}-${var.namespace}"
    labels = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.otel_collector.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.otel_collector.metadata[0].name
    namespace = var.namespace
  }
}

# Deployment
resource "kubernetes_deployment" "otel_collector" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.hpa_enabled ? null : var.replicas

    selector {
      match_labels = {
        app = local.name
      }
    }

    template {
      metadata {
        labels = local.labels
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8888"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.otel_collector.metadata[0].name

        container {
          name  = "otel-collector"
          image = "${var.image}:${var.image_version}"

          args = [
            "--config=/conf/otel-collector-config.yaml"
          ]

          port {
            name           = "otlp-grpc"
            container_port = 4317
            protocol       = "TCP"
          }

          port {
            name           = "otlp-http"
            container_port = 4318
            protocol       = "TCP"
          }

          port {
            name           = "metrics"
            container_port = 8888
            protocol       = "TCP"
          }

          port {
            name           = "health"
            container_port = 13133
            protocol       = "TCP"
          }

          port {
            name           = "zpages"
            container_port = 55679
            protocol       = "TCP"
          }

          env {
            name = "K8S_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name = "K8S_POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name = "K8S_POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name = "K8S_POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          volume_mount {
            name       = "otel-collector-config"
            mount_path = "/conf"
          }
        }

        volume {
          name = "otel-collector-config"
          config_map {
            name = kubernetes_config_map.otel_collector.metadata[0].name
          }
        }

        termination_grace_period_seconds = 30

        # Node selector for dedicated nodes
        node_selector = var.node_selector

        # Tolerations for tainted nodes
        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        # Anti-affinity to spread pods across nodes
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = [local.name]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = "25%"
        max_surge       = "25%"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec[0].replicas
    ]
  }

  depends_on = [
    kubernetes_config_map.otel_collector
  ]
}

# PodDisruptionBudget
resource "kubernetes_pod_disruption_budget_v1" "otel_collector" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    min_available = "50%"

    selector {
      match_labels = {
        app = local.name
      }
    }
  }
}
