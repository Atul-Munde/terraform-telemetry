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
}

# Deploy Elasticsearch (if enabled)
module "elasticsearch" {
  source = "./modules/elasticsearch"
  count  = var.elasticsearch_enabled ? 1 : 0

  namespace      = module.namespace.name
  environment    = var.environment
  replicas       = var.elasticsearch_replicas
  storage_size   = var.elasticsearch_storage_size
  storage_class  = var.elasticsearch_storage_class
  resources      = var.elasticsearch_resources
  retention_days = var.data_retention_days
  node_selector  = var.node_selector
  tolerations    = var.tolerations

  depends_on = [module.namespace]
}

# Deploy Jaeger
module "jaeger" {
  source = "./modules/jaeger"

  namespace          = module.namespace.name
  environment        = var.environment
  elasticsearch_host = var.elasticsearch_enabled ? "elasticsearch-master.${var.namespace}.svc.cluster.local" : ""
  node_selector      = var.node_selector
  tolerations        = var.tolerations

  depends_on = [module.namespace, module.elasticsearch]
}

# Deploy OpenTelemetry Collector
module "otel_collector" {
  source = "./modules/otel-collector"

  namespace       = module.namespace.name
  environment     = var.environment
  jaeger_endpoint = "jaeger-collector.${var.namespace}.svc.cluster.local:4317"
  node_selector   = var.node_selector
  tolerations     = var.tolerations

  depends_on = [module.namespace, module.jaeger]
}

# Deploy kube-prometheus-stack (if enabled)
module "kube_prometheus" {
  source = "./modules/kube-prometheus"
  count  = var.kube_prometheus_enabled ? 1 : 0

  namespace              = module.namespace.name
  environment            = var.environment
  create_storage_classes = var.kube_prometheus_create_storage_classes
  prometheus_resources   = var.prometheus_resources

  depends_on = [module.namespace]
}
