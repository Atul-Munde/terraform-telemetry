# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------
variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "chart_version" {
  description = "Kibana Helm chart version — must match Elasticsearch chart version"
  type        = string
  default     = "8.5.1"
}

variable "labels" {
  description = "Common labels applied to all resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Replicas / HA
# ---------------------------------------------------------------------------
variable "replicas" {
  description = "Number of Kibana replicas (>=2 for HA)"
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------
variable "resources" {
  description = "Resource requests and limits for Kibana pods"
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

# ---------------------------------------------------------------------------
# Elasticsearch connectivity
# ---------------------------------------------------------------------------
variable "elasticsearch_host" {
  description = "Full Elasticsearch internal URL — e.g. http://elasticsearch-master.telemetry.svc.cluster.local:9200"
  type        = string
}

# ---------------------------------------------------------------------------
# Security — secrets (NEVER hardcoded, always TF_VAR_* env vars)
# ---------------------------------------------------------------------------
variable "elastic_password" {
  description = "Password for the Elasticsearch 'elastic' superuser"
  type        = string
  sensitive   = true
}

variable "kibana_encryption_key" {
  description = "32-character random key for xpack.encryptedSavedObjects.encryptionKey"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.kibana_encryption_key) >= 32
    error_message = "kibana_encryption_key must be at least 32 characters."
  }
}

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
variable "storage_class" {
  description = "Storage class for Kibana PVC — empty string uses cluster default"
  type        = string
  default     = ""
}

variable "storage_size" {
  description = "Size of the Kibana saved-objects PVC"
  type        = string
  default     = "5Gi"
}

# ---------------------------------------------------------------------------
# Scheduling
# ---------------------------------------------------------------------------
variable "node_selector" {
  description = "Node selector for Kibana pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Kibana pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Tuning
# ---------------------------------------------------------------------------
variable "log_level" {
  description = "Kibana log level: fatal | error | warn | info | debug | trace | all | off"
  type        = string
  default     = "warn"

  validation {
    condition     = contains(["fatal", "error", "warn", "info", "debug", "trace", "all", "off"], var.log_level)
    error_message = "log_level must be one of: fatal, error, warn, info, debug, trace, all, off."
  }
}

variable "base_path" {
  description = "Optional server.basePath (e.g. /kibana) — leave empty for root"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# ALB Ingress
# ---------------------------------------------------------------------------
variable "create_ingress" {
  description = "Create an AWS ALB Ingress to expose Kibana publicly"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Fully-qualified hostname — e.g. kibana.test.intangles.com"
  type        = string
  default     = ""
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for HTTPS termination — set per environment in tfvars (not a secret)"
  type        = string
  default     = ""
}

variable "ingress_class_name" {
  description = "Kubernetes IngressClass name — matches the IngressClass installed by aws-load-balancer-controller (usually 'alb')"
  type        = string
  default     = "alb"
}

variable "alb_group_name" {
  description = "ALB IngressGroup name (alb.ingress.kubernetes.io/group.name). When set, Ingress joins the existing shared ALB instead of provisioning a new one. Leave empty for a dedicated ALB."
  type        = string
  default     = ""
}
