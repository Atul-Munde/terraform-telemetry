# =============================================================
# Core
# =============================================================
variable "namespace" {
  description = "Kubernetes namespace for collectors, RBAC, and Instrumentation CRDs"
  type        = string
  default     = "telemetry"
}

variable "operator_namespace" {
  description = "Namespace for the Operator Helm release and controller pods (default matches Helm chart default)"
  type        = string
  default     = "opentelemetry-operator-system"
}

variable "environment" {
  description = "Environment name (dev/staging/production)"
  type        = string
}

variable "app_namespace" {
  description = "Application namespace where Instrumentation CRD is deployed and pods are auto-instrumented"
  type        = string
  default     = "telemetry"
}

# =============================================================
# Operator
# =============================================================
variable "operator_chart_version" {
  description = "OpenTelemetry Operator Helm chart version"
  type        = string
  default     = "0.66.0"
}

variable "operator_replicas" {
  description = "Number of Operator manager replicas (min 2 for HA)"
  type        = number
  default     = 2
}

variable "operator_image_tag" {
  description = "OTel Collector contrib image tag used by the Operator"
  type        = string
  default     = "0.105.0"  # matches chart 0.66.0 app_version; 'container' filelog operator requires this
}

variable "operator_resources" {
  description = "Resource requests/limits for the Operator manager"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

# =============================================================
# Agent (DaemonSet)
# =============================================================
variable "agent_image" {
  description = "OTel Collector contrib image for the Agent DaemonSet"
  type        = string
  default     = "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib"
}

variable "agent_image_tag" {
  description = "Image tag for the Agent collector"
  type        = string
  default     = "0.105.0"  # must match operator chart 0.66.0 bundled default; 'container' filelog operator requires >= 0.105.0
}

variable "agent_resources" {
  description = "Resource requests/limits for each Agent pod (per node)"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "250m", memory = "512Mi" }
  }
}

variable "agent_node_selector" {
  description = "Node selector for Agent DaemonSet (label nodes with otel-agent=true)"
  type        = map(string)
  default     = { "otel-agent" = "true" }
}

variable "kubeletstats_insecure_skip_verify" {
  description = "Skip TLS verification for kubeletstats receiver (EKS requires true)"
  type        = bool
  default     = true
}

# =============================================================
# Gateway (StatefulSet)
# =============================================================
variable "gateway_image" {
  description = "OTel Collector contrib image for the Gateway StatefulSet"
  type        = string
  default     = "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib"
}

variable "gateway_image_tag" {
  description = "Image tag for the Gateway collector"
  type        = string
  default     = "0.105.0"  # kept in sync with agent_image_tag
}

variable "gateway_min_replicas" {
  description = "Minimum Gateway replicas (HPA lower bound — must be >= 2 for HA)"
  type        = number
  default     = 2

  validation {
    condition     = var.gateway_min_replicas >= 2
    error_message = "gateway_min_replicas must be at least 2 for production HA."
  }
}

variable "gateway_max_replicas" {
  description = "Maximum Gateway replicas (HPA upper bound)"
  type        = number
  default     = 8
}

variable "gateway_resources" {
  description = "Resource requests/limits for each Gateway pod"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "500m", memory = "1Gi" }
    limits   = { cpu = "2", memory = "2Gi" }  # whole cores preferred; Kubernetes normalises "2000m" → "2"
  }
}

variable "tail_sampling_decision_wait" {
  description = "Seconds to wait before making a tail sampling decision (30s+ recommended for async queues)"
  type        = number
  default     = 30
}

variable "tail_sampling_normal_percentage" {
  description = "Percentage of non-error, non-slow traces to keep (tail sampling)"
  type        = number
  default     = 50
}

variable "tail_sampling_slow_threshold_ms" {
  description = "Latency threshold in ms above which traces are always kept"
  type        = number
  default     = 2000
}

variable "tail_sampling_num_traces" {
  description = "Max number of traces buffered in memory per Gateway pod"
  type        = number
  default     = 50000
}

# =============================================================
# Backends
# =============================================================
variable "jaeger_endpoint" {
  description = "Jaeger collector OTLP gRPC endpoint"
  type        = string
  default     = "jaeger-collector.telemetry.svc.cluster.local:4317"
}

variable "prometheus_remote_write_endpoint" {
  description = "Prometheus remote write endpoint"
  type        = string
  default     = "http://kube-prometheus-stack-prometheus.telemetry.svc.cluster.local:9090/api/v1/write"
}

# =============================================================
# Infra Metrics (optional)
# =============================================================
variable "infra_metrics_enabled" {
  description = "Deploy otel-infra-metrics collector for DB/queue scraping"
  type        = bool
  default     = false
}

variable "infra_metrics_resources" {
  description = "Resource requests/limits for the infra-metrics collector"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

# Infra credentials — sensitive, sourced from env vars or secrets manager
variable "mongodb_host" {
  description = "MongoDB service hostname"
  type        = string
  default     = ""
}

variable "mongodb_username" {
  description = "MongoDB monitoring user"
  type        = string
  default     = "mongo-mon-user"
}

variable "mongodb_password" {
  description = "MongoDB monitoring user password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rabbitmq_host" {
  description = "RabbitMQ service hostname"
  type        = string
  default     = ""
}

variable "rabbitmq_username" {
  description = "RabbitMQ monitoring user"
  type        = string
  default     = "appuser"
}

variable "rabbitmq_password" {
  description = "RabbitMQ monitoring user password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_host" {
  description = "Redis master service hostname"
  type        = string
  default     = ""
}

variable "postgresql_host" {
  description = "PostgreSQL service hostname"
  type        = string
  default     = ""
}

variable "postgresql_username" {
  description = "PostgreSQL monitoring user"
  type        = string
  default     = "postgres"
}

variable "postgresql_password" {
  description = "PostgreSQL monitoring user password"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================
# Instrumentation
# =============================================================
variable "instrumentation_enabled" {
  description = "Deploy the Instrumentation CRD for Node.js auto-instrumentation"
  type        = bool
  default     = true
}

variable "nodejs_instrumentation_image" {
  description = "Node.js auto-instrumentation init-container image"
  type        = string
  default     = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.69.0"
}

variable "enabled_instrumentations" {
  description = "Comma-separated list of Node.js instrumentations to enable"
  type        = string
  default     = "http,grpc,express,restify,mongodb,pg,redis,ioredis,amqplib,kafkajs,socket.io,dns,net"
}

# =============================================================
# kube-prometheus integration
# =============================================================
variable "kube_prometheus_enabled" {
  description = "Create ServiceMonitor for Prometheus to scrape Gateway metrics"
  type        = bool
  default     = true
}

# =============================================================
# Scheduling
# =============================================================
variable "node_selector" {
  description = "Node selector for Gateway and infra-metrics pods"
  type        = map(string)
  default     = { "telemetry" = "true" }
}

variable "tolerations" {
  description = "Tolerations for Gateway and infra-metrics pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}
