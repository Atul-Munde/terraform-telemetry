# Instrumentation CRD — Node.js auto-instrumentation
# Deploying this CR + annotating the app namespace triggers zero-code instrumentation:
#   kubectl annotate namespace <app_namespace> \
#     instrumentation.opentelemetry.io/inject-nodejs="<namespace>/nodejs-instrumentation"
#   kubectl rollout restart deployment -n <app_namespace>
#
# The Operator injects an init-container that installs the OTel SDK before the app starts.

resource "kubernetes_manifest" "nodejs_instrumentation" {
  count = var.instrumentation_enabled ? 1 : 0

  manifest = {
    apiVersion = "opentelemetry.io/v1alpha1"
    kind       = "Instrumentation"
    metadata = {
      name      = "nodejs-instrumentation"
      namespace = var.app_namespace
      labels    = merge(local.common_labels, {
        "app.kubernetes.io/component" = "instrumentation"
      })
    }
    spec = {
      # Send to Agent on local node (low latency, no cross-node hop)
      exporter = {
        endpoint = "http://otel-agent-collector.${var.namespace}.svc.cluster.local:4318"
      }

      # W3C TraceContext + Baggage — mandatory for cross-service context propagation
      propagators = ["tracecontext", "baggage"]

      sampler = {
        # parentbased_traceidratio: respect parent's sampling decision.
        # argument "1" = 100% head sampling — Gateway tail_sampling does the filtering.
        # Do NOT set head sampling < 1 here; it would permanently drop traces before tail decision.
        type     = "parentbased_traceidratio"
        argument = "1"
      }

      nodejs = {
        # Pin to specific version — never use latest in production
        image = var.nodejs_instrumentation_image

        env = [
          {
            # gRPC protocol matches Agent receiver port 4317
            name  = "OTEL_EXPORTER_OTLP_PROTOCOL"
            value = "grpc"
          },
          {
            name  = "OTEL_TRACES_EXPORTER"
            value = "otlp"
          },
          {
            name  = "OTEL_METRICS_EXPORTER"
            value = "otlp"
          },
          {
            name  = "OTEL_LOGS_EXPORTER"
            value = "otlp"
          },
          {
            # EKS node + cloud resource detection
            name  = "OTEL_NODE_RESOURCE_DETECTORS"
            value = "env,host,os,process,container,aws"
          },
          {
            # Explicit instrumentation list — prevents surprise CPU overhead from
            # unknown libraries or future SDK additions
            name  = "OTEL_NODE_ENABLED_INSTRUMENTATIONS"
            value = var.enabled_instrumentations
          },
          {
            # FIX from otel_operator_v2: do NOT set this to ""  (wipes service.name).
            # Set namespace so services are filterable in Jaeger/Grafana.
            name  = "OTEL_RESOURCE_ATTRIBUTES"
            value = "service.namespace=${var.app_namespace}"
          }
        ]
      }
    }
  }

  depends_on = [helm_release.otel_operator]
}
