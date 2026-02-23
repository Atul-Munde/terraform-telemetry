# kube-prometheus-stack Module Variables

variable "namespace" {
  description = "Kubernetes namespace for kube-prometheus-stack"
  type        = string
  default     = "telemetry"
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "kube-prometheus-stack"
}

variable "chart_version" {
  description = "Helm chart version"
  type        = string
  default     = "81.6.2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Node Scheduling
variable "node_selector_key" {
  description = "Node selector label key"
  type        = string
  default     = "telemetry"
}

variable "node_selector_value" {
  description = "Node selector label value"
  type        = string
  default     = "true"
}

# Storage Configuration
variable "storage_provisioner" {
  description = "Storage provisioner for storage classes"
  type        = string
  default     = "ebs.csi.aws.com"
}

variable "create_storage_classes" {
  description = "Create storage classes"
  type        = bool
  default     = true
}

# Prometheus Configuration
variable "prometheus_replicas" {
  description = "Number of Prometheus replicas"
  type        = number
  default     = 2
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "15d"
}

variable "prometheus_storage" {
  description = "Storage size for Prometheus"
  type        = string
  default     = "50Gi"
}

variable "prometheus_storage_class" {
  description = "Storage class name for Prometheus"
  type        = string
  default     = "obs-kube-prometheus"
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
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "4Gi"
    }
  }
}

# Alertmanager Configuration
variable "alertmanager_replicas" {
  description = "Number of Alertmanager replicas"
  type        = number
  default     = 2
}

variable "alertmanager_storage" {
  description = "Storage size for Alertmanager"
  type        = string
  default     = "10Gi"
}

variable "alertmanager_storage_class" {
  description = "Storage class name for Alertmanager"
  type        = string
  default     = "obs-kube-alertmanager"
}

variable "alertmanager_resources" {
  description = "Alertmanager resource requests and limits"
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
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

# Grafana Configuration
variable "grafana_replicas" {
  description = "Number of Grafana replicas"
  type        = number
  default     = 1
}

variable "grafana_storage" {
  description = "Storage size for Grafana"
  type        = string
  default     = "10Gi"
}

variable "grafana_storage_class" {
  description = "Storage class name for Grafana"
  type        = string
  default     = "obs-kube-grafana"
}

variable "grafana_resources" {
  description = "Grafana resource requests and limits"
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
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

# Node Exporter Configuration
variable "node_exporter_port" {
  description = "Port for node-exporter to expose metrics (change if default 9100 conflicts with existing installation)"
  type        = number
  default     = 9101
}

# Feature Flags
variable "default_rules_enabled" {
  description = "Enable default alerting rules"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Common labels to apply to resources"
  type        = map(string)
  default     = {}
}
