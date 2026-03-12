# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------
variable "namespace" {
  description = "Kubernetes namespace where VictoriaMetrics components are deployed"
  type        = string
  default     = "telemetry"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector applied to all VictoriaMetrics pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations applied to all VictoriaMetrics pods"
  type = list(object({
    key                = string
    operator           = string
    value              = optional(string)
    effect             = optional(string)
    toleration_seconds = optional(number)
  }))
  default = []
}

# ---------------------------------------------------------------------------
# VictoriaMetrics Operator (Helm)
# ---------------------------------------------------------------------------
variable "vm_operator_chart_version" {
  description = "Helm chart version for victoria-metrics-operator"
  type        = string
  default     = "0.59.1"
}

variable "vm_operator_namespace" {
  description = "Namespace where the VictoriaMetrics Operator controller pod runs"
  type        = string
  default     = "victoria-metrics-operator-system"
}

variable "vm_operator_replicas" {
  description = "Operator deployment replicas (2 for active-active HA via leader election)"
  type        = number
  default     = 1
}

variable "vm_operator_resources" {
  description = "CPU/memory for the operator pod"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "256Mi" }
  }
}

# ---------------------------------------------------------------------------
# VMCluster
# ---------------------------------------------------------------------------
variable "vm_cluster_name" {
  description = "Name of the VMCluster CR — operator derives service names from this"
  type        = string
  default     = "vmcluster"
}

variable "vmstorage_replicas" {
  description = "Number of vmstorage StatefulSet replicas. Must be >= 2*replication_factor-1 for HA"
  type        = number
  default     = 3
  validation {
    condition     = var.vmstorage_replicas >= 3
    error_message = "vmstorage_replicas must be >= 3 to support replicationFactor=2 with full HA."
  }
}

variable "vminsert_replicas" {
  description = "Baseline vminsert Deployment replicas (HPA adjusts from here)"
  type        = number
  default     = 3
  validation {
    condition     = var.vminsert_replicas >= 2
    error_message = "vminsert_replicas must be >= 2 — single replica is a SPOF for all write traffic."
  }
}

variable "vmselect_replicas" {
  description = "Baseline vmselect Deployment replicas (HPA adjusts from here)"
  type        = number
  default     = 3
  validation {
    condition     = var.vmselect_replicas >= 2
    error_message = "vmselect_replicas must be >= 2 — single replica is a SPOF for all query traffic."
  }
}

variable "replication_factor" {
  description = "Number of copies stored for each ingested sample. vminsert writes N copies across N distinct vmstorage nodes"
  type        = number
  default     = 2
  validation {
    condition     = var.replication_factor >= 1
    error_message = "replication_factor must be >= 1."
  }
}

variable "retention_period" {
  description = "Data retention period. Accepts: Nm (months), Nd (days), Nh (hours). E.g. '7d', '1M', '90d'"
  type        = string
  default     = "7d"
}

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------
variable "vmstorage_resources" {
  description = "CPU/memory for each vmstorage pod"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "500m", memory = "1Gi" }
    limits   = { cpu = "1",    memory = "2Gi" }
  }
}

variable "vminsert_resources" {
  description = "CPU/memory for each vminsert pod"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "200m", memory = "256Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

variable "vmselect_resources" {
  description = "CPU/memory for each vmselect pod"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "200m", memory = "512Mi" }
    limits   = { cpu = "1",    memory = "1Gi" }
  }
}

variable "vmagent_resources" {
  description = "CPU/memory for the vmagent pod"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

variable "vmalert_resources" {
  description = "CPU/memory for the vmalert pod"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "300m", memory = "256Mi" }
  }
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------
variable "vmstorage_storage_size" {
  description = "PVC size per vmstorage pod. Size for 7d retention at 1M samples/sec ~ 50-100Gi; scale up for longer retention"
  type        = string
  default     = "100Gi"
}

variable "vmselect_cache_storage_size" {
  description = "PVC size for vmselect query result cache"
  type        = string
  default     = "20Gi"
}

variable "storage_class_name" {
  description = "Storage class for vmstorage PVCs. Created by this module when create_storage_class=true"
  type        = string
  default     = "vm-storage-gp3"
}

variable "create_storage_class" {
  description = "Create the EBS gp3 StorageClass. Disable if the class already exists in the cluster"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# HPA
# ---------------------------------------------------------------------------
variable "vminsert_min_replicas" {
  description = "HPA minimum replicas for vminsert"
  type        = number
  default     = 3
}

variable "vminsert_max_replicas" {
  description = "HPA maximum replicas for vminsert"
  type        = number
  default     = 10
}

variable "vmselect_min_replicas" {
  description = "HPA minimum replicas for vmselect"
  type        = number
  default     = 3
}

variable "vmselect_max_replicas" {
  description = "HPA maximum replicas for vmselect"
  type        = number
  default     = 10
}

# ---------------------------------------------------------------------------
# Ingress / ALB
# ---------------------------------------------------------------------------
variable "create_ingress" {
  description = "Create an AWS ALB Ingress to expose vmselect UI / query API publicly"
  type        = bool
  default     = false
}

variable "vmselect_ingress_host" {
  description = "Public hostname for vmselect — e.g. vm.test.example.com"
  type        = string
  default     = ""
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for ALB HTTPS listener"
  type        = string
  default     = ""
}

variable "alb_group_name" {
  description = "ALB ingress group name (merges multiple ingresses onto a single ALB)"
  type        = string
  default     = ""
}

variable "ingress_class_name" {
  description = "Kubernetes Ingress class name"
  type        = string
  default     = "alb"
}

# ---------------------------------------------------------------------------
# Feature toggles
# ---------------------------------------------------------------------------
variable "vmauth_enabled" {
  description = "Deploy VMAuth as an auth gateway in front of vminsert/vmselect"
  type        = bool
  default     = false
}

variable "vmauth_password" {
  description = "Password for VMAuth basic authentication. Only used when vmauth_enabled=true"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vmagent_enabled" {
  description = "Deploy VMAgent to scrape cluster metrics and feed them into VMCluster"
  type        = bool
  default     = true
}

variable "vmalert_enabled" {
  description = "Deploy VMAlert for alerting rules evaluation"
  type        = bool
  default     = false
}

variable "kube_prometheus_enabled" {
  description = "Create ServiceMonitor resources for scraping by kube-prometheus-stack Prometheus"
  type        = bool
  default     = false
}

variable "alertmanager_url" {
  description = "Alertmanager URL for VMAlert to send notifications to"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Backup / S3
# ---------------------------------------------------------------------------
variable "backup_enabled" {
  description = "Create S3 bucket and CronJob for vmbackup"
  type        = bool
  default     = false
}

variable "backup_schedule" {
  description = "Cron expression for backup job — default is 02:00 UTC daily"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_s3_bucket_name" {
  description = "S3 bucket name for vmbackup storage. Leave empty to auto-generate: vm-backup-<environment>"
  type        = string
  default     = ""
}

variable "backup_s3_region" {
  description = "AWS region for the backup S3 bucket"
  type        = string
  default     = "ap-south-1"
}

variable "backup_retention_days" {
  description = "S3 lifecycle expiry in days for backup objects"
  type        = number
  default     = 30
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN used to create the IRSA trust policy for the vmbackup service account. Required when backup_enabled=true"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# MongoDB Exporter Scraping
# ---------------------------------------------------------------------------
variable "mongodb_scrape_enabled" {
  description = "Enable VMServiceScrape to scrape the bitnami-mongodb-exporter sidecar via VMAgent"
  type        = bool
  default     = false
}

variable "mongodb_exporter_namespace" {
  description = "Namespace to restrict MongoDB scraping to. Leave empty (\"\") to scrape mongodb-exporter services across ALL namespaces (recommended when multiple MongoDB clusters exist in different namespaces)."
  type        = string
  default     = ""
}

variable "mongodb_exporter_service_labels" {
  description = "matchLabels selector to identify mongodb-exporter Kubernetes Services. Use only labels that are constant across ALL MongoDB clusters (e.g. app.kubernetes.io/component + app.kubernetes.io/name). Avoid instance-specific labels like app.kubernetes.io/instance."
  type        = map(string)
  default     = {}
}

variable "mongodb_exporter_port" {
  description = "Named port on the mongodb-exporter Service that exposes /metrics (bitnami chart default: http-metrics)"
  type        = string
  default     = "http-metrics"
}

# ---------------------------------------------------------------------------
# PostgreSQL / TimescaleDB Exporter Scraping
# ---------------------------------------------------------------------------
variable "postgres_scrape_enabled" {
  description = "Enable VMServiceScrape to scrape postgres-exporter sidecars via VMAgent"
  type        = bool
  default     = false
}

variable "postgres_exporter_namespace" {
  description = "Namespace to restrict postgres scraping to. Leave empty (\"\") to scrape postgres-exporter services across ALL namespaces."
  type        = string
  default     = ""
}

variable "postgres_exporter_label_key" {
  description = "Label key present on ALL postgres-exporter Services (value may differ per cluster). VMServiceScrape uses matchExpressions/Exists so every cluster is discovered regardless of value."
  type        = string
  default     = "pg-exporter-service"
}

variable "postgres_exporter_port" {
  description = "Container port number on the postgres-exporter that exposes /metrics (standard prometheus-postgres-exporter default: 9187)"
  type        = number
  default     = 9187
}

# ---------------------------------------------------------------------------
# ScyllaDB Native Metrics Scraping
# ---------------------------------------------------------------------------
variable "scylladb_scrape_enabled" {
  description = "Enable VMServiceScrape to scrape ScyllaDB native Prometheus metrics via VMAgent"
  type        = bool
  default     = false
}

variable "scylladb_exporter_namespace" {
  description = "Namespace to restrict ScyllaDB scraping to. Leave empty (\"\") to scrape across ALL namespaces (recommended when multiple ScyllaDB clusters exist in different namespaces)."
  type        = string
  default     = ""
}

variable "scylladb_exporter_service_labels" {
  description = "matchLabels selector to identify ScyllaDB Services that expose the native Prometheus endpoint. The Scylla Operator sets app.kubernetes.io/name=scylla on all ScyllaDB cluster Services."
  type        = map(string)
  default     = { "app.kubernetes.io/name" = "scylla" }
}

variable "scylladb_exporter_port" {
  description = "Container port number for ScyllaDB's built-in native Prometheus endpoint (default: 9180)"
  type        = number
  default     = 9180
}

# ---------------------------------------------------------------------------
# Redis Exporter Scraping
# ---------------------------------------------------------------------------
variable "redis_scrape_enabled" {
  description = "Enable VMServiceScrape to scrape redis-exporter sidecars via VMAgent"
  type        = bool
  default     = false
}

variable "redis_exporter_namespace" {
  description = "Namespace to restrict Redis scraping to. Leave empty (\"\") to scrape redis-exporter services across ALL namespaces (recommended when multiple Redis clusters exist in different namespaces)."
  type        = string
  default     = ""
}

variable "redis_exporter_service_labels" {
  description = "matchLabels selector to identify redis-exporter Kubernetes Services."
  type        = map(string)
  default     = { "release" = "kube-prometheus-stack" }
}

variable "redis_exporter_port" {
  description = "Container port number on the redis-exporter that exposes /metrics (standard prometheus redis-exporter default: 9121)"
  type        = number
  default     = 9121
}

# ---------------------------------------------------------------------------
# Elasticsearch metrics scraping
# ---------------------------------------------------------------------------
variable "elasticsearch_scrape_enabled" {
  description = "Enable VMServiceScrape to scrape Elasticsearch /_prometheus/metrics via VMAgent"
  type        = bool
  default     = false
}

variable "elasticsearch_service_labels" {
  description = "matchLabels selector to identify Elasticsearch Kubernetes Services for metrics scraping."
  type        = map(string)
  default     = { "app" = "elasticsearch-coordinating" }
}
