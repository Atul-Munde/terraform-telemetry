# Agent Collector — DaemonSet CRD
# Runs on every node labeled otel-agent=true.
# Responsibilities:
#   - Receive OTLP from auto-instrumented app pods on the same node
#   - Collect kubeletstats (node/pod/container metrics) from local kubelet
#   - Read container logs (filelog) from /var/log/pods
#   - Enrich with EKS cloud metadata (resourcedetection/eks)
#   - Enrich with K8s pod metadata (k8sattributes)
#   - Forward TRACES via loadbalancing exporter (routes by traceID hash → same Gateway pod)
#   - Forward METRICS/LOGS via round-robin OTLP to Gateway

resource "kubernetes_manifest" "otel_agent" {
  # force_conflicts: reclaim field ownership from kubectl-patch commands run outside Terraform
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "opentelemetry.io/v1beta1"
    kind       = "OpenTelemetryCollector"

    metadata = {
      name      = "otel-agent"
      namespace = var.namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "otel-agent"
      })
    }

    spec = {
      mode           = "daemonset"
      serviceAccount = kubernetes_service_account.otel_agent.metadata[0].name
      image          = "${var.agent_image}:${var.agent_image_tag}"

      nodeSelector = var.agent_node_selector

      resources = {
        requests = {
          cpu    = local._norm_cpu.ag_req  # normalized to match k8s API storage format
          memory = var.agent_resources.requests.memory
        }
        limits = {
          cpu    = local._norm_cpu.ag_lim  # normalized to match k8s API storage format
          memory = var.agent_resources.limits.memory
        }
      }

      env = [
        {
          name = "K8S_NODE_NAME"
          valueFrom = {
            fieldRef = { fieldPath = "spec.nodeName" }
          }
        },
        {
          name = "K8S_POD_IP"
          valueFrom = {
            fieldRef = { fieldPath = "status.podIP" }
          }
        }
      ]

      volumeMounts = [
        {
          name      = "varlogpods"
          mountPath = "/var/log/pods"
          readOnly  = true
        }
      ]

      volumes = [
        {
          name = "varlogpods"
          hostPath = { path = "/var/log/pods" }
        }
      ]

      config = {
        receivers = {
          otlp = {
            protocols = {
              grpc = { endpoint = "0.0.0.0:4317" }
              http = { endpoint = "0.0.0.0:4318" }
            }
          }

          kubeletstats = {
            collection_interval  = "30s"
            auth_type            = "serviceAccount"
            endpoint             = "https://$${K8S_NODE_NAME}:10250"
            insecure_skip_verify = var.kubeletstats_insecure_skip_verify
            metric_groups        = ["node", "pod", "container"]
          }

          filelog = {
            include           = ["/var/log/pods/${var.app_namespace}_*/*/*.log"]
            exclude           = ["/var/log/pods/${var.namespace}_otel-agent*/**/*.log"]
            include_file_path = true
            operators = [
              { type = "container", id = "container-parser" }
            ]
          }
        }

        processors = {
          memory_limiter = {
            check_interval    = "5s"
            limit_mib         = 400
            spike_limit_mib   = 80
          }

          # EKS cloud + node metadata: cloud.provider, cloud.region, k8s.cluster.name, host.id
          "resourcedetection/eks" = {
            detectors = ["env", "eks", "ec2"]
            timeout   = "15s"
            override  = false
            eks = {
              resource_attributes = {
                "k8s.cluster.name" = { enabled = true }
              }
            }
            ec2 = {
              resource_attributes = {
                "cloud.provider"           = { enabled = true }
                "cloud.platform"           = { enabled = true }
                "cloud.region"             = { enabled = true }
                "cloud.availability_zone"  = { enabled = true }
                "host.id"                  = { enabled = true }
                "host.name"                = { enabled = true }
              }
            }
          }

          # K8s pod metadata: namespace, deployment, pod name, node, container
          k8sattributes = {
            auth_type   = "serviceAccount"
            passthrough = false
            extract = {
              metadata = [
                "k8s.namespace.name",
                "k8s.deployment.name",
                "k8s.pod.name",
                "k8s.pod.uid",
                "k8s.node.name",
                "k8s.container.name"
              ]
              labels = [
                {
                  tag_name = "app.kubernetes.io/name"
                  key      = "app.kubernetes.io/name"
                  from     = "pod"
                },
                {
                  tag_name = "app.kubernetes.io/version"
                  key      = "app.kubernetes.io/version"
                  from     = "pod"
                }
              ]
            }
            pod_association = [
              { sources = [{ from = "resource_attribute", name = "k8s.pod.ip" }] },
              { sources = [{ from = "resource_attribute", name = "k8s.pod.uid" }] },
              { sources = [{ from = "connection" }] }
            ]
          }

          # Drop pod/container metrics from non-target namespaces.
          # Node metrics (no namespace attr) pass through unaffected.
          "filter/kubeletstats" = {
            error_mode = "ignore"
            metrics = {
              datapoint = [
                "resource.attributes[\"k8s.namespace.name\"] != nil and resource.attributes[\"k8s.namespace.name\"] != \"${var.app_namespace}\""
              ]
            }
          }

          # Copy k8s.pod.name → service.instance.id (OTel semantic convention).
          # Done here on the Agent (not the Gateway) because only the Agent has the
          # app pod's k8s metadata at this point. The Gateway would stamp its own
          # pod name, overwriting the app's identity.
          # Effect in Jaeger: each replica of a service appears as a distinct instance
          # node, making it easy to spot per-pod errors or latency outliers.
          resource = {
            attributes = [
              {
                key            = "service.instance.id"
                from_attribute = "k8s.pod.name"
                action         = "insert"  # insert = only set if not already present
              }
            ]
          }

          batch = {
            timeout             = "5s"
            send_batch_size     = 1024
            send_batch_max_size = 2048
          }
        }

        exporters = {
          # TRACES: loadbalancing routes by traceID hash.
          # All spans of one trace hit the same Gateway StatefulSet pod.
          # This is REQUIRED for tail_sampling to work correctly.
          loadbalancing = {
            protocol = {
              otlp = {
                tls     = { insecure = true }
                timeout = "10s"
              }
            }
            resolver = {
              dns = {
                # StatefulSet headless service returns all pod IPs
                hostname = "otel-gateway-collector-headless.${var.namespace}.svc.cluster.local"
                port     = "4317"  # must be string in otelcol >= 0.105.0 (confmap.strictlyTypedInput)
                interval = "5s"
                timeout  = "1s"
              }
            }
          }

          # METRICS + LOGS: round-robin to Gateway ClusterIP service (fine for non-trace signals)
          "otlp/gateway" = {
            endpoint = "otel-gateway-collector.${var.namespace}.svc.cluster.local:4317"
            tls      = { insecure = true }
          }
        }

        extensions = {
          health_check = { endpoint = "0.0.0.0:13133" }
        }

        service = {
          extensions = ["health_check"]
          pipelines = {
            traces = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "resourcedetection/eks", "k8sattributes", "resource", "batch"]
              exporters  = ["loadbalancing"]
            }
            metrics = {
              receivers  = ["otlp", "kubeletstats"]
              processors = ["memory_limiter", "resourcedetection/eks", "k8sattributes", "resource", "filter/kubeletstats", "batch"]
              exporters  = ["otlp/gateway"]
            }
            logs = {
              receivers  = ["filelog"]
              processors = ["memory_limiter", "resourcedetection/eks", "k8sattributes", "resource", "batch"]
              exporters  = ["otlp/gateway"]
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
    kubernetes_service_account.otel_agent,
    kubernetes_cluster_role_binding.otel_agent
  ]
}
