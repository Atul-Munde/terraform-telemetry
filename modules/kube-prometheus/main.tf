# kube-prometheus-stack Module
# Deploys Prometheus, Alertmanager, Grafana, and related components

locals {
  name = "kube-prometheus"
}

# Storage Classes
resource "kubernetes_storage_class_v1" "prometheus" {
  count = var.create_storage_classes ? 1 : 0

  metadata {
    name = var.prometheus_storage_class
  }
  storage_provisioner = var.storage_provisioner
  parameters = {
    type   = "gp3"
    fsType = "xfs"
  }
  reclaim_policy         = "Retain"
  allow_volume_expansion = true

  lifecycle {
    ignore_changes = [parameters]
  }
}

resource "kubernetes_storage_class_v1" "alertmanager" {
  count = var.create_storage_classes ? 1 : 0

  metadata {
    name = var.alertmanager_storage_class
  }
  storage_provisioner = var.storage_provisioner
  parameters = {
    type   = "gp3"
    fsType = "xfs"
  }
  reclaim_policy         = "Retain"
  allow_volume_expansion = true

  lifecycle {
    ignore_changes = [parameters]
  }
}

resource "kubernetes_storage_class_v1" "grafana" {
  count = var.create_storage_classes ? 1 : 0

  metadata {
    name = var.grafana_storage_class
  }
  storage_provisioner = var.storage_provisioner
  parameters = {
    type   = "gp3"
    fsType = "xfs"
  }
  reclaim_policy         = "Retain"
  allow_volume_expansion = true

  lifecycle {
    ignore_changes = [parameters]
  }
}

# Helm release for kube-prometheus-stack
resource "helm_release" "kube_prometheus_stack" {
  name             = var.release_name
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/templates/values.yaml.tpl", {
      # Node scheduling
      node_selector_key   = var.node_selector_key
      node_selector_value = var.node_selector_value

      # Prometheus settings
      prometheus_replicas                  = var.prometheus_replicas
      prometheus_retention                 = var.prometheus_retention
      prometheus_storage                   = var.prometheus_storage
      prometheus_storage_class             = var.prometheus_storage_class
      prometheus_resources_requests_cpu    = var.prometheus_resources.requests.cpu
      prometheus_resources_requests_memory = var.prometheus_resources.requests.memory
      prometheus_resources_limits_cpu      = var.prometheus_resources.limits.cpu
      prometheus_resources_limits_memory   = var.prometheus_resources.limits.memory

      # Alertmanager settings
      alertmanager_replicas                  = var.alertmanager_replicas
      alertmanager_storage                   = var.alertmanager_storage
      alertmanager_storage_class             = var.alertmanager_storage_class
      alertmanager_resources_requests_cpu    = var.alertmanager_resources.requests.cpu
      alertmanager_resources_requests_memory = var.alertmanager_resources.requests.memory
      alertmanager_resources_limits_cpu      = var.alertmanager_resources.limits.cpu
      alertmanager_resources_limits_memory   = var.alertmanager_resources.limits.memory

      # Node Exporter settings
      node_exporter_port = var.node_exporter_port

      # Grafana settings
      grafana_replicas                  = var.grafana_replicas
      grafana_storage                   = var.grafana_storage
      grafana_storage_class             = var.grafana_storage_class
      grafana_resources_requests_cpu    = var.grafana_resources.requests.cpu
      grafana_resources_requests_memory = var.grafana_resources.requests.memory
      grafana_resources_limits_cpu      = var.grafana_resources.limits.cpu
      grafana_resources_limits_memory   = var.grafana_resources.limits.memory

      # Feature flags
      default_rules_enabled = var.default_rules_enabled
    })
  ]

  depends_on = [
    kubernetes_storage_class_v1.prometheus,
    kubernetes_storage_class_v1.alertmanager,
    kubernetes_storage_class_v1.grafana,
  ]
}
