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

variable "data_retention_days" {
  description = "Number of days to retain trace data"
  type        = number
  default     = 7
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
