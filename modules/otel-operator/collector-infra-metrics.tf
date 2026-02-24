# Infra Metrics Collector — Deployment CRD
# Scrapes DB/queue metrics independently from the main trace pipeline.
# count = 0 by default — enable with infra_metrics_enabled = true per environment.
# Can be toggled without affecting trace or log pipelines.

resource "kubernetes_manifest" "otel_infra_metrics" {
  count = var.infra_metrics_enabled ? 1 : 0

  manifest = {
    apiVersion = "opentelemetry.io/v1beta1"
    kind       = "OpenTelemetryCollector"

    metadata = {
      name      = "otel-infra-metrics"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "otel-infra-metrics"
      })
    }

    spec = {
      mode           = "deployment"
      replicas       = 1
      serviceAccount = kubernetes_service_account.otel_gateway.metadata[0].name
      image          = "${var.gateway_image}:${var.gateway_image_tag}"

      nodeSelector = var.node_selector

      resources = {
        requests = {
          cpu    = local._norm_cpu.im_req  # normalized to match k8s API storage format
          memory = var.infra_metrics_resources.requests.memory
        }
        limits = {
          cpu    = local._norm_cpu.im_lim  # normalized to match k8s API storage format
          memory = var.infra_metrics_resources.limits.memory
        }
      }

      env = [
        {
          name = "MONGODB_PASSWORD"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret.otel_infra_credentials[0].metadata[0].name
              key  = "mongodb-password"
            }
          }
        },
        {
          name = "RABBITMQ_PASSWORD"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret.otel_infra_credentials[0].metadata[0].name
              key  = "rabbitmq-password"
            }
          }
        },
        {
          name = "POSTGRESQL_PASSWORD"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret.otel_infra_credentials[0].metadata[0].name
              key  = "postgresql-password"
            }
          }
        }
      ]

      config = {
        receivers = {
          "redis/${var.app_namespace}" = {
            endpoint            = "${var.redis_host}:6379"
            collection_interval = "30s"
          }

          "rabbitmq/${var.app_namespace}" = {
            endpoint            = "http://${var.rabbitmq_host}:15672"
            username            = var.rabbitmq_username
            password            = "$${env:RABBITMQ_PASSWORD}"
            collection_interval = "30s"
          }

          "mongodb/${var.app_namespace}" = {
            hosts               = [{ endpoint = "${var.mongodb_host}:27017" }]
            username            = var.mongodb_username
            password            = "$${env:MONGODB_PASSWORD}"
            collection_interval = "30s"
            initial_delay       = "1s"
            tls                 = { insecure = true }
          }

          "postgresql/${var.app_namespace}" = {
            endpoint            = "${var.postgresql_host}:5432"
            transport           = "tcp"
            username            = var.postgresql_username
            password            = "$${env:POSTGRESQL_PASSWORD}"
            databases           = ["postgres"]
            collection_interval = "30s"
            tls                 = { insecure = true }
          }
        }

        processors = {
          memory_limiter = {
            check_interval  = "5s"
            limit_mib       = 400
            spike_limit_mib = 100
          }

          # Inject service.name per infra component.
          # External scrapers don't inherit OTEL_SERVICE_NAME from target pods.
          "resource/redis" = {
            attributes = [{ key = "service.name", value = "${var.app_namespace}-redis", action = "upsert" }]
          }
          "resource/rabbitmq" = {
            attributes = [{ key = "service.name", value = "${var.app_namespace}-rabbitmq", action = "upsert" }]
          }
          "resource/mongodb" = {
            attributes = [{ key = "service.name", value = "${var.app_namespace}-mongodb", action = "upsert" }]
          }
          "resource/postgresql" = {
            attributes = [{ key = "service.name", value = "${var.app_namespace}-timescaledb", action = "upsert" }]
          }

          batch = {
            timeout             = "10s"
            send_batch_size     = 1024
            send_batch_max_size = 2048
          }
        }

        exporters = {
          "otlp/jaeger" = {
            endpoint = var.jaeger_endpoint
            tls      = { insecure = true }
            retry_on_failure = {
              enabled          = true
              initial_interval = "5s"
              max_interval     = "30s"
              max_elapsed_time = "300s"
            }
          }

          "prometheusremotewrite/prometheus" = {
            endpoint = var.prometheus_remote_write_endpoint
            tls      = { insecure = true }
            resource_to_telemetry_conversion = { enabled = true }
          }

          prometheus = {
            endpoint = "0.0.0.0:8889"
            resource_to_telemetry_conversion = { enabled = true }
          }
        }

        extensions = {
          health_check = { endpoint = "0.0.0.0:13133" }
        }

        service = {
          extensions = ["health_check"]
          pipelines = {
            "metrics/redis" = {
              receivers  = ["redis/${var.app_namespace}"]
              processors = ["memory_limiter", "resource/redis", "batch"]
              exporters  = ["otlp/jaeger", "prometheusremotewrite/prometheus", "prometheus"]
            }
            "metrics/rabbitmq" = {
              receivers  = ["rabbitmq/${var.app_namespace}"]
              processors = ["memory_limiter", "resource/rabbitmq", "batch"]
              exporters  = ["otlp/jaeger", "prometheusremotewrite/prometheus", "prometheus"]
            }
            "metrics/mongodb" = {
              receivers  = ["mongodb/${var.app_namespace}"]
              processors = ["memory_limiter", "resource/mongodb", "batch"]
              exporters  = ["otlp/jaeger", "prometheusremotewrite/prometheus", "prometheus"]
            }
            "metrics/postgresql" = {
              receivers  = ["postgresql/${var.app_namespace}"]
              processors = ["memory_limiter", "resource/postgresql", "batch"]
              exporters  = ["otlp/jaeger", "prometheusremotewrite/prometheus", "prometheus"]
            }
          }
          telemetry = {
            logs    = { level = "warn" }
            metrics = { level = "detailed", address = "0.0.0.0:8888" }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.otel_operator,
    kubernetes_manifest.otel_gateway,
    kubernetes_secret.otel_infra_credentials
  ]
}
