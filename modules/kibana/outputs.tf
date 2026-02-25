output "service_name" {
  description = "Kubernetes Service name for Kibana (used in Ingress backend)"
  value       = "kibana-kibana"
}

output "endpoint" {
  description = "Internal cluster endpoint — host:port"
  value       = "kibana-kibana.${var.namespace}.svc.cluster.local:5601"
}

output "connection_url" {
  description = "Internal HTTP URL for Kibana"
  value       = "http://kibana-kibana.${var.namespace}.svc.cluster.local:5601"
}

output "helm_release_name" {
  description = "Helm release name"
  value       = helm_release.kibana.name
}

output "public_url" {
  description = "Public URL — HTTPS via ALB when create_ingress=true, internal URL otherwise"
  value       = var.create_ingress ? "https://${var.ingress_host}" : "http://kibana-kibana.${var.namespace}.svc.cluster.local:5601"
}
