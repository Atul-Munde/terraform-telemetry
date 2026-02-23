# kube-prometheus-stack Module

Deploys the complete Prometheus monitoring stack including Prometheus, Alertmanager, Grafana, and related components.

## Usage

```hcl
module "kube_prometheus" {
  source = "./modules/kube-prometheus"

  namespace        = "observability"
  environment      = "production"
  chart_version    = "81.6.2"
  
  # Node scheduling
  node_selector_key   = "data-monitoring"
  node_selector_value = "true"
  
  # Prometheus
  prometheus_replicas = 2
  prometheus_storage  = "100Gi"
  prometheus_retention = "30d"
  
  # Alertmanager
  alertmanager_replicas = 2
  alertmanager_storage  = "10Gi"
  
  # Grafana
  grafana_replicas = 2
  grafana_storage  = "10Gi"
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| namespace | Kubernetes namespace | string | - |
| chart_version | Helm chart version | string | "81.6.2" |
| node_selector_key | Node selector label key | string | "data-monitoring" |
| node_selector_value | Node selector label value | string | "true" |
| prometheus_replicas | Prometheus replicas | number | 2 |
| prometheus_storage | Prometheus PVC size | string | "50Gi" |
| prometheus_retention | Data retention period | string | "15d" |
| alertmanager_replicas | Alertmanager replicas | number | 2 |
| alertmanager_storage | Alertmanager PVC size | string | "10Gi" |
| grafana_replicas | Grafana replicas | number | 1 |
| grafana_storage | Grafana PVC size | string | "10Gi" |
| create_storage_classes | Create custom storage classes | bool | true |
| default_rules_enabled | Enable default alerting rules | bool | true |

## Outputs

| Name | Description |
|------|-------------|
| prometheus_url | Internal Prometheus URL |
| grafana_url | Internal Grafana URL |
| alertmanager_url | Internal Alertmanager URL |

## Components

- **Prometheus**: Metrics collection and storage
- **Alertmanager**: Alert routing and notifications
- **Grafana**: Visualization and dashboards
- **Prometheus Operator**: CRD-based configuration
- **kube-state-metrics**: Kubernetes state metrics
- **node-exporter**: Node-level metrics

## Features

- Storage classes with Retain policy
- Hard pod anti-affinity
- Topology spread constraints for multi-AZ
- PodDisruptionBudget enabled
- Security context with non-root user
