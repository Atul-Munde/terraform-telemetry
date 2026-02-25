variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "replicas" {
  description = "Number of Elasticsearch replicas"
  type        = number
  default     = 3
}

variable "storage_size" {
  description = "Storage size for each Elasticsearch node"
  type        = string
  default     = "100Gi"
}

variable "storage_class" {
  description = "Storage class for persistent volumes"
  type        = string
  default     = ""
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

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "retention_days" {
  description = "Number of days to retain indices"
  type        = number
  default     = 7
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
  description = "Password for the Elasticsearch 'elastic' superuser. Set via TF_VAR_elastic_password env var — never commit to tfvars."
  type        = string
  sensitive   = true
  default     = ""
}
