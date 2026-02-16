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

  # Import root module
module "telemetry" {
  source = "../.."

  environment                         = "staging"
  namespace                           = "telemetry"
  create_namespace                    = true

  # OTel Collector Configuration
  otel_collector_replicas             = 2
  otel_collector_version              = "0.95.0"
  otel_collector_resources = {
    requests = {
      cpu    = "300m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1500m"
      memory = "2Gi"
    }
  }

  # HPA Configuration
  otel_collector_hpa_enabled          = true
  otel_collector_hpa_min_replicas     = 2
  otel_collector_hpa_max_replicas     = 8
  otel_collector_hpa_cpu_threshold    = 70
  otel_collector_hpa_memory_threshold = 80

  # Jaeger Configuration
  jaeger_chart_version                = "2.0.0"
  jaeger_storage_type                 = "elasticsearch"
  jaeger_query_replicas               = 2
  jaeger_collector_replicas           = 2

  # Elasticsearch Configuration
  elasticsearch_enabled               = true
  elasticsearch_replicas              = 2
  elasticsearch_storage_size          = "75Gi"
  elasticsearch_storage_class         = "gp3"
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

  # Data Retention
  data_retention_days                 = 7

  # Sampling
  enable_sampling                     = false
  sampling_percentage                 = 100

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
