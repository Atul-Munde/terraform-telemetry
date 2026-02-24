output "agent_grpc_endpoint" {
  description = "OTel Agent OTLP gRPC endpoint (use this in app OTEL_EXPORTER_OTLP_ENDPOINT)"
  value       = "otel-agent-collector.${var.namespace}.svc.cluster.local:4317"
}

output "agent_http_endpoint" {
  description = "OTel Agent OTLP HTTP endpoint"
  value       = "http://otel-agent-collector.${var.namespace}.svc.cluster.local:4318"
}

output "gateway_metrics_endpoint" {
  description = "Gateway Prometheus scrape endpoint (port 8889)"
  value       = "otel-gateway-collector.${var.namespace}.svc.cluster.local:8889"
}

output "gateway_grpc_endpoint" {
  description = "Gateway OTLP gRPC endpoint (for direct integration if needed)"
  value       = "otel-gateway-collector.${var.namespace}.svc.cluster.local:4317"
}

output "operator_namespace" {
  description = "Namespace where the OTel Operator is installed"
  value       = var.namespace
}

output "instrumentation_annotation_command" {
  description = "Command to enable namespace-wide auto-instrumentation for Node.js"
  value       = "kubectl annotate namespace ${var.app_namespace} instrumentation.opentelemetry.io/inject-nodejs=\"${var.app_namespace}/nodejs-instrumentation\" && kubectl rollout restart deployment -n ${var.app_namespace}"
}
