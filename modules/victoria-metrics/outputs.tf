output "vminsert_endpoint" {
  description = "Internal cluster URL for sending Prometheus remote-write to VMCluster vminsert (port 8480)."
  value       = local.vminsert_url
}

output "vmselect_endpoint" {
  description = "Internal cluster URL for querying data from VMCluster vmselect (port 8481)."
  value       = local.vmselect_url
}

output "prometheus_remote_write_url" {
  description = "Full Prometheus remote-write URL. Use this in OTel Collector, Prometheus, or any scraper configured to send metrics to VictoriaMetrics."
  value       = "${local.vminsert_url}/insert/0/prometheus/api/v1/write"
}

output "grafana_datasource_url" {
  description = "Prometheus-compatible datasource URL to use in Grafana when adding a VictoriaMetrics data source."
  value       = "${local.vmselect_url}/select/0/prometheus"
}

output "vmselect_ui_url" {
  description = "Public UI URL for vmselect (via ALB). Only populated when create_ingress = true and vmselect_ingress_host is set."
  value       = var.create_ingress && var.vmselect_ingress_host != "" ? "https://${var.vmselect_ingress_host}" : ""
}

output "vmauth_url" {
  description = "Internal cluster URL for VMAuth proxy. Only populated when vmauth_enabled = true."
  value       = var.vmauth_enabled ? "http://vmauth-vmauth.${var.namespace}.svc.cluster.local:8427" : ""
}

output "backup_s3_bucket" {
  description = "Name of the S3 bucket used for VictoriaMetrics backups. Empty when backup_enabled = false."
  value       = var.backup_enabled ? local.s3_bucket_name : ""
}

output "backup_s3_bucket_arn" {
  description = "ARN of the S3 backup bucket. Empty when backup_enabled = false."
  value       = var.backup_enabled ? aws_s3_bucket.vmbackup[0].arn : ""
}

output "vmbackup_iam_role_arn" {
  description = "IAM role ARN (IRSA) used by the vmbackup Kubernetes service account to access S3. Empty when backup_enabled = false."
  value       = var.backup_enabled ? aws_iam_role.vmbackup[0].arn : ""
  sensitive   = false
}

output "operator_namespace" {
  description = "Kubernetes namespace where the VictoriaMetrics Operator is deployed."
  value       = var.vm_operator_namespace
}

output "operator_helm_release_name" {
  description = "Name of the Helm release for the VictoriaMetrics Operator."
  value       = helm_release.vm_operator.name
}

output "storage_class_name" {
  description = "Name of the StorageClass used for vmstorage PVCs."
  value       = local.effective_storage_class
}

output "vmcluster_name" {
  description = "Name of the VMCluster custom resource."
  value       = var.vm_cluster_name
}

output "namespace" {
  description = "Kubernetes namespace where VictoriaMetrics components are deployed."
  value       = var.namespace
}
