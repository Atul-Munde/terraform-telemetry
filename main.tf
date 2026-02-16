# Provider Configuration
provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# Local variables
locals {
  common_labels = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      project     = "telemetry"
    },
    var.labels
  )
}

# Create Namespace
module "namespace" {
  source = "./modules/namespace"

  namespace        = var.namespace
  create_namespace = var.create_namespace
  labels           = local.common_labels
  annotations      = var.annotations
}

# Deploy Elasticsearch (if enabled)
module "elasticsearch" {
  source = "./modules/elasticsearch"
  count  = var.elasticsearch_enabled ? 1 : 0

  namespace       = module.namespace.name
  environment     = var.environment
  replicas        = var.elasticsearch_replicas
  storage_size    = var.elasticsearch_storage_size
  storage_class   = var.elasticsearch_storage_class
  resources       = var.elasticsearch_resources
  labels          = local.common_labels
  retention_days  = var.data_retention_days
  node_selector   = var.node_selector
  tolerations     = var.tolerations

  depends_on = [module.namespace]
}

# Deploy Jaeger
module "jaeger" {
  source = "./modules/jaeger"

  namespace                = module.namespace.name
  environment              = var.environment
  chart_version            = var.jaeger_chart_version
  storage_type             = var.jaeger_storage_type
  elasticsearch_host       = var.elasticsearch_enabled ? "elasticsearch-master.${var.namespace}.svc.cluster.local" : ""
  elasticsearch_port       = 9200
  query_replicas           = var.jaeger_query_replicas
  collector_replicas       = var.jaeger_collector_replicas
  labels                   = local.common_labels

  depends_on = [
    module.namespace,
    module.elasticsearch
  ]
}

# Deploy OpenTelemetry Collector
module "otel_collector" {
  source = "./modules/otel-collector"

  namespace                = module.namespace.name
  environment              = var.environment
  replicas                 = var.otel_collector_replicas
  image                    = var.otel_collector_image
  image_version            = var.otel_collector_version
  resources                = var.otel_collector_resources
  hpa_enabled              = var.otel_collector_hpa_enabled
  hpa_min_replicas         = var.otel_collector_hpa_min_replicas
  hpa_max_replicas         = var.otel_collector_hpa_max_replicas
  hpa_cpu_threshold        = var.otel_collector_hpa_cpu_threshold
  hpa_memory_threshold     = var.otel_collector_hpa_memory_threshold
  jaeger_endpoint          = "jaeger-collector.${var.namespace}.svc.cluster.local:4317"
  enable_sampling          = var.enable_sampling
  sampling_percentage      = var.sampling_percentage
  labels                   = local.common_labels
  node_selector            = var.node_selector
  tolerations              = var.tolerations

  depends_on = [
    module.namespace,
    module.jaeger
  ]
}
