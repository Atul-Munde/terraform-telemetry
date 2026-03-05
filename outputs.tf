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

output "otel_public_otlp_url" {
  description = "Public OTLP HTTP endpoint for developers (https if ingress enabled)"
  value       = var.otel_operator_enabled ? module.otel_operator[0].public_otlp_url : "otel-operator disabled"
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

output "jaeger_url" {
  description = "Jaeger UI endpoint (public URL if ingress enabled, internal URL otherwise)"
  value       = module.jaeger.public_url
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

output "kibana_url" {
  description = "Kibana endpoint (public URL if ingress enabled, internal URL otherwise)"
  value       = var.kibana_enabled ? module.kibana[0].public_url : "kibana disabled"
}

output "prometheus_url" {
  description = "Prometheus endpoint (public URL if ingress enabled, internal URL otherwise)"
  value       = var.kube_prometheus_enabled ? module.kube_prometheus[0].prometheus_url : "kube-prometheus disabled"
}

output "grafana_url" {
  description = "Grafana endpoint (public URL if ingress enabled, internal URL otherwise)"
  value       = var.kube_prometheus_enabled ? module.kube_prometheus[0].grafana_url : "kube-prometheus disabled"
}

# ---------------------------------------------------------------------------
# VictoriaMetrics
# ---------------------------------------------------------------------------
output "vm_prometheus_remote_write_url" {
  description = "Full Prometheus remote-write URL for VictoriaMetrics. Set as prometheus_remote_write_endpoint in otel-operator module to replace kube-prometheus."
  value       = var.victoria_metrics_enabled ? module.victoria_metrics[0].prometheus_remote_write_url : "victoria-metrics disabled"
}

output "vm_grafana_datasource_url" {
  description = "Prometheus-compatible datasource URL for Grafana (VictoriaMetrics vmselect)"
  value       = var.victoria_metrics_enabled ? module.victoria_metrics[0].grafana_datasource_url : "victoria-metrics disabled"
}

output "vm_ui_url" {
  description = "Public vmselect UI URL (VMUI). Only populated when vm_create_ingress = true."
  value       = var.victoria_metrics_enabled ? module.victoria_metrics[0].vmselect_ui_url : "victoria-metrics disabled"
}

output "vm_backup_s3_bucket" {
  description = "S3 bucket used for VictoriaMetrics backups. Empty when vm_backup_enabled = false."
  value       = var.victoria_metrics_enabled ? module.victoria_metrics[0].backup_s3_bucket : "victoria-metrics disabled"
}
