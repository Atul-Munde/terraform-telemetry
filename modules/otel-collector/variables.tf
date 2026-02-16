variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "replicas" {
  description = "Number of replicas"
  type        = number
  default     = 2
}

variable "image" {
  description = "Container image"
  type        = string
  default     = "otel/opentelemetry-collector-contrib"
}

variable "image_version" {
  description = "Image version"
  type        = string
  default     = "0.95.0"
}

variable "resources" {
  description = "Resource requests and limits"
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
}

variable "hpa_enabled" {
  description = "Enable Horizontal Pod Autoscaler"
  type        = bool
  default     = true
}

variable "hpa_min_replicas" {
  description = "Minimum replicas for HPA"
  type        = number
  default     = 2
}

variable "hpa_max_replicas" {
  description = "Maximum replicas for HPA"
  type        = number
  default     = 10
}

variable "hpa_cpu_threshold" {
  description = "CPU threshold percentage for HPA"
  type        = number
  default     = 70
}

variable "hpa_memory_threshold" {
  description = "Memory threshold percentage for HPA"
  type        = number
  default     = 80
}

variable "jaeger_endpoint" {
  description = "Jaeger collector endpoint"
  type        = string
}

variable "enable_sampling" {
  description = "Enable tail-based sampling"
  type        = bool
  default     = false
}

variable "sampling_percentage" {
  description = "Sampling percentage"
  type        = number
  default     = 100
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector for pod scheduling"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for pod scheduling"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}
