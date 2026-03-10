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

# ---------------------------------------------------------------------------
# Prometheus Configuration — DISABLED
# Prometheus is replaced by VictoriaMetrics. These variables are retained
# so that the templatefile() call in main.tf continues to compile and
# can be re-enabled without structural changes.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Alertmanager Configuration — ACTIVE (deployed via kube-prometheus-stack)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Grafana Configuration — ACTIVE (deployed via kube-prometheus-stack)
# ---------------------------------------------------------------------------
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

variable "grafana_existing_claim" {
  description = "Name of an existing PVC to use for Grafana. Set on re-deploys to avoid Helm trying to patch the immutable volumeName field on a bound PVC. Leave empty on fresh installs."
  type        = string
  default     = ""
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

# ---------------------------------------------------------------------------
# Node Exporter Configuration — ACTIVE
# node-exporter is kept enabled even without Prometheus.
# VMAgent auto-discovers its ServiceMonitor and scrapes node metrics
# (CPU/memory/disk/network) which flow directly into VictoriaMetrics.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Ingress — Prometheus
# ---------------------------------------------------------------------------
variable "create_ingress_prometheus" {
  description = "Create an AWS ALB Ingress to expose Prometheus publicly"
  type        = bool
  default     = false
}

variable "prometheus_ingress_host" {
  description = "Public hostname for Prometheus — e.g. prometheus.test.intangles.com"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Ingress — Grafana
# ---------------------------------------------------------------------------
variable "create_ingress_grafana" {
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
# Shared ALB settings (used by both ingresses)
# ---------------------------------------------------------------------------
variable "alb_certificate_arn" {
  description = "ACM certificate ARN for ALB HTTPS termination"
  type        = string
  default     = ""
}

variable "ingress_class_name" {
  description = "Kubernetes IngressClass name used by aws-load-balancer-controller (usually 'alb')"
  type        = string
  default     = "alb"
}

variable "alb_group_name" {
  description = "ALB IngressGroup name — share the ALB across services"
  type        = string
  default     = "intangles-ingress"
}

variable "vm_grafana_datasource_url" {
  description = "VictoriaMetrics vmselect URL to provision as a Grafana datasource (Prometheus-compatible). e.g. http://vmselect-vmcluster.<namespace>.svc.cluster.local:8481/select/0/prometheus"
  type        = string
  default     = ""
}

variable "jaeger_grafana_datasource_url" {
  description = "Jaeger query URL to provision as a Grafana datasource. e.g. http://jaeger-query.<namespace>:16686"
  type        = string
  default     = ""
}
