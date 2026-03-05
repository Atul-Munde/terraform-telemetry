terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "otel-terraform-state-setup"
    key            = "k8s-otel-jaeger/production/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Import root module
module "telemetry" {
  source = "../.."

  environment      = "production"
  namespace        = "telemetry"
  create_namespace = true

  # ---------------------------------------------------------------------------
  # OTel Operator
  # ---------------------------------------------------------------------------
  otel_operator_enabled      = true
  otel_operator_chart_version = "0.66.0"
  otel_operator_replicas     = 2
  otel_collector_image_tag   = "0.105.0"  # matches operator chart 0.66.0 bundled default
  app_namespace              = "telemetry"

  # OTel Agent (DaemonSet)
  otel_agent_resources = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "250m"
      memory = "512Mi"
    }
  }
  otel_agent_node_selector = { "otel-agent" = "true" }

  # OTel Gateway (StatefulSet) — production: 3 min replicas
  gateway_min_replicas = 3
  gateway_max_replicas = 10
  otel_gateway_resources = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2"  # Kubernetes normalises "2000m" → "2"; use whole-core form directly
      memory = "2Gi"
    }
  }

  # Tail sampling — production keeps 50% of normal traces
  tail_sampling_decision_wait     = 30
  tail_sampling_normal_percentage = 50
  tail_sampling_slow_threshold_ms = 2000
  tail_sampling_num_traces        = 100000

  # ---------------------------------------------------------------------------
  # Infra metrics — enabled in production; credentials via TF_VAR_* env vars
  # ---------------------------------------------------------------------------
  infra_metrics_enabled = true
  infra_metrics_resources = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }

  mongodb_host     = var.mongodb_host
  mongodb_username = var.mongodb_username
  mongodb_password = var.mongodb_password

  rabbitmq_host     = var.rabbitmq_host
  rabbitmq_username = var.rabbitmq_username
  rabbitmq_password = var.rabbitmq_password

  redis_host = var.redis_host

  postgresql_host     = var.postgresql_host
  postgresql_username = var.postgresql_username
  postgresql_password = var.postgresql_password

  # ---------------------------------------------------------------------------
  # Auto-instrumentation
  # ---------------------------------------------------------------------------
  instrumentation_enabled      = true
  nodejs_instrumentation_image = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.69.0"

  # ---------------------------------------------------------------------------
  # Jaeger Configuration — Production HA
  # ---------------------------------------------------------------------------
  jaeger_chart_version      = "2.0.0"
  jaeger_storage_type       = "elasticsearch"
  jaeger_query_replicas     = 3
  jaeger_collector_replicas = 3

  # ---------------------------------------------------------------------------
  # Elasticsearch Configuration — Production HA
  # ---------------------------------------------------------------------------
  elasticsearch_enabled      = true
  elasticsearch_replicas     = 3
  elasticsearch_storage_size = "200Gi"
  elasticsearch_resources = {
    requests = {
      cpu    = "2000m"
      memory = "4Gi"
    }
    limits = {
      cpu    = "4000m"
      memory = "8Gi"
    }
  }

  # Data Retention — longer for production
  data_retention_days = 14

  # Labels
  labels = {
    environment = "production"
    team        = "platform"
    criticality = "high"
  }

  # ---------------------------------------------------------------------------
  # VictoriaMetrics — full HA production configuration
  # ---------------------------------------------------------------------------
  victoria_metrics_enabled = true

  vmstorage_replicas    = 3
  vminsert_replicas     = 3
  vmselect_replicas     = 3
  vm_replication_factor = 2
  vm_retention_period   = "7d"

  vmstorage_storage_size  = "100Gi"
  vm_storage_class_name   = "vm-storage-gp3"
  vm_create_storage_class = true

  vminsert_min_replicas = 3
  vminsert_max_replicas = 10
  vmselect_min_replicas = 3
  vmselect_max_replicas = 10

  vmagent_enabled  = true
  vmalert_enabled  = true
  alertmanager_url = var.alertmanager_url

  vmauth_enabled  = true
  vmauth_password = var.vmauth_password

  vm_create_ingress     = true
  vmselect_ingress_host = "vm.test.intangles.com"
  vm_ingress_class_name = "alb"

  vm_backup_enabled        = true
  vm_backup_schedule       = "0 2 * * *"
  vm_backup_s3_bucket_name = ""
  vm_backup_s3_region      = "ap-south-1"
  vm_backup_retention_days = 30
  eks_oidc_provider_arn    = var.eks_oidc_provider_arn
}

# ---------------------------------------------------------------------------
# Sensitive variable pass-through (sourced from TF_VAR_* or terraform.tfvars)
# ---------------------------------------------------------------------------
variable "mongodb_host"       { type = string; default = "" }
variable "mongodb_username"   { type = string; default = "" }
variable "mongodb_password"   { type = string; sensitive = true; default = "" }
variable "rabbitmq_host"      { type = string; default = "" }
variable "rabbitmq_username"  { type = string; default = "" }
variable "rabbitmq_password"  { type = string; sensitive = true; default = "" }
variable "redis_host"         { type = string; default = "" }
variable "postgresql_host"    { type = string; default = "" }
variable "postgresql_username" { type = string; default = "" }
variable "postgresql_password" { type = string; sensitive = true; default = "" }

variable "vmauth_password" {
  description = "VMAuth default user password (sensitive)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "alertmanager_url" {
  description = "Alertmanager URL for VMAlert to send alerts to"
  type        = string
  default     = ""
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN for vmbackup IRSA"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "namespace" {
  value = module.telemetry.namespace
}

output "otel_agent_grpc_endpoint" {
  value = module.telemetry.otel_agent_grpc_endpoint
}

output "otel_agent_http_endpoint" {
  value = module.telemetry.otel_agent_http_endpoint
}

output "instrumentation_annotation_command" {
  value = module.telemetry.instrumentation_annotation_command
}

output "jaeger_ui_port_forward_command" {
  value = module.telemetry.jaeger_ui_port_forward_command
}

output "elasticsearch_endpoint" {
  value = module.telemetry.elasticsearch_endpoint
}

output "vm_prometheus_remote_write_url" {
  value = module.telemetry.vm_prometheus_remote_write_url
}

output "vm_grafana_datasource_url" {
  value = module.telemetry.vm_grafana_datasource_url
}

output "vm_ui_url" {
  value = module.telemetry.vm_ui_url
}

output "vm_backup_s3_bucket" {
  value = module.telemetry.vm_backup_s3_bucket
}
