output "query_service_name" {
  description = "Jaeger Query service name"
  value       = "${local.release_name}-query"
}

output "collector_service_name" {
  description = "Jaeger Collector service name"
  value       = "${local.release_name}-collector"
}

output "query_ui_url" {
  description = "Jaeger Query UI URL (internal)"
  value       = "http://${local.release_name}-query.${var.namespace}.svc.cluster.local:16686"
}

output "collector_grpc_endpoint" {
  description = "Jaeger Collector gRPC endpoint"
  value       = "${local.release_name}-collector.${var.namespace}.svc.cluster.local:14250"
}

output "collector_http_endpoint" {
  description = "Jaeger Collector HTTP endpoint"
  value       = "${local.release_name}-collector.${var.namespace}.svc.cluster.local:14268"
}
