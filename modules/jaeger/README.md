# Jaeger Module

Deploys Jaeger distributed tracing platform using Helm chart.

## Usage

```hcl
module "jaeger" {
  source = "./modules/jaeger"

  namespace          = "observability"
  environment        = "production"
  storage_type       = "elasticsearch"
  elasticsearch_host = "elasticsearch-master.observability.svc.cluster.local"
  collector_replicas = 3
  query_replicas     = 2
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| namespace | Kubernetes namespace | string | - |
| environment | Environment name | string | "dev" |
| chart_version | Jaeger Helm chart version | string | "2.0.0" |
| storage_type | Backend storage type | string | "elasticsearch" |
| elasticsearch_host | ES hostname | string | "" |
| elasticsearch_port | ES port | number | 9200 |
| collector_replicas | Jaeger Collector replicas | number | 2 |
| query_replicas | Jaeger Query replicas | number | 2 |

## Outputs

| Name | Description |
|------|-------------|
| query_endpoint | Jaeger UI endpoint |
| collector_endpoint | Collector OTLP endpoint |

## Architecture

```
OTel Collector → Jaeger Collector → Elasticsearch
                       ↓
                 Jaeger Query (UI)
```

## Features

- OTLP ingestion support (gRPC: 4317, HTTP: 4318)
- Pod anti-affinity for HA
- PodDisruptionBudget enabled
- Rolling update strategy
