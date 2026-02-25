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
  elastic_password = var.elastic_password

  depends_on = [module.namespace]
}

# Deploy Kibana (if enabled — requires elasticsearch_enabled = true)
module "kibana" {
  source = "./modules/kibana"
  count  = var.kibana_enabled ? 1 : 0

  namespace             = module.namespace.name
  environment           = var.environment
  chart_version         = var.kibana_chart_version
  replicas              = var.kibana_replicas
  resources             = var.kibana_resources
  elasticsearch_host    = var.elasticsearch_enabled ? (
    var.elastic_password != ""
      ? "https://elasticsearch-master.${var.namespace}.svc:9200"
      : "http://elasticsearch-master.${var.namespace}.svc:9200"
  ) : ""
  elastic_password      = var.elastic_password
  kibana_encryption_key = var.kibana_encryption_key
  storage_class         = var.kibana_storage_class
  storage_size          = var.kibana_storage_size
  labels                = local.common_labels
  node_selector         = var.node_selector
  tolerations           = var.tolerations
  log_level             = var.kibana_log_level
  create_ingress        = var.kibana_create_ingress
  ingress_host          = var.kibana_ingress_host
  alb_certificate_arn   = var.alb_certificate_arn
  ingress_class_name    = var.kibana_ingress_class
  alb_group_name        = var.alb_group_name

  depends_on = [module.namespace, module.elasticsearch]
}

# Deploy Jaeger
module "jaeger" {
  source = "./modules/jaeger"

  namespace          = module.namespace.name
  environment        = var.environment
  chart_version      = var.jaeger_chart_version
  storage_type       = var.jaeger_storage_type
  query_replicas     = var.jaeger_query_replicas
  collector_replicas = var.jaeger_collector_replicas
  elasticsearch_host = var.elasticsearch_enabled ? "elasticsearch-master.${var.namespace}.svc.cluster.local" : ""
  elastic_password   = var.elastic_password
  node_selector      = var.node_selector
  tolerations        = var.tolerations

  depends_on = [module.namespace, module.elasticsearch]
}

# Deploy OpenTelemetry Operator + Agent + Gateway + Instrumentation
# Replaces the old single-Deployment otel-collector module.
module "otel_operator" {
  source = "./modules/otel-operator"
  count  = var.otel_operator_enabled ? 1 : 0

  namespace     = module.namespace.name
  environment   = var.environment
  app_namespace = var.app_namespace

  # Operator
  operator_chart_version = var.otel_operator_chart_version
  operator_replicas      = var.environment == "production" ? 2 : 1
  operator_image_tag     = var.otel_collector_image_tag

  # Agent (DaemonSet)
  agent_image_tag                   = var.otel_collector_image_tag
  agent_resources                   = var.otel_agent_resources
  agent_node_selector               = var.otel_agent_node_selector
  kubeletstats_insecure_skip_verify = var.kubeletstats_insecure_skip_verify

  # Gateway (StatefulSet)
  gateway_image_tag               = var.otel_collector_image_tag
  gateway_min_replicas            = var.gateway_min_replicas
  gateway_max_replicas            = var.gateway_max_replicas
  gateway_resources               = var.otel_gateway_resources
  tail_sampling_decision_wait     = var.tail_sampling_decision_wait
  tail_sampling_normal_percentage = var.tail_sampling_normal_percentage
  tail_sampling_slow_threshold_ms = var.tail_sampling_slow_threshold_ms
  tail_sampling_num_traces        = var.tail_sampling_num_traces

  # Backends
  jaeger_endpoint                  = "jaeger-collector.${var.namespace}.svc.cluster.local:4317"
  prometheus_remote_write_endpoint = "http://kube-prometheus-stack-prometheus.${var.namespace}.svc.cluster.local:9090/api/v1/write"

  # Infra metrics (opt-in)
  infra_metrics_enabled   = var.infra_metrics_enabled
  infra_metrics_resources = var.infra_metrics_resources
  mongodb_host            = var.mongodb_host
  mongodb_username        = var.mongodb_username
  mongodb_password        = var.mongodb_password
  rabbitmq_host           = var.rabbitmq_host
  rabbitmq_username       = var.rabbitmq_username
  rabbitmq_password       = var.rabbitmq_password
  redis_host              = var.redis_host
  postgresql_host         = var.postgresql_host
  postgresql_username     = var.postgresql_username
  postgresql_password     = var.postgresql_password

  # Instrumentation
  instrumentation_enabled      = var.instrumentation_enabled
  nodejs_instrumentation_image = var.nodejs_instrumentation_image
  enabled_instrumentations     = var.otel_enabled_instrumentations

  # Integration
  kube_prometheus_enabled = var.kube_prometheus_enabled
  node_selector           = var.node_selector
  tolerations             = var.tolerations
  labels                  = local.common_labels

  depends_on = [
    module.namespace,
    module.jaeger,
    module.elasticsearch,
  ]
}

# Deploy kube-prometheus-stack (if enabled)
module "kube_prometheus" {
  source = "./modules/kube-prometheus"
  count  = var.kube_prometheus_enabled ? 1 : 0

  namespace              = module.namespace.name
  environment            = var.environment
  create_storage_classes = var.kube_prometheus_create_storage_classes
  prometheus_resources   = var.prometheus_resources
  grafana_existing_claim = var.grafana_existing_claim

  depends_on = [module.namespace]
}
