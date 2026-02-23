# kube-prometheus-stack Module Outputs

output "namespace" {
  description = "Namespace where kube-prometheus-stack is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.kube_prometheus_stack.name
}

output "release_status" {
  description = "Helm release status"
  value       = helm_release.kube_prometheus_stack.status
}

output "grafana_service" {
  description = "Grafana service name"
  value       = "${helm_release.kube_prometheus_stack.name}-grafana"
}

output "prometheus_service" {
  description = "Prometheus service name"
  value       = "${helm_release.kube_prometheus_stack.name}-prometheus"
}

output "alertmanager_service" {
  description = "Alertmanager service name"
  value       = "${helm_release.kube_prometheus_stack.name}-alertmanager"
}

output "prometheus_url" {
  description = "Internal Prometheus URL"
  value       = "http://${helm_release.kube_prometheus_stack.name}-prometheus.${var.namespace}.svc.cluster.local:9090"
}

output "grafana_url" {
  description = "Internal Grafana URL"
  value       = "http://${helm_release.kube_prometheus_stack.name}-grafana.${var.namespace}.svc.cluster.local:80"
}

output "alertmanager_url" {
  description = "Internal Alertmanager URL"
  value       = "http://${helm_release.kube_prometheus_stack.name}-alertmanager.${var.namespace}.svc.cluster.local:9093"
}
