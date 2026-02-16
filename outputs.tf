output "namespace" {
  description = "Kubernetes namespace for telemetry stack"
  value       = module.namespace.name
}

output "otel_collector_service_name" {
  description = "OTel Collector service name"
  value       = module.otel_collector.service_name
}

output "otel_collector_grpc_endpoint" {
  description = "OTel Collector OTLP gRPC endpoint"
  value       = "${module.otel_collector.service_name}.${module.namespace.name}.svc.cluster.local:4317"
}

output "otel_collector_http_endpoint" {
  description = "OTel Collector OTLP HTTP endpoint"
  value       = "${module.otel_collector.service_name}.${module.namespace.name}.svc.cluster.local:4318"
}

output "jaeger_query_service" {
  description = "Jaeger Query service name"
  value       = "jaeger-query.${module.namespace.name}.svc.cluster.local:16686"
}

output "jaeger_ui_port_forward_command" {
  description = "Command to port-forward Jaeger UI"
  value       = "kubectl port-forward -n ${module.namespace.name} svc/jaeger-query 16686:16686"
}

output "elasticsearch_endpoint" {
  description = "Elasticsearch endpoint (if enabled)"
  value       = var.elasticsearch_enabled ? "elasticsearch.${module.namespace.name}.svc.cluster.local:9200" : "N/A"
}

output "application_config_snippet" {
  description = "Configuration snippet for applications"
  value = {
    otlp_grpc_endpoint = "${module.otel_collector.service_name}.${module.namespace.name}.svc.cluster.local:4317"
    otlp_http_endpoint = "http://${module.otel_collector.service_name}.${module.namespace.name}.svc.cluster.local:4318"
    environment_variables = {
      OTEL_EXPORTER_OTLP_ENDPOINT = "http://${module.otel_collector.service_name}.${module.namespace.name}.svc.cluster.local:4318"
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    }
  }
}
