output "service_name" {
  description = "Elasticsearch service name"
  value       = "elasticsearch-master"
}

output "endpoint" {
  description = "Elasticsearch endpoint"
  value       = "elasticsearch-master.${var.namespace}.svc.cluster.local:9200"
}

output "helm_release_name" {
  description = "Elasticsearch Helm release name"
  value       = helm_release.elasticsearch.name
}

output "connection_url" {
  description = "Elasticsearch connection URL"
  value       = "http://elasticsearch-master.${var.namespace}.svc.cluster.local:9200"
}

