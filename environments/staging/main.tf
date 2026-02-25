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

  # ---------------------------------------------------------------------------
  # Jaeger Configuration
  # ---------------------------------------------------------------------------
  jaeger_chart_version      = "2.0.0"
  jaeger_storage_type       = "elasticsearch"
  jaeger_query_replicas     = 2
  jaeger_collector_replicas = 2

  # ---------------------------------------------------------------------------
  # Elasticsearch Configuration
  # ---------------------------------------------------------------------------
  elasticsearch_enabled       = true
  elasticsearch_replicas      = 2
  elasticsearch_storage_size  = "75Gi"
  elasticsearch_storage_class = "gp3"
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

output "kibana_url" {
  value = module.telemetry.kibana_url
}
