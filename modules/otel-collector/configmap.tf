resource "kubernetes_config_map" "otel_collector" {
  metadata {
    name      = "${local.name}-config"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "otel-collector-config.yaml" = yamlencode({
      receivers = {
        otlp = {
          protocols = {
            grpc = {
              endpoint = "0.0.0.0:4317"
            }
            http = {
              endpoint = "0.0.0.0:4318"
            }
          }
        }
        # Prometheus receiver for scraping metrics
        prometheus = {
          config = {
            scrape_configs = [
              {
                job_name        = "otel-collector"
                scrape_interval = "30s"
                static_configs = [
                  {
                    targets = ["localhost:8888"]
                  }
                ]
              }
            ]
          }
        }
      }

      processors = merge({
        # Batch processor to reduce API calls
        batch = {
          timeout             = "10s"
          send_batch_size     = 1024
          send_batch_max_size = 2048
        }

        # Memory limiter to prevent OOM
        memory_limiter = {
          check_interval         = "1s"
          limit_mib              = 512
          spike_limit_mib        = 128
          limit_percentage       = 80
          spike_limit_percentage = 20
        }

        # Resource processor to add environment labels
        resource = {
          attributes = [
            {
              key    = "environment"
              value  = var.environment
              action = "insert"
            },
            {
              key    = "k8s.cluster.name"
              value  = "default"
              action = "insert"
            }
          ]
        }

        # K8s attributes processor
        k8sattributes = {
          auth_type   = "serviceAccount"
          passthrough = false
          extract = {
            metadata = [
              "k8s.namespace.name",
              "k8s.deployment.name",
              "k8s.pod.name",
              "k8s.pod.uid",
              "k8s.node.name"
            ]
            labels = [
              {
                tag_name = "app"
                key      = "app"
                from     = "pod"
              }
            ]
          }
        }
        },
        # Conditionally add tail_sampling processor
        var.enable_sampling ? {
          tail_sampling = {
            decision_wait               = "10s"
            num_traces                  = 100
            expected_new_traces_per_sec = 10
            policies = [
              {
                name = "error-traces"
                type = "status_code"
                status_code = {
                  status_codes = ["ERROR"]
                }
              },
              {
                name = "probabilistic-policy"
                type = "probabilistic"
                probabilistic = {
                  sampling_percentage = var.sampling_percentage
                }
              }
            ]
          }
        } : {}
      )

      exporters = {
        # OTLP exporter for Jaeger
        otlp = {
          endpoint = var.jaeger_endpoint
          tls = {
            insecure = true
          }
        }

        # Logging exporter for debugging
        logging = {
          loglevel            = "info"
          sampling_initial    = 5
          sampling_thereafter = 200
        }
      }

      extensions = {
        health_check = {
          endpoint = "0.0.0.0:13133"
        }
        pprof = {
          endpoint = "0.0.0.0:1777"
        }
        zpages = {
          endpoint = "0.0.0.0:55679"
        }
      }

      service = {
        extensions = ["health_check", "pprof", "zpages"]
        pipelines = {
          traces = {
            receivers = ["otlp"]
            processors = var.enable_sampling ? [
              "memory_limiter",
              "k8sattributes",
              "resource",
              "tail_sampling",
              "batch"
              ] : [
              "memory_limiter",
              "k8sattributes",
              "resource",
              "batch"
            ]
            exporters = ["otlp", "logging"]
          }
          metrics = {
            receivers  = ["otlp", "prometheus"]
            processors = ["memory_limiter", "batch"]
            exporters  = ["logging"]
          }
        }
        telemetry = {
          logs = {
            level = "info"
          }
          metrics = {
            level   = "detailed"
            address = "0.0.0.0:8888"
          }
        }
      }
    })
  }
}
