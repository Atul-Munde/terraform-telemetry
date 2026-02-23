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

# Import root module
module "telemetry" {
  source = "../.."

  environment      = "production"
  namespace        = "telemetry"
  create_namespace = true

  # OTel Collector Configuration - Production Scale
  otel_collector_replicas = 3
  otel_collector_version  = "0.95.0"
  otel_collector_resources = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "4Gi"
    }
  }

  # HPA Configuration - Higher limits for production
  otel_collector_hpa_enabled          = true
  otel_collector_hpa_min_replicas     = 3
  otel_collector_hpa_max_replicas     = 15
  otel_collector_hpa_cpu_threshold    = 70
  otel_collector_hpa_memory_threshold = 80

  # Jaeger Configuration - Production HA
  jaeger_chart_version      = "2.0.0"
  jaeger_storage_type       = "elasticsearch"
  jaeger_query_replicas     = 3
  jaeger_collector_replicas = 3

  # Elasticsearch Configuration - Production HA
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

  # Data Retention - Longer for production
  data_retention_days = 14

  # Sampling - Enable for high-volume production
  enable_sampling     = true
  sampling_percentage = 50

  # Labels
  labels = {
    environment = "production"
    team        = "platform"
    criticality = "high"
  }
}

# Outputs
output "namespace" {
  value = module.telemetry.namespace
}

output "otel_collector_grpc_endpoint" {
  value = module.telemetry.otel_collector_grpc_endpoint
}

output "otel_collector_http_endpoint" {
  value = module.telemetry.otel_collector_http_endpoint
}

output "jaeger_ui_port_forward_command" {
  value = module.telemetry.jaeger_ui_port_forward_command
}

output "elasticsearch_endpoint" {
  value = module.telemetry.elasticsearch_endpoint
}
