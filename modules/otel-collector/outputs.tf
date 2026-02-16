output "service_name" {
  description = "OTel Collector service name"
  value       = kubernetes_service.otel_collector.metadata[0].name
}

output "deployment_name" {
  description = "OTel Collector deployment name"
  value       = kubernetes_deployment.otel_collector.metadata[0].name
}

output "grpc_endpoint" {
  description = "OTLP gRPC endpoint"
  value       = "${kubernetes_service.otel_collector.metadata[0].name}.${var.namespace}.svc.cluster.local:4317"
}

output "http_endpoint" {
  description = "OTLP HTTP endpoint"
  value       = "${kubernetes_service.otel_collector.metadata[0].name}.${var.namespace}.svc.cluster.local:4318"
}

output "metrics_endpoint" {
  description = "Metrics endpoint"
  value       = "${kubernetes_service.otel_collector.metadata[0].name}.${var.namespace}.svc.cluster.local:8888"
}
