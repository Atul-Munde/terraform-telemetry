output "namespace" {
  description = "Kubernetes namespace for telemetry stack"
  value       = module.namespace.name
}

# ---------------------------------------------------------------------------
# OTel Agent endpoints (apps should send telemetry here)
# ---------------------------------------------------------------------------
output "otel_agent_grpc_endpoint" {
  description = "OTel Agent OTLP gRPC endpoint — use as OTEL_EXPORTER_OTLP_ENDPOINT"
  value       = var.otel_operator_enabled ? module.otel_operator[0].agent_grpc_endpoint : "otel-operator disabled"
}

output "otel_agent_http_endpoint" {
  description = "OTel Agent OTLP HTTP endpoint"
  value       = var.otel_operator_enabled ? module.otel_operator[0].agent_http_endpoint : "otel-operator disabled"
}

output "otel_gateway_metrics_endpoint" {
  description = "Gateway Prometheus scrape endpoint (port 8889)"
  value       = var.otel_operator_enabled ? module.otel_operator[0].gateway_metrics_endpoint : "otel-operator disabled"
}

output "instrumentation_annotation_command" {
  description = "Command to enable namespace-wide Node.js auto-instrumentation"
  value       = var.otel_operator_enabled ? module.otel_operator[0].instrumentation_annotation_command : "otel-operator disabled"
}

# ---------------------------------------------------------------------------
# Jaeger
# ---------------------------------------------------------------------------
output "jaeger_query_service" {
  description = "Jaeger Query service name"
  value       = "jaeger-query.${module.namespace.name}.svc.cluster.local:16686"
}

output "jaeger_ui_port_forward_command" {
  description = "Command to port-forward Jaeger UI"
  value       = "kubectl port-forward -n ${module.namespace.name} svc/jaeger-query 16686:16686"
}

# ---------------------------------------------------------------------------
# Elasticsearch
# ---------------------------------------------------------------------------
output "elasticsearch_endpoint" {
  description = "Elasticsearch endpoint (if enabled)"
  value       = var.elasticsearch_enabled ? "elasticsearch.${module.namespace.name}.svc.cluster.local:9200" : "N/A"
}

# ---------------------------------------------------------------------------
# Application config snippet
# ---------------------------------------------------------------------------
output "application_config_snippet" {
  description = "Environment variables snippet for instrumenting applications"
  value = {
    otlp_grpc_endpoint = var.otel_operator_enabled ? module.otel_operator[0].agent_grpc_endpoint : ""
    otlp_http_endpoint = var.otel_operator_enabled ? module.otel_operator[0].agent_http_endpoint : ""
    environment_variables = {
      OTEL_EXPORTER_OTLP_ENDPOINT = var.otel_operator_enabled ? "http://${module.otel_operator[0].agent_http_endpoint}" : ""
      OTEL_EXPORTER_OTLP_PROTOCOL = "grpc"
      OTEL_SERVICE_NAME           = "<your-service-name>"
      OTEL_RESOURCE_ATTRIBUTES    = "service.namespace=${var.app_namespace}"
    }
  }
}
