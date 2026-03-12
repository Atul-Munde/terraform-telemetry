output "service_name" {
  description = "Elasticsearch coordinating service name (consumers connect here)"
  value       = "${var.cluster_name}-coordinating"
}

output "endpoint" {
  description = "Elasticsearch coordinating endpoint"
  value       = "${var.cluster_name}-coordinating.${var.namespace}.svc.cluster.local:9200"
}

output "master_service_name" {
  description = "Elasticsearch master service name"
  value       = "${var.cluster_name}-master"
}

output "master_endpoint" {
  description = "Elasticsearch master endpoint (internal — do not expose to consumers)"
  value       = "${var.cluster_name}-master.${var.namespace}.svc.cluster.local:9200"
}

output "data_service_name" {
  description = "Elasticsearch data service name"
  value       = "${var.cluster_name}-data"
}

output "helm_release_names" {
  description = "All Elasticsearch Helm release names"
  value = {
    master       = helm_release.elasticsearch_master.name
    data         = helm_release.elasticsearch_data.name
    coordinating = helm_release.elasticsearch_coordinating.name
  }
}

output "connection_url" {
  description = "Elasticsearch connection URL (via coordinating nodes)"
  value       = "${var.elastic_password != "" ? "https" : "http"}://${var.cluster_name}-coordinating.${var.namespace}.svc.cluster.local:9200"
}

output "cluster_name" {
  description = "Elasticsearch cluster name"
  value       = var.cluster_name
}

