# kube-prometheus Module

Deploys the `kube-prometheus-stack` Helm chart (Prometheus Operator + Grafana + Alertmanager).

In this stack, **VictoriaMetrics handles metrics storage and scraping** via VMAgent.  
kube-prometheus-stack is deployed primarily for:
- Its CRDs (ServiceMonitor, PodMonitor, PrometheusRule, AlertmanagerConfig)
- Grafana with pre-configured VictoriaMetrics and Jaeger datasources
- Alertmanager

The operator is scoped to the `telemetry` namespace to avoid CRD conflicts with any  
Prometheus Operator already running elsewhere in the cluster.

## Usage

```hcl
module "kube_prometheus" {
  source = "./modules/kube-prometheus"

  namespace     = "telemetry"
  environment   = "staging"
  chart_version = "81.6.2"

  kube_prometheus_create_storage_classes = false   # storage classes already exist

  prometheus_resources = {
    requests = { cpu = "2000m", memory = "6Gi" }
    limits   = { cpu = "4000m", memory = "12Gi" }
  }

  # VictoriaMetrics datasource for Grafana
  vm_grafana_datasource_url = "http://vmselect-victoria-metrics.telemetry.svc.cluster.local:8481/select/0/prometheus"

  # Jaeger datasource for Grafana
  jaeger_grafana_datasource_url = "http://jaeger-query.telemetry.svc.cluster.local:16686"

  # Restrict Prometheus Operator to telemetry namespace only
  operator_watch_namespaces = ["telemetry"]
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Kubernetes namespace | string | `"telemetry"` |
| `environment` | Environment name | string | `"dev"` |
| `chart_version` | Helm chart version | string | `"81.6.2"` |
| `release_name` | Helm release name | string | `"kube-prometheus-stack"` |
| `node_selector_key` | Node selector label key | string | `"telemetry"` |
| `node_selector_value` | Node selector label value | string | `"true"` |
| `create_storage_classes` | Create custom StorageClasses | bool | `true` |
| `prometheus_replicas` | Prometheus replicas | number | `2` |
| `prometheus_retention` | Prometheus retention period | string | `"15d"` |
| `prometheus_storage` | Prometheus PVC size | string | `"50Gi"` |
| `prometheus_resources` | Prometheus CPU/memory | object | see variables.tf |
| `alertmanager_replicas` | Alertmanager replicas | number | `2` |
| `alertmanager_storage` | Alertmanager PVC size | string | `"10Gi"` |
| `grafana_replicas` | Grafana replicas | number | `1` |
| `grafana_storage` | Grafana PVC size | string | `"10Gi"` |
| `vm_grafana_datasource_url` | VictoriaMetrics vmselect Prometheus-compatible URL | string | `""` |
| `jaeger_grafana_datasource_url` | Jaeger query URL for Grafana trace datasource | string | `""` |
| `operator_watch_namespaces` | Namespaces the Prometheus Operator watches | list(string) | `[]` |
| `create_ingress` | Create ALB Ingress for Grafana | bool | `false` |
| `ingress_host` | Grafana public hostname | string | `""` |
| `alb_certificate_arn` | ACM cert ARN | string | `""` |
| `alb_group_name` | ALB IngressGroup name | string | `""` |

## Outputs

| Name | Description |
|------|-------------|
| `prometheus_url` | Internal Prometheus URL |
| `grafana_url` | Internal Grafana URL / public URL when ingress enabled |
| `alertmanager_url` | Internal Alertmanager URL |

## Grafana Datasources

When configured, the module provisions Grafana with:

| Datasource | URL | Type |
|------------|-----|------|
| VictoriaMetrics | `http://vmselect-victoria-metrics.telemetry.svc.cluster.local:8481/select/0/prometheus` | Prometheus-compatible |
| Jaeger | `http://jaeger-query.telemetry.svc.cluster.local:16686` | Jaeger |

Access Grafana: https://grafana.test.intangles.com

## Namespace Isolation

Setting `operator_watch_namespaces = ["telemetry"]` restricts the kube-prometheus  
Prometheus Operator to only process CRDs in the `telemetry` namespace. This prevents  
reconciliation conflicts when another Prometheus Operator is already running in the cluster  
(e.g. in an `observability` namespace).

## Components

| Component | Role |
|-----------|------|
| Prometheus Operator | Reconciles ServiceMonitor, PodMonitor, PrometheusRule CRDs |
| Prometheus | Metrics storage (side-by-side with VictoriaMetrics; scraping done by VMAgent) |
| Alertmanager | Alert routing and notification |
| Grafana | Dashboards and visualization |
| kube-state-metrics | Kubernetes object state metrics |
| node-exporter | Per-node CPU/memory/disk metrics |
