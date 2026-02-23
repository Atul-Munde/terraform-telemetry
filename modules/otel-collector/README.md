# OpenTelemetry Collector Module

Deploys OpenTelemetry Collector as a Kubernetes Deployment for trace ingestion.

## Usage

```hcl
module "otel_collector" {
  source = "./modules/otel-collector"

  namespace        = "observability"
  environment      = "production"
  replicas         = 3
  jaeger_endpoint  = "jaeger-collector:4317"
  
  hpa_enabled      = true
  hpa_min_replicas = 3
  hpa_max_replicas = 15
  
  enable_sampling     = true
  sampling_percentage = 10
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| namespace | Kubernetes namespace | string | - |
| environment | Environment name | string | "dev" |
| replicas | Number of replicas | number | 2 |
| image | OTel Collector image | string | "otel/opentelemetry-collector-contrib" |
| image_version | Image version | string | "0.91.0" |
| jaeger_endpoint | Jaeger OTLP endpoint | string | - |
| hpa_enabled | Enable HPA | bool | false |
| hpa_min_replicas | HPA minimum replicas | number | 2 |
| hpa_max_replicas | HPA maximum replicas | number | 10 |
| enable_sampling | Enable tail sampling | bool | false |
| sampling_percentage | Sampling percentage | number | 100 |

## Outputs

| Name | Description |
|------|-------------|
| service_name | OTel Collector service name |
| otlp_grpc_endpoint | OTLP gRPC endpoint (4317) |
| otlp_http_endpoint | OTLP HTTP endpoint (4318) |

## Pipeline Configuration

```yaml
receivers:
  - otlp (gRPC: 4317, HTTP: 4318)
  - prometheus (self-metrics)

processors:
  - memory_limiter
  - k8sattributes
  - resource
  - tail_sampling (optional)
  - batch

exporters:
  - otlp (to Jaeger)
  - logging
```

## Features

- HPA with CPU/Memory scaling
- Pod anti-affinity for distribution
- PodDisruptionBudget (50% min available)
- Dynamic tail sampling
- K8s attribute enrichment
