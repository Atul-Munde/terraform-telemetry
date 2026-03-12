variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# ---------------------------------------------------------------------------
# Cluster identity
# ---------------------------------------------------------------------------
variable "cluster_name" {
  description = "Elasticsearch cluster name — used as clusterName in Helm values and service DNS prefix"
  type        = string
  default     = "elasticsearch"
}

# ---------------------------------------------------------------------------
# Node roles — per-role replica count, resources, and storage
# ---------------------------------------------------------------------------
variable "node_roles" {
  description = "Configuration for each Elasticsearch node role (master, data, coordinating)"
  type = object({
    master = object({
      replicas     = number
      storage_size = string
      resources = object({
        requests = object({
          cpu    = string
          memory = string
        })
        limits = object({
          cpu    = string
          memory = string
        })
      })
    })
    data = object({
      replicas     = number
      storage_size = string
      resources = object({
        requests = object({
          cpu    = string
          memory = string
        })
        limits = object({
          cpu    = string
          memory = string
        })
      })
    })
    coordinating = object({
      replicas = number
      resources = object({
        requests = object({
          cpu    = string
          memory = string
        })
        limits = object({
          cpu    = string
          memory = string
        })
      })
    })
  })
  default = {
    master = {
      replicas     = 3
      storage_size = "10Gi"
      resources = {
        requests = { cpu = "500m",  memory = "1Gi" }
        limits   = { cpu = "1000m", memory = "2Gi" }
      }
    }
    data = {
      replicas     = 2
      storage_size = "100Gi"
      resources = {
        requests = { cpu = "1000m", memory = "2Gi" }
        limits   = { cpu = "2000m", memory = "4Gi" }
      }
    }
    coordinating = {
      replicas = 2
      resources = {
        requests = { cpu = "500m",  memory = "1Gi" }
        limits   = { cpu = "1000m", memory = "2Gi" }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Anti-affinity
# ---------------------------------------------------------------------------
variable "anti_affinity" {
  description = "Anti-affinity type for master and data nodes: 'hard' (requiredDuring) or 'soft' (preferredDuring)"
  type        = string
  default     = "hard"

  validation {
    condition     = contains(["hard", "soft"], var.anti_affinity)
    error_message = "anti_affinity must be 'hard' or 'soft'."
  }
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------
variable "storage_class" {
  description = "Storage class for persistent volumes"
  type        = string
  default     = ""
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

# ---------------------------------------------------------------------------
# ILM (Index Lifecycle Management)
# ---------------------------------------------------------------------------
variable "custom_ilm_policies" {
  description = "Map of index prefix to retention days for custom ILM policies. Example: { \"jaeger-span\" = 14, \"application-logs\" = 30 }"
  type        = map(number)
  default     = {}
}
