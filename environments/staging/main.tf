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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }

  }

  backend "s3" {
    bucket         = "otel-terraform-state-setup"
    key            = "k8s-otel-jaeger/staging/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    profile        = "mum-test"
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
  region  = "ap-south-1"
  profile = "mum-test"
}

provider "kubectl" {
  config_path = "~/.kube/config"
}

# ---------------------------------------------------------------------------
# Secret variables — must be supplied via TF_VAR_* env vars
# ---------------------------------------------------------------------------
variable "elastic_password" {
  description = "Elasticsearch elastic user password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kibana_encryption_key" {
  description = "Kibana encryption key (minimum 32 characters)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "dash0_auth_token" {
  description = "Dash0 API auth token (Bearer). Use TF_VAR_dash0_auth_token env var."
  type        = string
  sensitive   = true
  default     = ""
}

# Import root module
module "telemetry" {
  source = "../.."

  environment      = "staging"
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

  # OTel Gateway (StatefulSet)
  gateway_min_replicas = 2
  gateway_max_replicas = 5
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

  # Tail sampling
  tail_sampling_decision_wait     = 30
  tail_sampling_normal_percentage = 50
  tail_sampling_slow_threshold_ms = 2000
  tail_sampling_num_traces        = 50000

  # Infra metrics — disabled in staging
  infra_metrics_enabled = false

  # Auto-instrumentation
  instrumentation_enabled      = true
  nodejs_instrumentation_image = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.69.0"

  # OTel Agent public ingress (OTLP HTTP for developer local testing)
  otel_create_ingress = true
  otel_ingress_host   = "otel.test.intangles.com"

  # ---------------------------------------------------------------------------
  # Jaeger Configuration
  # ---------------------------------------------------------------------------
  jaeger_chart_version      = "2.0.0"
  jaeger_storage_type       = "elasticsearch"
  jaeger_query_replicas     = 2
  jaeger_collector_replicas = 2
  jaeger_create_ingress     = true
  jaeger_ingress_host       = "jaeger.test.intangles.com"
  jaeger_ingress_class      = "alb"

  # ---------------------------------------------------------------------------
  # Elasticsearch Configuration
  # ---------------------------------------------------------------------------
  elasticsearch_enabled       = true
  elasticsearch_replicas      = 2
  elasticsearch_storage_size  = "75Gi"
  elasticsearch_storage_class = "gp3"
  custom_ilm_policies = {
    "jaeger-span"    = 5
    "jaeger-service" = 9
  }
  elasticsearch_resources = {
    requests = {
      cpu    = "1000m"
      memory = "2Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "4Gi"
    }
  }

  # ---------------------------------------------------------------------------
  # Kibana Configuration
  # ---------------------------------------------------------------------------
  kibana_enabled         = true
  kibana_replicas        = 1
  kibana_chart_version   = "8.5.1"
  kibana_storage_size    = "5Gi"
  kibana_storage_class   = "gp3"
  kibana_log_level       = "info"
  kibana_create_ingress  = true
  kibana_ingress_host    = "kibana.test.intangles.com"
  kibana_ingress_class   = "alb"
  alb_group_name         = "intangles-ingress"
  alb_certificate_arn    = "arn:aws:acm:ap-south-1:294202164463:certificate/6aaf4f38-c00f-4ad2-bf41-ae4ab88123a0"
  kibana_resources = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "1000m"
      memory = "2Gi"
    }
  }

  # ---------------------------------------------------------------------------
  # kube-prometheus Configuration
  # ---------------------------------------------------------------------------
  kube_prometheus_enabled                = true
  kube_prometheus_create_storage_classes = true
  grafana_existing_claim                 = "kube-prometheus-stack-grafana"
  prometheus_resources = {
    requests = {
      cpu    = "2000m"
      memory = "6Gi"
    }
    limits = {
      cpu    = "4000m"
      memory = "12Gi"
    }
  }

  # Prometheus & Grafana public ingress
  prometheus_create_ingress = true
  prometheus_ingress_host   = "prometheus.test.intangles.com"
  grafana_create_ingress    = true
  grafana_ingress_host      = "grafana.test.intangles.com"

  # Data Retention
  data_retention_days = 7

  # Node Placement
  node_selector = {
    telemetry = "true"
  }
  tolerations = []

  # Labels
  labels = {
    environment = "staging"
    team        = "platform"
  }

  # Secret credentials — passed from TF_VAR_* env vars (X-Pack security enabled)
  elastic_password      = var.elastic_password
  kibana_encryption_key = var.kibana_encryption_key
  dash0_auth_token      = var.dash0_auth_token

  # ---------------------------------------------------------------------------
  # VictoriaMetrics — enabled in staging for validation
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
  vminsert_max_replicas = 6
  vmselect_min_replicas = 3
  vmselect_max_replicas = 6

  vmagent_enabled  = true
  vmalert_enabled  = true
  alertmanager_url = "http://kube-prometheus-stack-alertmanager.telemetry.svc.cluster.local:9093"
  vmauth_enabled   = false

  vm_create_ingress     = true
  vmselect_ingress_host = "vm.test.intangles.com"
  vm_ingress_class_name = "alb"

  vm_backup_enabled = false

  # MongoDB Exporter Scraping
  mongodb_scrape_enabled          = true
  mongodb_exporter_namespace      = "atomsphere-kl-111"
  mongodb_exporter_service_labels = {
    "app.kubernetes.io/component" = "metrics"
    "app.kubernetes.io/instance"  = "intangles-mongo-gen-obs"
  }
  mongodb_exporter_port           = "http-metrics"
}

# Outputs
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

output "jaeger_url" {
  value = module.telemetry.jaeger_url
}

output "kibana_url" {
  value = module.telemetry.kibana_url
}

output "prometheus_url" {
  value = module.telemetry.prometheus_url
}

output "grafana_url" {
  value = module.telemetry.grafana_url
}

output "otel_public_otlp_url" {
  value = module.telemetry.otel_public_otlp_url
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
