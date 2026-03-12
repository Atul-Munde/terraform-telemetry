# Jaeger Module

Deploys the Jaeger distributed tracing platform via Helm chart (`jaeger` 2.0.0).  
Backend storage: Elasticsearch. Receives traces from the OTel Gateway via OTLP gRPC.

## Usage

```hcl
module "jaeger" {
  source = "./modules/jaeger"

  namespace              = "telemetry"
  environment            = "staging"
  chart_version          = "2.0.0"
  elasticsearch_host     = "elasticsearch-master.telemetry.svc.cluster.local"
  collector_replicas     = 2
  query_replicas         = 2
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Kubernetes namespace | string | — |
| `environment` | Environment name (dev/staging/production) | string | — |
| `chart_version` | Jaeger Helm chart version | string | `"2.0.0"` |
| `elasticsearch_host` | ES internal hostname | string | `""` |
| `elasticsearch_port` | ES port | number | `9200` |
| `collector_replicas` | Jaeger Collector replicas | number | `2` |
| `query_replicas` | Jaeger Query replicas | number | `2` |
| `resources` | CPU/memory for collector and query pods | object | see variables.tf |
| `create_ingress` | Create ALB Ingress for Jaeger UI | bool | `false` |
| `ingress_host` | Public hostname (e.g. `jaeger.test.intangles.com`) | string | `""` |
| `alb_certificate_arn` | ACM cert ARN | string | `""` |
| `alb_group_name` | ALB IngressGroup to join | string | `""` |

## Outputs

| Name | Description |
|------|-------------|
| `query_endpoint` | Internal Jaeger UI URL (`http://jaeger-query.<ns>.svc.cluster.local:16686`) |
| `collector_grpc_endpoint` | OTLP gRPC endpoint (`jaeger-collector.<ns>.svc.cluster.local:4317`) |
| `public_url` | Public ALB URL when `create_ingress=true` |

## Architecture

```
OTel Agent (DaemonSet)
        │ OTLP gRPC
        ▼
OTel Gateway (StatefulSet) ── tail sampling
        │ OTLP gRPC :4317
        ▼
Jaeger Collector ────────────────► Elasticsearch
        │                          (jaeger-span-* / jaeger-service-*)
        ▼
Jaeger Query (UI)
https://jaeger.test.intangles.com
```

## Elasticsearch Index Templates

Jaeger is configured with `es.create-index-templates: "false"` to prevent it from  
creating index templates with bare `text` fields (which break ES 8.x aggregations).  
Fielddata-enabled templates are registered by the `elasticsearch` module's ILM job instead.

## Features

- OTLP ingestion (gRPC: 4317, HTTP: 4318) via Jaeger Collector
- Pod anti-affinity for query and collector pods
- PodDisruptionBudget enabled
- ALB ingress support (internet-facing, HTTPS-only, IP target mode)
- `es.create-index-templates: "false"` to prevent fielddata conflict with ES 8.x
