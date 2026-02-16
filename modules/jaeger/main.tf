locals {
  release_name = "jaeger"
  chart_repo   = "https://jaegertracing.github.io/helm-charts"
}

# Jaeger Helm Release
resource "helm_release" "jaeger" {
  name       = local.release_name
  repository = local.chart_repo
  chart      = "jaeger"
  version    = var.chart_version
  namespace  = var.namespace
  timeout    = 600

  values = [
    yamlencode({
      provisionDataStore = {
        cassandra = false
        elasticsearch = false
      }

      storage = {
        type = var.storage_type
        elasticsearch = var.storage_type == "elasticsearch" ? {
          scheme = "http"
          host   = var.elasticsearch_host
          port   = var.elasticsearch_port
          user   = ""
          password = ""
        } : null
      }

      # Jaeger Agent (DaemonSet) - Optional, useful for sidecar pattern
      agent = {
        enabled = false
      }

      # Jaeger Collector
      collector = {
        enabled = true
        replicaCount = var.collector_replicas
        
        service = {
          type = "ClusterIP"
          grpc = {
            port = 14250
          }
          http = {
            port = 14268
          }
          otlp = {
            grpc = {
              name = "otlp-grpc"
              port = 4317
            }
            http = {
              name = "otlp-http"
              port = 4318
            }
          }
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        podDisruptionBudget = {
          enabled = true
          minAvailable = 1
        }

        autoscaling = {
          enabled = false
        }

        strategy = {
          type = "RollingUpdate"
          rollingUpdate = {
            maxUnavailable = "25%"
            maxSurge = "25%"
          }
        }

        affinity = {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchExpressions = [
                      {
                        key      = "app.kubernetes.io/component"
                        operator = "In"
                        values   = ["collector"]
                      }
                    ]
                  }
                  topologyKey = "kubernetes.io/hostname"
                }
              }
            ]
          }
        }
      }

      # Jaeger Query (UI)
      query = {
        enabled = true
        replicaCount = var.query_replicas

        service = {
          type = "ClusterIP"
          port = 16686
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        podDisruptionBudget = {
          enabled = true
          minAvailable = 1
        }

        strategy = {
          type = "RollingUpdate"
          rollingUpdate = {
            maxUnavailable = "25%"
            maxSurge = "25%"
          }
        }

        affinity = {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchExpressions = [
                      {
                        key      = "app.kubernetes.io/component"
                        operator = "In"
                        values   = ["query"]
                      }
                    ]
                  }
                  topologyKey = "kubernetes.io/hostname"
                }
              }
            ]
          }
        }
      }

      # Ingress - disabled by default
      ingress = {
        enabled = false
      }

      # All-in-one deployment - disabled for production
      allInOne = {
        enabled = false
      }
    })
  ]

  set {
    name  = "commonLabels.environment"
    value = var.environment
  }

  set {
    name  = "commonLabels.managed-by"
    value = "terraform"
  }
}
