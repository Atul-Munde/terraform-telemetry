# Gateway Collector — StatefulSet CRD
#
# DESIGN DECISIONS:
#   mode: statefulset  — required for tail_sampling correctness (all spans of a trace
#                        must reach the SAME pod for deterministic decisions)
#   loadbalancing exporter on Agent → headless service DNS → all pod IPs returned
#   HPA in hpa.tf targets this CRD; minReplicas: 2 enforced at HPA level
#
# Pipeline: memory_limiter → filter/noise → transform/clean-attrs
#           → transform/peer-service → tail_sampling → batch
#           → [jaeger, prometheus_remote_write, prometheus_scrape]

resource "kubernetes_manifest" "otel_gateway" {
  # force_conflicts: reclaim field ownership from kubectl-patch commands run outside Terraform
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "opentelemetry.io/v1beta1"
    kind       = "OpenTelemetryCollector"

    metadata = {
      name      = "otel-gateway"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "otel-gateway"
      })
    }

    spec = {
      # StatefulSet: mandatory for tail sampling with multiple replicas
      mode     = "statefulset"
      replicas = var.gateway_min_replicas

      serviceAccount = kubernetes_service_account.otel_gateway.metadata[0].name
      image          = "${var.gateway_image}:${var.gateway_image_tag}"

      nodeSelector = var.node_selector

      # null when empty: Kubernetes API stores absent tolerations as null, not [].
      # Returning [] would cause a provider inconsistency error on every apply.
      tolerations = length(var.tolerations) > 0 ? [
        for t in var.tolerations : {
          key      = t.key
          operator = t.operator
          value    = t.value
          effect   = t.effect
        }
      ] : null

      affinity = {
        podAntiAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = [
            {
              labelSelector = {
                matchLabels = {
                  "app.kubernetes.io/component" = "otel-gateway"
                }
              }
              topologyKey = "kubernetes.io/hostname"
            }
          ]
        }
      }

      resources = {
        requests = {
          cpu    = local._norm_cpu.gw_req  # normalized: "2000m" → "2" to match k8s API
          memory = var.gateway_resources.requests.memory
        }
        limits = {
          cpu    = local._norm_cpu.gw_lim  # normalized: "2000m" → "2" to match k8s API
          memory = var.gateway_resources.limits.memory
        }
      }

      # PodDisruptionBudget: keep at least 1 pod during node drains/upgrades
      podDisruptionBudget = {
        minAvailable = 1
      }

      config = {
        receivers = {
          otlp = {
            protocols = {
              grpc = { endpoint = "0.0.0.0:4317" }
              http = { endpoint = "0.0.0.0:4318" }
            }
          }
        }

        processors = {
          # Step 1: Memory guard — always first in pipeline
          memory_limiter = {
            check_interval  = "5s"
            limit_mib       = 1600
            spike_limit_mib = 400
          }

          # Step 2: Drop noise — health probes, kube-probe UAs, restify middleware,
          # OTel SDK self-traces, bare network connection spans
          "filter/noise" = {
            error_mode = "ignore"
            traces = {
              span = [
                "attributes[\"http.route\"] == \"/healthz\"",
                "attributes[\"http.route\"] == \"/readyz\"",
                "attributes[\"http.route\"] == \"/livez\"",
                "attributes[\"http.target\"] == \"/healthz\"",
                "attributes[\"http.target\"] == \"/readyz\"",
                "attributes[\"http.target\"] == \"/livez\"",
                "attributes[\"url.path\"] == \"/healthz\"",
                "attributes[\"url.path\"] == \"/readyz\"",
                "attributes[\"url.path\"] == \"/livez\"",
                "attributes[\"http.target\"] == \"/\"",
                "attributes[\"url.path\"] == \"/\"",
                "IsMatch(attributes[\"http.user_agent\"], \"ELB-HealthChecker.*\")",
                "IsMatch(attributes[\"http.user_agent\"], \"kube-probe.*\")",
                "IsMatch(attributes[\"user_agent.original\"], \"ELB-HealthChecker.*\")",
                "IsMatch(attributes[\"user_agent.original\"], \"kube-probe.*\")",
                "attributes[\"restify.type\"] == \"middleware\" and attributes[\"restify.name\"] != \"enrichContextPostAuth\" and attributes[\"restify.name\"] != \"enrichContextAndInjectSpans\" and attributes[\"restify.name\"] != \"setExecutionContext\"",
                "attributes[\"http.target\"] == \"/v1/metrics\"",
                "attributes[\"http.target\"] == \"/v1/traces\"",
                "attributes[\"http.target\"] == \"/v1/logs\"",
                "name == \"dns.lookup\"",
                "name == \"tcp.connect\"",
                "name == \"ipc.connect\"",
                "name == \"tls.connect\"",
                "name == \"redis-connect\"",
                "name == \"redis-CLUSTER\"",
                "name == \"redis-info\"",
                "IsMatch(name, \"pg-pool\\\\.connect\")",
                "name == \"mongodb.saslContinue\"",
                "name == \"mongodb.listCollections\""
              ]
            }
            metrics = {
              metric = ["name == \"health_check_requests_counter\""]
            }
          }

          # Step 3: Clean verbose process and path attributes to reduce span payload size
          "transform/clean-attributes" = {
            error_mode = "ignore"
            trace_statements = [
              {
                context    = "resource"
                statements = [
                  "delete_key(attributes, \"process.command_args\") where attributes[\"process.command_args\"] != nil",
                  "delete_key(attributes, \"process.command\") where attributes[\"process.command\"] != nil",
                  "delete_key(attributes, \"process.executable.path\") where attributes[\"process.executable.path\"] != nil",
                  "delete_key(attributes, \"process.executable.name\") where attributes[\"process.executable.name\"] != nil",
                  "delete_key(attributes, \"process.owner\") where attributes[\"process.owner\"] != nil",
                  "delete_key(attributes, \"os.type\") where attributes[\"os.type\"] != nil",
                  "delete_key(attributes, \"os.version\") where attributes[\"os.version\"] != nil"
                ]
              },
              {
                context    = "span"
                statements = [
                  "delete_key(attributes, \"db.connection_string\") where attributes[\"db.connection_string\"] != nil",
                  "truncate_all(attributes, 200) where attributes[\"db.statement\"] != nil"
                ]
              }
            ]
          }

          # Step 4: Derive peer.service for DB/queue spans so Jaeger shows them as
          # separate service nodes in the service dependency graph
          "transform/peer-service" = {
            error_mode = "ignore"
            trace_statements = [
              {
                context    = "span"
                statements = [
                  "set(attributes[\"peer.service\"], \"${var.app_namespace}-mongodb\") where attributes[\"db.system\"] == \"mongodb\" and attributes[\"peer.service\"] == nil",
                  "set(attributes[\"peer.service\"], \"${var.app_namespace}-redis\") where attributes[\"db.system\"] == \"redis\" and attributes[\"peer.service\"] == nil",
                  "set(attributes[\"peer.service\"], \"${var.app_namespace}-timescaledb\") where attributes[\"db.system\"] == \"postgresql\" and attributes[\"peer.service\"] == nil",
                  "set(attributes[\"peer.service\"], \"${var.app_namespace}-rabbitmq\") where attributes[\"messaging.system\"] == \"rabbitmq\" and attributes[\"peer.service\"] == nil"
                ]
              }
            ]
          }

          # Step 5: Tail sampling — decision_wait: 30s (covers async queue round-trip)
          # policies: always keep ERRORs and slow traces; probabilistic sample the rest
          tail_sampling = {
            decision_wait               = "${var.tail_sampling_decision_wait}s"
            num_traces                  = var.tail_sampling_num_traces
            expected_new_traces_per_sec = 500
            policies = [
              {
                name        = "errors-always"
                type        = "status_code"
                status_code = { status_codes = ["ERROR"] }
              },
              {
                name    = "slow-traces"
                type    = "latency"
                latency = { threshold_ms = var.tail_sampling_slow_threshold_ms }
              },
              {
                name          = "normal-probabilistic"
                type          = "probabilistic"
                probabilistic = { sampling_percentage = var.tail_sampling_normal_percentage }
              }
            ]
          }

          # Step 6: Batch — always last before export
          batch = {
            timeout             = "10s"
            send_batch_size     = 2048
            send_batch_max_size = 4096
          }
        }

        exporters = {
          # Primary trace backend: Jaeger via OTLP gRPC
          # retry + queue ensure no data loss during transient Jaeger unavailability
          "otlp/jaeger" = {
            endpoint = var.jaeger_endpoint
            tls      = { insecure = true }
            retry_on_failure = {
              enabled          = true
              initial_interval = "5s"
              max_interval     = "30s"
              max_elapsed_time = "300s"
            }
            sending_queue = {
              enabled       = true
              num_consumers = 4
              queue_size    = 5000
            }
          }

          # Prometheus remote write: push metrics to kube-prometheus-stack
        #   "prometheusremotewrite/prometheus" = {
        #     endpoint = var.prometheus_remote_write_endpoint
        #     tls      = { insecure = true }
        #     resource_to_telemetry_conversion = { enabled = true }
        #     retry_on_failure = {
        #       enabled          = true
        #       initial_interval = "5s"
        #       max_interval     = "30s"
        #       max_elapsed_time = "120s"
        #     }
        #   }

        # TODO: scrape data from prometheus receiver instead of remote write to avoid OTel collector → Prometheus → OTel collector loop for metrics

          # Scrape endpoint for Prometheus ServiceMonitor (port 8889)
          prometheus = {
            endpoint = "0.0.0.0:8889"
            resource_to_telemetry_conversion = { enabled = true }
          }
        }

        extensions = {
          health_check = { endpoint = "0.0.0.0:13133" }
          # memory_ballast reduces GC pressure: set to ~1/3 of memory limit
          # 2Gi limit → 683 MiB ballast
          memory_ballast = { size_mib = 683 }
        }

        service = {
          extensions = ["health_check", "memory_ballast"]
          pipelines = {
            traces = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "filter/noise", "transform/clean-attributes", "transform/peer-service", "tail_sampling", "batch"]
              exporters  = ["otlp/jaeger"]
            }
            metrics = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "batch"]
              exporters  = ["prometheus"] // "prometheusremotewrite/prometheus" check this
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
    kubernetes_service_account.otel_gateway,
    kubernetes_cluster_role_binding.otel_gateway
  ]
}
