variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "chart_version" {
  description = "Jaeger Helm chart version"
  type        = string
  default     = "2.0.0"
}

variable "storage_type" {
  description = "Storage backend type (elasticsearch, cassandra, badger)"
  type        = string
  default     = "elasticsearch"
  validation {
    condition     = contains(["elasticsearch", "cassandra", "badger"], var.storage_type)
    error_message = "Storage type must be elasticsearch, cassandra, or badger."
  }
}

variable "elasticsearch_host" {
  description = "Elasticsearch host"
  type        = string
  default     = ""
}

variable "elasticsearch_port" {
  description = "Elasticsearch port"
  type        = number
  default     = 9200
}

variable "query_replicas" {
  description = "Number of Jaeger Query replicas"
  type        = number
  default     = 2
}

variable "collector_replicas" {
  description = "Number of Jaeger Collector replicas"
  type        = number
  default     = 2
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

variable "elastic_password" {
  description = "Elasticsearch elastic user password — used for Jaeger ES storage auth"
  type        = string
  sensitive   = true
  default     = ""
}

variable "elastic_username" {
  description = "Elasticsearch username for Jaeger storage"
  type        = string
  default     = "elastic"
}

# ---------------------------------------------------------------------------
# ALB Ingress
# ---------------------------------------------------------------------------
variable "create_ingress" {
  description = "Create an AWS ALB Ingress to expose Jaeger UI publicly"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Fully-qualified hostname — e.g. jaeger.test.intangles.com"
  type        = string
  default     = ""
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for HTTPS termination"
  type        = string
  default     = ""
}

variable "ingress_class_name" {
  description = "Kubernetes IngressClass name (usually 'alb')"
  type        = string
  default     = "alb"
}

variable "alb_group_name" {
  description = "ALB IngressGroup name — share an existing ALB or leave empty for a dedicated one"
  type        = string
  default     = ""
}
