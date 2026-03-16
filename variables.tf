variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "namespace" {
  description = "Kubernetes namespace for telemetry stack"
  type        = string
  default     = "telemetry"
}

variable "create_namespace" {
  description = "Whether to create the namespace"
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region used by the AWS provider"
  type        = string
  default     = "ap-south-1"
}

# ---------------------------------------------------------------------------
# OTel Operator
# ---------------------------------------------------------------------------
variable "otel_operator_enabled" {
  description = "Install the OpenTelemetry Operator and all collector CRDs"
  type        = bool
  default     = true
}

variable "otel_operator_chart_version" {
  description = "opentelemetry-operator Helm chart version"
  type        = string
  default     = "0.66.0"
}

variable "otel_operator_replicas" {
  description = "Number of OTel Operator controller-manager replicas (>=2 for HA)"
  type        = number
  default     = 2
}

variable "otel_collector_image_tag" {
  description = "otelcol-contrib image tag (without registry prefix)"
  type        = string
  default     = "0.105.0"  # matches operator chart 0.66.0 bundled default (app_version)
}

variable "app_namespace" {
  description = "Application namespace to monitor for pod logs and auto-instrumentation"
  type        = string
  default     = "telemetry"
}

# ---------------------------------------------------------------------------
# OTel Agent (DaemonSet)
# ---------------------------------------------------------------------------
variable "otel_agent_resources" {
  description = "Resource requests and limits for the OTel Agent DaemonSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "250m"
      memory = "512Mi"
    }
  }
}

variable "otel_agent_node_selector" {
  description = "Node selector for the OTel Agent DaemonSet"
  type        = map(string)
  default = {
    "otel-agent" = "true"
  }
}

variable "kubeletstats_insecure_skip_verify" {
  description = "Skip TLS verification for kubeletstats receiver (EKS uses self-signed kubelet cert)"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# OTel Gateway (StatefulSet — required for tail_sampling correctness)
# ---------------------------------------------------------------------------
variable "gateway_min_replicas" {
  description = "Minimum Gateway StatefulSet replicas — must be >=2 to avoid SPOF"
  type        = number
  default     = 2
  validation {
    condition     = var.gateway_min_replicas >= 2
    error_message = "gateway_min_replicas must be >= 2 to ensure tail_sampling correctness."
  }
}

variable "gateway_max_replicas" {
  description = "Maximum Gateway replicas for HPA"
  type        = number
  default     = 8
}

variable "otel_gateway_resources" {
  description = "Resource requests and limits for the OTel Gateway StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "2Gi"
    }
  }
}

# ---------------------------------------------------------------------------
# Tail sampling
# ---------------------------------------------------------------------------
variable "tail_sampling_decision_wait" {
  description = "Seconds to wait before making a sampling decision (allow async spans to arrive)"
  type        = number
  default     = 30
}

variable "tail_sampling_normal_percentage" {
  description = "Percentage of normal (non-error, non-slow) traces to keep"
  type        = number
  default     = 50
}

variable "tail_sampling_slow_threshold_ms" {
  description = "Latency threshold in ms — traces above this are always kept"
  type        = number
  default     = 2000
}

variable "tail_sampling_num_traces" {
  description = "Number of traces to hold in memory at once"
  type        = number
  default     = 50000
}

# ---------------------------------------------------------------------------
# Infra metrics collector (optional Deployment)
# ---------------------------------------------------------------------------
variable "infra_metrics_enabled" {
  description = "Deploy a separate OTel collector for infrastructure DB metrics"
  type        = bool
  default     = false
}

variable "infra_metrics_resources" {
  description = "Resource requests and limits for the infra metrics collector"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "mongodb_host" {
  description = "MongoDB host for infra metrics (e.g. mongodb.telemetry.svc.cluster.local:27017)"
  type        = string
  default     = ""
}

variable "mongodb_username" {
  description = "MongoDB username for infra metrics"
  type        = string
  default     = ""
}

variable "mongodb_password" {
  description = "MongoDB password for infra metrics"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rabbitmq_host" {
  description = "RabbitMQ management host (e.g. rabbitmq.telemetry.svc.cluster.local:15692)"
  type        = string
  default     = ""
}

variable "rabbitmq_username" {
  description = "RabbitMQ username for infra metrics"
  type        = string
  default     = ""
}

variable "rabbitmq_password" {
  description = "RabbitMQ password for infra metrics"
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_host" {
  description = "Redis host for infra metrics (e.g. redis.telemetry.svc.cluster.local:6379)"
  type        = string
  default     = ""
}

variable "postgresql_host" {
  description = "PostgreSQL host for infra metrics"
  type        = string
  default     = ""
}

variable "postgresql_username" {
  description = "PostgreSQL username for infra metrics"
  type        = string
  default     = ""
}

variable "postgresql_password" {
  description = "PostgreSQL password for infra metrics"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------------------------
# Auto-instrumentation
# ---------------------------------------------------------------------------
variable "instrumentation_enabled" {
  description = "Create an Instrumentation CR for Node.js auto-instrumentation"
  type        = bool
  default     = true
}

variable "nodejs_instrumentation_image" {
  description = "Node.js auto-instrumentation image"
  type        = string
  default     = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.69.0"
}

variable "otel_enabled_instrumentations" {
  description = "Comma-separated list of instrumentations to enable in Node.js agent"
  type        = string
  default     = "http,grpc,express,restify,koa,connect,dns,net,pg,mysql,mysql2,mongodb,redis,ioredis,memcached,aws-sdk,kafkajs,amqplib,graphql,winston,bunyan,pino"
}

variable "jaeger_chart_version" {
  description = "Jaeger Helm chart version"
  type        = string
  default     = "2.0.0"
}

variable "jaeger_storage_type" {
  description = "Jaeger storage backend type (elasticsearch, cassandra, badger)"
  type        = string
  default     = "elasticsearch"
}

variable "elasticsearch_enabled" {
  description = "Enable Elasticsearch deployment"
  type        = bool
  default     = true
}

variable "kube_prometheus_enabled" {
  description = "Enable kube-prometheus-stack deployment"
  type        = bool
  default     = true
}

variable "kube_prometheus_create_storage_classes" {
  description = "Create storage classes for kube-prometheus-stack"
  type        = bool
  default     = true
}

variable "grafana_existing_claim" {
  description = "Existing Grafana PVC name. Set to '<release_name>-grafana' after first install to prevent Helm patching the immutable volumeName field. Leave empty for fresh installs."
  type        = string
  default     = ""
}

variable "prometheus_resources" {
  description = "Prometheus resource requests and limits"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "1000m"
      memory = "2Gi"
    }
    limits = {
      cpu    = "4000m"
      memory = "8Gi"
    }
  }
}

variable "elasticsearch_replicas" {
  description = "Number of Elasticsearch replicas"
  type        = number
  default     = 1
}

variable "elasticsearch_storage_size" {
  description = "Elasticsearch PVC size"
  type        = string
  default     = "50Gi"
}

variable "elasticsearch_storage_class" {
  description = "Storage class for Elasticsearch PVCs"
  type        = string
  default     = "gp3"
}

variable "elasticsearch_resources" {
  description = "Resource requests and limits for Elasticsearch"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "1000m"
      memory = "2Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "4Gi"
    }
  }
}

variable "jaeger_query_replicas" {
  description = "Number of Jaeger Query replicas"
  type        = number
  default     = 2
}

variable "jaeger_collector_replicas" {
  description = "Number of Jaeger Collector replicas"
  type        = number
  default     = 2
}

variable "jaeger_create_ingress" {
  description = "Create an AWS ALB Ingress to expose Jaeger UI publicly"
  type        = bool
  default     = false
}

variable "jaeger_ingress_host" {
  description = "Public hostname for Jaeger UI — e.g. jaeger.test.intangles.com"
  type        = string
  default     = ""
}

variable "jaeger_ingress_class" {
  description = "Kubernetes IngressClass name used by aws-load-balancer-controller (usually 'alb')"
  type        = string
  default     = "alb"
}

variable "data_retention_days" {
  description = "Number of days to retain trace data"
  type        = number
  default     = 7
}

variable "custom_ilm_policies" {
  description = "Map of index prefix to retention days for custom ILM policies. Example: { \"jaeger-span\" = 14, \"application-logs\" = 30 }"
  type        = map(number)
  default     = {}
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Common annotations to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector for pod scheduling"
  type        = map(string)
  default = {
    telemetry = "true"
  }
}

variable "tolerations" {
  description = "Tolerations for pod scheduling"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = [
    {
      key      = "telemetry"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }
  ]
}

# ---------------------------------------------------------------------------
# Kibana
# ---------------------------------------------------------------------------
variable "kibana_enabled" {
  description = "Deploy Kibana — requires elasticsearch_enabled = true"
  type        = bool
  default     = false
}

variable "kibana_chart_version" {
  description = "Kibana Helm chart version — must match Elasticsearch version"
  type        = string
  default     = "8.5.1"
}

variable "kibana_replicas" {
  description = "Number of Kibana replicas (>=2 for production HA)"
  type        = number
  default     = 2
}

variable "kibana_storage_size" {
  description = "Size of the Kibana saved-objects PVC"
  type        = string
  default     = "5Gi"
}

variable "kibana_storage_class" {
  description = "Storage class for Kibana PVC — empty string uses cluster default"
  type        = string
  default     = ""
}

variable "kibana_log_level" {
  description = "Kibana log level: warn for production, info for staging/dev"
  type        = string
  default     = "warn"
}

variable "kibana_resources" {
  description = "Resource requests and limits for Kibana"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "1000m"
      memory = "2Gi"
    }
  }
}

variable "kibana_create_ingress" {
  description = "Create an AWS ALB Ingress for Kibana"
  type        = bool
  default     = false
}

variable "kibana_ingress_host" {
  description = "Public hostname for Kibana — e.g. kibana.test.intangles.com"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Shared secrets — set via TF_VAR_* env vars, NEVER in tfvars files
# ---------------------------------------------------------------------------
variable "elastic_password" {
  description = "Elasticsearch 'elastic' superuser password. Use TF_VAR_elastic_password env var."
  type        = string
  sensitive   = true
  default     = ""
}

variable "kibana_encryption_key" {
  description = "32-character encryption key for Kibana saved objects. Use TF_VAR_kibana_encryption_key env var."
  type        = string
  sensitive   = true
  default     = ""
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for ALB HTTPS termination. Set per environment in tfvars — this is not a secret."
  type        = string
  default     = ""
}

variable "alb_group_name" {
  description = "ALB IngressGroup name (alb.ingress.kubernetes.io/group.name). Set to your existing group to share the ALB instead of creating a new one."
  type        = string
  default     = ""
}

variable "kibana_ingress_class" {
  description = "Kubernetes IngressClass name used by aws-load-balancer-controller (usually 'alb')"
  type        = string
  default     = "alb"
}

# ---------------------------------------------------------------------------
# Prometheus / Grafana Ingress
# ---------------------------------------------------------------------------
variable "prometheus_create_ingress" {
  description = "Create an AWS ALB Ingress to expose Prometheus publicly"
  type        = bool
  default     = false
}

variable "prometheus_ingress_host" {
  description = "Public hostname for Prometheus — e.g. prometheus.test.intangles.com"
  type        = string
  default     = ""
}

variable "grafana_create_ingress" {
  description = "Create an AWS ALB Ingress to expose Grafana publicly"
  type        = bool
  default     = false
}

variable "grafana_ingress_host" {
  description = "Public hostname for Grafana — e.g. grafana.test.intangles.com"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# OTel Agent Ingress
# ---------------------------------------------------------------------------
variable "otel_create_ingress" {
  description = "Create an AWS ALB Ingress to expose OTel Agent OTLP HTTP (4318) for external developer access"
  type        = bool
  default     = false
}

variable "otel_ingress_host" {
  description = "Public hostname for OTel OTLP endpoint — e.g. otel.test.intangles.com"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# VictoriaMetrics
# ---------------------------------------------------------------------------
variable "victoria_metrics_enabled" {
  description = "Deploy the VictoriaMetrics HA cluster (VMCluster + Operator)"
  type        = bool
  default     = false
}

variable "vm_operator_chart_version" {
  description = "victoria-metrics-operator Helm chart version"
  type        = string
  default     = "0.59.1"
}

variable "vm_cluster_name" {
  description = "Name of the VMCluster custom resource"
  type        = string
  default     = "vmcluster"
}

variable "vmstorage_replicas" {
  description = "Number of vmstorage pods (StatefulSet). Must be >= 3 for HA."
  type        = number
  default     = 3
}

variable "vminsert_replicas" {
  description = "Number of vminsert pods (Deployment). Must be >= 2 for HA."
  type        = number
  default     = 3
}

variable "vmselect_replicas" {
  description = "Number of vmselect pods (Deployment). Must be >= 2 for HA."
  type        = number
  default     = 3
}

variable "vm_replication_factor" {
  description = "VMCluster replication factor — how many vmstorage nodes each write is replicated across"
  type        = number
  default     = 2
}

variable "vm_retention_period" {
  description = "Data retention period for VictoriaMetrics (e.g. '7d', '30d', '1y')"
  type        = string
  default     = "7d"
}

variable "vmstorage_storage_size" {
  description = "PVC size for each vmstorage pod (EBS gp3)"
  type        = string
  default     = "100Gi"
}

variable "vm_storage_class_name" {
  description = "StorageClass name for vmstorage PVCs"
  type        = string
  default     = "vm-storage-gp3"
}

variable "vm_create_storage_class" {
  description = "Create the EBS gp3 StorageClass for vmstorage"
  type        = bool
  default     = true
}

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

variable "vmauth_enabled" {
  description = "Deploy VMAuth proxy in front of vminsert/vmselect for basic authentication"
  type        = bool
  default     = false
}

variable "vmauth_password" {
  description = "Password for VMAuth default user (sensitive)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vmagent_enabled" {
  description = "Deploy VMAgent to scrape Kubernetes cluster metrics"
  type        = bool
  default     = true
}

variable "vmalert_enabled" {
  description = "Deploy VMAlert to evaluate alerting and recording rules"
  type        = bool
  default     = false
}

variable "alertmanager_url" {
  description = "Alertmanager URL to send alerts to (used by VMAlert)"
  type        = string
  default     = ""
}

variable "vm_create_ingress" {
  description = "Create an ALB Ingress for the vmselect UI / query API"
  type        = bool
  default     = false
}

variable "vmselect_ingress_host" {
  description = "Public hostname for vmselect UI — e.g. vm.test.intangles.com"
  type        = string
  default     = ""
}

variable "vm_ingress_class_name" {
  description = "Ingress class name for VictoriaMetrics ingress (alb)"
  type        = string
  default     = "alb"
}

variable "vm_backup_enabled" {
  description = "Enable scheduled vmstorage backups to S3"
  type        = bool
  default     = false
}

variable "vm_backup_schedule" {
  description = "Cron expression for backup schedule"
  type        = string
  default     = "0 2 * * *"
}

variable "vm_backup_s3_bucket_name" {
  description = "S3 bucket name for backups. Leave empty to auto-generate 'vm-backup-<environment>'"
  type        = string
  default     = ""
}

variable "vm_backup_s3_region" {
  description = "AWS region for backup S3 bucket"
  type        = string
  default     = "ap-south-1"
}

variable "vm_backup_retention_days" {
  description = "Days to keep backup objects in S3 before expiry"
  type        = number
  default     = 30
}

variable "eks_oidc_provider_arn" {
  description = "OIDC provider ARN for EKS cluster (used for IRSA on vmbackup service account)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Prometheus Operator namespace isolation
# ---------------------------------------------------------------------------
variable "kube_prometheus_operator_watch_namespaces" {
  description = "Namespaces the Prometheus Operator will watch for CRDs (ServiceMonitor, PrometheusRule, etc.). Set to a non-empty list to restrict namespace scope — required when a second Prometheus Operator already exists in the cluster watching a different namespace set (e.g. 'observability'). Leave empty ([]) to watch all namespaces."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Dash0
# ---------------------------------------------------------------------------
variable "dash0_auth_token" {
  description = "Dash0 API auth token (Bearer). Use TF_VAR_dash0_auth_token env var."
  type        = string
  sensitive   = true
  default     = ""
}
# MongoDB Exporter Scraping
# ---------------------------------------------------------------------------
variable "mongodb_scrape_enabled" {
  description = "Enable VMServiceScrape to scrape the bitnami-mongodb-exporter sidecar via VMAgent"
  type        = bool
  default     = false
}

variable "mongodb_exporter_namespace" {
  description = "Namespace where the mongodb-exporter Service is running (e.g. atomsphere-kl-111)"
  type        = string
  default     = ""
}

variable "mongodb_exporter_service_labels" {
  description = "matchLabels selector to identify the mongodb-exporter Kubernetes Service"
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
  description = "Namespace to restrict postgres scraping to. Leave empty (\"\") to scrape across ALL namespaces."
  type        = string
  default     = ""
}

variable "postgres_exporter_label_key" {
  description = "Label key present on ALL postgres-exporter Services. VMServiceScrape uses matchExpressions/Exists so every cluster is discovered regardless of label value."
  type        = string
  default     = "pg-exporter-service"
}

variable "postgres_exporter_port" {
  description = "Container port number on the postgres-exporter that exposes /metrics (default: 9187)"
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
  description = "Namespace to restrict ScyllaDB scraping to. Leave empty (\"\") to scrape across ALL namespaces."
  type        = string
  default     = ""
}

variable "scylladb_exporter_service_labels" {
  description = "matchLabels selector to identify ScyllaDB Services that expose the native Prometheus endpoint."
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
  description = "Namespace to restrict Redis scraping to. Leave empty (\"\") to scrape across ALL namespaces."
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
