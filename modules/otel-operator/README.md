# OTel Operator Module

Deploys the **OpenTelemetry Operator** and all collector infrastructure:

- **Operator** — Helm chart `opentelemetry-operator` 0.66.0, 2 replicas (HA leader-election)
- **Agent** — `OpenTelemetryCollector` CRD, mode `daemonset` (1 pod per node)
- **Gateway** — `OpenTelemetryCollector` CRD, mode `statefulset` (min 2 pods, HPA 2–8)
- **Infra-Metrics** — `OpenTelemetryCollector` CRD, mode `deployment` (DB/queue scraping)
- **Instrumentation** — `Instrumentation` CRD for zero-code auto-instrumentation
- **ServiceMonitor** — scrapes Operator metrics into kube-prometheus-stack
- **RBAC** — ClusterRole + bindings for kubeletstats and pod logs access
- **HPA** — scales Gateway on CPU + memory

All CRD-backed resources use `kubectl_manifest` (gavinbunney/kubectl) instead of  
`kubernetes_manifest` to avoid plan-time CRD validation failures on fresh deploys.

## Usage

```hcl
module "otel_operator" {
  source = "./modules/otel-operator"
  count  = var.otel_operator_enabled ? 1 : 0

  namespace             = "telemetry"
  environment           = "staging"
  operator_chart_version = "0.66.0"

  # Agent DaemonSet
  agent_resources = {
    requests = { cpu = "100m",  memory = "256Mi" }
    limits   = { cpu = "250m",  memory = "512Mi" }
  }
  agent_node_selector = { "otel-agent" = "true" }

  # Gateway StatefulSet
  gateway_min_replicas = 2
  gateway_max_replicas = 8
  gateway_resources = {
    requests = { cpu = "500m",  memory = "1Gi" }
    limits   = { cpu = "2000m", memory = "2Gi" }
  }

  # Tail sampling
  tail_sampling_decision_wait       = 30
  tail_sampling_normal_percentage   = 50
  tail_sampling_slow_threshold_ms   = 2000
  tail_sampling_num_traces          = 50000

  # Export targets
  jaeger_endpoint                  = "jaeger-collector.telemetry.svc.cluster.local:4317"
  prometheus_remote_write_endpoint = "http://vminsert-victoria-metrics.telemetry.svc.cluster.local:8480/insert/0/prometheus/api/v1/write"
  elasticsearch_endpoint           = "https://elasticsearch-master.telemetry.svc.cluster.local:9200"
  elastic_password                 = var.elastic_password

  # Auto-instrumentation
  instrumentation_enabled     = true
  enabled_instrumentations    = ["nodejs"]
  app_namespace               = "telemetry"
}
```

## Inputs

### Core

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Namespace for collectors, RBAC, Instrumentation CRDs | string | `"telemetry"` |
| `operator_namespace` | Namespace for the Operator Helm release | string | `"opentelemetry-operator-system"` |
| `environment` | Environment name | string | — |
| `app_namespace` | Application namespace for auto-instrumentation | string | `"telemetry"` |
| `operator_chart_version` | opentelemetry-operator Helm chart version | string | `"0.66.0"` |
| `operator_replicas` | Operator manager replicas (min 2 for HA) | number | `2` |

### OTel Agent (DaemonSet)

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `agent_image_tag` | otelcol-contrib image tag | string | `"0.105.0"` |
| `agent_resources` | CPU/memory per Agent pod | object | 100m/256Mi → 250m/512Mi |
| `agent_node_selector` | Node selector for Agent pods | map(string) | `{"otel-agent":"true"}` |
| `kubeletstats_insecure_skip_verify` | Skip kubelet TLS verification (EKS) | bool | `true` |

### OTel Gateway (StatefulSet)

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `gateway_image_tag` | otelcol-contrib image tag | string | `"0.105.0"` |
| `gateway_min_replicas` | Min replicas (must be >= 2) | number | `2` |
| `gateway_max_replicas` | Max replicas (HPA) | number | `8` |
| `gateway_resources` | CPU/memory per Gateway pod | object | 500m/1Gi → 2000m/2Gi |

### Tail Sampling

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `tail_sampling_decision_wait` | Seconds to buffer spans before deciding | number | `30` |
| `tail_sampling_normal_percentage` | % of normal traces to keep | number | `50` |
| `tail_sampling_slow_threshold_ms` | Latency above which traces are always kept (ms) | number | `2000` |
| `tail_sampling_num_traces` | Max traces buffered in memory per Gateway pod | number | `50000` |

### Export Targets

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `jaeger_endpoint` | Jaeger collector OTLP gRPC endpoint | string | `jaeger-collector.telemetry...:4317` |
| `prometheus_remote_write_endpoint` | Remote-write URL for metrics | string | vminsert URL |
| `elasticsearch_endpoint` | ES HTTPS URL for log export | string | `https://elasticsearch-master...:9200` |
| `elastic_password` | ES password — use `TF_VAR_elastic_password` | string | `""` |
| `dash0_endpoint` | Dash0 OTLP gRPC endpoint (optional secondary export) | string | `""` |
| `dash0_auth_token` | Dash0 auth token — use `TF_VAR_dash0_auth_token` | string | `""` |

### Auto-Instrumentation

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `instrumentation_enabled` | Deploy Instrumentation CRD | bool | `true` |
| `enabled_instrumentations` | Runtimes to instrument (`nodejs`, `java`, `python`, etc.) | list(string) | `["nodejs"]` |

### Infra-Metrics

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `infra_metrics_enabled` | Deploy infra-metrics collector | bool | `false` |
| `infra_metrics_resources` | CPU/memory for infra-metrics pod | object | see variables.tf |

### Ingress

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `create_ingress` | Create ALB Ingress for Agent HTTP endpoint | bool | `false` |
| `ingress_host` | Public hostname (e.g. `otel.test.intangles.com`) | string | `""` |
| `alb_certificate_arn` | ACM cert ARN | string | `""` |
| `alb_group_name` | ALB IngressGroup name | string | `""` |

## Outputs

| Name | Description |
|------|-------------|
| `agent_grpc_endpoint` | `otel-agent-collector.<ns>.svc.cluster.local:4317` |
| `agent_http_endpoint` | `http://otel-agent-collector.<ns>.svc.cluster.local:4318` |
| `public_otlp_url` | Public ALB URL when `create_ingress=true`, otherwise internal HTTP URL |
| `gateway_grpc_endpoint` | `otel-gateway-collector.<ns>.svc.cluster.local:4317` |
| `gateway_metrics_endpoint` | Gateway Prometheus scrape endpoint (`:8889`) |
| `operator_namespace` | Namespace where the Operator is installed |
| `instrumentation_annotation_command` | `kubectl annotate` command to enable Node.js auto-instrumentation |

## Architecture

```
[App Pod]
    │ OTLP gRPC/HTTP :4317/:4318
    ▼
[OTel Agent DaemonSet]          ← nodeSelector: otel-agent=true
    │ OTLP gRPC
    ▼
[OTel Gateway StatefulSet]      ← headless service, consistent-hash routing
    │ tail sampling (30s wait)  ← min 2 pods, HPA 2-8
    ├── OTLP gRPC → Jaeger Collector :4317
    ├── prometheusremotewrite → vminsert :8480
    └── file/ES → Elasticsearch :9200

[OTel Infra-Metrics Deployment]
    └── custom scrape configs → vminsert :8480
```

## Tail Sampling Notes

The Gateway **must** run as a StatefulSet with a headless service. All spans for the same  
`traceID` are routed to the same pod via consistent hashing. If spans landed on different  
pods, they could not be sampled together.

`gateway_min_replicas >= 2` is enforced by a validation rule:
```hcl
condition     = var.gateway_min_replicas >= 2
error_message = "gateway_min_replicas must be >= 2 to ensure tail_sampling correctness."
```

## Auto-Instrumentation

```bash
# Enable Node.js auto-instrumentation for a namespace
kubectl annotate namespace <app-namespace> \
  instrumentation.opentelemetry.io/inject-nodejs="telemetry/nodejs-instrumentation"
kubectl rollout restart deployment -n <app-namespace>
```

The OTel Operator injects the SDK init container — no code changes required.
