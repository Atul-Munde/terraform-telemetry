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

variable "otel_collector_replicas" {
  description = "Number of OTel Collector replicas"
  type        = number
  default     = 2
}

variable "otel_collector_image" {
  description = "OTel Collector container image"
  type        = string
  default     = "otel/opentelemetry-collector-contrib"
}

variable "otel_collector_version" {
  description = "OTel Collector version"
  type        = string
  default     = "0.95.0"
}

variable "otel_collector_resources" {
  description = "Resource requests and limits for OTel Collector"
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
      cpu    = "200m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "1Gi"
    }
  }
}

variable "otel_collector_hpa_enabled" {
  description = "Enable HPA for OTel Collector"
  type        = bool
  default     = true
}

variable "otel_collector_hpa_min_replicas" {
  description = "Minimum replicas for OTel Collector HPA"
  type        = number
  default     = 2
}

variable "otel_collector_hpa_max_replicas" {
  description = "Maximum replicas for OTel Collector HPA"
  type        = number
  default     = 10
}

variable "otel_collector_hpa_cpu_threshold" {
  description = "CPU threshold percentage for HPA"
  type        = number
  default     = 70
}

variable "otel_collector_hpa_memory_threshold" {
  description = "Memory threshold percentage for HPA"
  type        = number
  default     = 80
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

variable "enable_sampling" {
  description = "Enable tail-based sampling in OTel Collector"
  type        = bool
  default     = false
}

variable "sampling_percentage" {
  description = "Percentage of traces to sample (if sampling enabled)"
  type        = number
  default     = 100
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
