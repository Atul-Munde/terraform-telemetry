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
    key            = "k8s-otel-jaeger/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

variable "aws_region" {
  description = "AWS region used by providers and forwarded to the root module"
  type        = string
  default     = "ap-south-1"
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
  region = var.aws_region
}

# Import root module
module "telemetry" {
  source = "../.."

  aws_region       = var.aws_region
  environment      = "dev"
  namespace        = "telemetry"
  create_namespace = true

  # ---------------------------------------------------------------------------
  # OTel Operator
  # ---------------------------------------------------------------------------
  otel_operator_enabled      = true
  otel_operator_chart_version = "0.66.0"
  otel_operator_replicas     = 1  # single replica acceptable in dev
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

  # Tail sampling — keep ALL traces in dev for easy debugging
  tail_sampling_decision_wait     = 30
  tail_sampling_normal_percentage = 100
  tail_sampling_slow_threshold_ms = 2000
  tail_sampling_num_traces        = 10000

  # Infra metrics — disabled in dev
  infra_metrics_enabled = false

  # Auto-instrumentation
  instrumentation_enabled       = true
  nodejs_instrumentation_image  = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.69.0"

  # ---------------------------------------------------------------------------
  # Jaeger Configuration
  # ---------------------------------------------------------------------------
  jaeger_chart_version      = "2.0.0"
  jaeger_storage_type       = "elasticsearch"
  jaeger_query_replicas     = 1
  jaeger_collector_replicas = 1

  # ---------------------------------------------------------------------------
  # Elasticsearch Configuration
  # ---------------------------------------------------------------------------
  elasticsearch_enabled      = true
  elasticsearch_replicas     = 1
  elasticsearch_storage_size = "30Gi"
  elasticsearch_resources = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "1000m"
      memory = "2Gi"
    }
  }

  # Data Retention
  data_retention_days = 3

  # Labels
  labels = {
    environment = "dev"
    team        = "platform"
  }

  # ---------------------------------------------------------------------------
  # VictoriaMetrics — disabled in dev
  # ---------------------------------------------------------------------------
  victoria_metrics_enabled = false
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
