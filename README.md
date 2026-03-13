# Telemetry Stack — Terraform (EKS / `ap-south-1`)

Production-grade observability platform for the **`intangles`** cluster, managed entirely with Terraform.
All components live in the `telemetry` Kubernetes namespace on **`intangles-qa-cluster`** (`ap-south-1`).

---

## Architecture Overview

```
Applications (any namespace)
        │
        │  OTLP gRPC / HTTP  (push)
        ▼
┌────────────────────────────────────┐
│  OTel Agent  (DaemonSet)           │  ← 1 pod per node
│  otel-agent-collector              │    receives spans / metrics / logs locally
└──────────────┬─────────────────────┘
               │  OTLP gRPC  (forward all signals)
               ▼
┌────────────────────────────────────┐
│  OTel Gateway (StatefulSet)        │  ← tail sampling + fan-out
│  otel-gateway-collector            │    min 2 pods (HPA 2–8), headless service
└────────┬───────────────────────────┘
         │ Traces         │ Metrics          │ Logs
         ▼                ▼                  ▼
   Jaeger (ES backend)  VictoriaMetrics  Elasticsearch
   jaeger-collector     vminsert:8480    (fileexporter)
         │                │
         ▼                ▼
   Jaeger UI       Grafana (kube-prometheus-stack)
   Kibana
```

### Component Inventory

| Component | Kind | Chart / Image Version | Replicas (staging) |
|-----------|------|-----------------------|-------------------|
| opentelemetry-operator | Helm | 0.66.0 | 2 (HA) |
| OTel Agent | DaemonSet (CRD) | otelcol-contrib 0.105.0 | 1 per node |
| OTel Gateway | StatefulSet (CRD) | otelcol-contrib 0.105.0 | 2–8 (HPA) |
| OTel Infra-Metrics | Deployment (CRD) | otelcol-contrib 0.105.0 | 1 |
| Elasticsearch | Helm | 8.x (dedicated roles) | 3 master + 2 data + 2 coordinating |
| Kibana | Helm | 8.5.1 | 1 |
| Jaeger | Helm | 2.0.0 | 2 query + 2 collector |
| VictoriaMetrics | Operator + VMCluster | cluster mode | 3 storage + 3 insert + 3 select |
| Grafana | kube-prometheus-stack | — | 1 |
| VMAgent | CRD | — | 1 |
| VMAlert | CRD | — | 1 |

---

## Endpoints

### Internal (within-cluster)

| Service | Address |
|---------|---------|
| OTel Agent gRPC | `otel-agent-collector.telemetry.svc.cluster.local:4317` |
| OTel Agent HTTP | `http://otel-agent-collector.telemetry.svc.cluster.local:4318` |
| OTel Gateway gRPC | `otel-gateway-collector.telemetry.svc.cluster.local:4317` |
| VictoriaMetrics write | `http://vminsert-victoria-metrics.telemetry.svc.cluster.local:8480/insert/0/prometheus/api/v1/write` |
| VictoriaMetrics query | `http://vmselect-victoria-metrics.telemetry.svc.cluster.local:8481/select/0/prometheus` |
| Jaeger query | `http://jaeger-query.telemetry.svc.cluster.local:16686` |
| Elasticsearch | `https://elasticsearch-master.telemetry.svc.cluster.local:9200` |

### Public (AWS ALB + ACM TLS)

| UI | URL |
|----|-----|
| Kibana | https://kibana.test.intangles.com |
| Grafana | https://grafana.test.intangles.com |
| Jaeger | https://jaeger.test.intangles.com |
| VictoriaMetrics | https://vm.test.intangles.com |
| OTel (OTLP HTTP) | https://otel.test.intangles.com |

ALB group: `intangles-ingress`
ACM cert: `arn:aws:acm:ap-south-1:294202164463:certificate/6aaf4f38-c00f-4ad2-bf41-ae4ab88123a0`

---

## Terraform Modules

```
modules/
├── namespace/           creates telemetry namespace + resource labels
├── otel-operator/       OTel Operator Helm + Agent/Gateway/InfraMetrics CRDs + RBAC + Instrumentation CRD
├── elasticsearch/       Elasticsearch Helm, ILM job, Jaeger fielddata index templates
├── kibana/              Kibana Helm + ALB ingress
├── jaeger/              Jaeger Helm (ES backend), 2 query + 2 collector replicas
├── kube-prometheus/     kube-prometheus-stack (Prometheus CRDs, Grafana, Alertmanager)
└── victoria-metrics/    VictoriaMetrics Operator + VMCluster + VMAgent + VMAlert + S3 backup
```

All modules are independently togglable via `*_enabled` booleans in `variables.tf`.

---

## Environments

```
environments/
├── dev/         minimal single-node, no HA
├── staging/     full HA stack — active (ap-south-1, intangles-qa-cluster)
└── production/  production config
```

Each environment has its own `main.tf` (calls root module) and `terraform.tfvars`.

---

## Quick Start

### Prerequisites

- Terraform >= 1.5
- `kubectl` configured for `intangles-qa-cluster` (ap-south-1) — see [docs/SETUP.md](docs/SETUP.md) for `AWS_PROFILE` setup
- Helm >= 3.12

### Deploy (staging)

```bash
export AWS_PROFILE=<your-profile-name>   # set your local AWS profile
cd environments/staging

terraform init                           # backend config is already in main.tf

TF_VAR_elastic_password='<password>' \
TF_VAR_kibana_encryption_key='<32-char-key>' \
TF_VAR_dash0_auth_token='Bearer <token>' \
terraform apply -auto-approve
```

> Credentials must **never** be committed. Use `TF_VAR_*` environment variables or copy `environments/staging/.tf_apply.sh.example` → `.tf_apply.sh` (git-ignored).

### Verify pods

```bash
kubectl get pods -n telemetry

# OTel Agent (1 per node)
kubectl get pods -n telemetry -l app.kubernetes.io/name=otel-agent-collector

# OTel Gateway (min 2)
kubectl get pods -n telemetry -l app.kubernetes.io/name=otel-gateway-collector

# Elasticsearch (3 master + 2 data + 2 coordinating)
kubectl get pods -n telemetry -l chart=elasticsearch

# Jaeger
kubectl get pods -n telemetry -l app.kubernetes.io/name=jaeger

# VictoriaMetrics
kubectl get pods -n telemetry | grep -E "vminsert|vmselect|vmstorage"
```

---

## Sending Telemetry from Applications

### Same cluster (recommended)

```bash
# gRPC
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.telemetry.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc

# HTTP/protobuf
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.telemetry.svc.cluster.local:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

### From outside the cluster

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.test.intangles.com
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

---

## Auto-Instrumentation

The OTel Operator manages an `Instrumentation` CRD. Enable namespace-wide auto-instrumentation:

```bash
# Node.js
kubectl annotate namespace <app-namespace> \
  instrumentation.opentelemetry.io/inject-nodejs="telemetry/nodejs-instrumentation"
kubectl rollout restart deployment -n <app-namespace>
```

Trace flow: App → OTel Agent → OTel Gateway → Jaeger.

---

## Tail Sampling (Gateway)

| Parameter | Variable | Default |
|-----------|----------|---------|
| Decision wait | `tail_sampling_decision_wait` | 30 s |
| Normal trace keep % | `tail_sampling_normal_percentage` | configurable |
| Slow trace threshold | `tail_sampling_slow_threshold_ms` | configurable ms |
| Max buffered traces/pod | `tail_sampling_num_traces` | configurable |

Error and slow traces are **always** kept. Tail sampling requires >= 2 Gateway pods — the headless StatefulSet ensures consistent hash-based routing so each trace's spans reach the same sampling decision.

---

## Metrics (VMAgent)

VMAgent scrapes:
- Kubernetes cluster metrics (kube-state-metrics, node-exporter, kubelet, API server)
- MongoDB exporters — label `app.kubernetes.io/name=mongodb`, port `http-metrics`
- PostgreSQL / TimescaleDB exporters — label `pg-exporter-service`, port `9187`
- All ServiceMonitors in the `telemetry` namespace

Metrics written to VictoriaMetrics via remote-write. Retention: **7 days**.
VMAlert sends to Alertmanager: `kube-prometheus-stack-alertmanager.telemetry.svc.cluster.local:9093`.

---

## VictoriaMetrics Cluster (Staging)

| Component | Replicas | Storage |
|-----------|----------|---------|
| vmstorage | 3 | 100 Gi EBS gp3 each |
| vminsert | 3 (HPA 3–6) | — |
| vmselect | 3 (HPA 3–6) | 20 Gi cache each |

Replication factor: **2**. VMBackup -> S3 via IRSA. Bucket output as `vm_backup_s3_bucket`.

---

## Key Variables

See [`variables.tf`](variables.tf):

| Variable | Description |
|----------|-------------|
| `environment` | `dev` / `staging` / `production` |
| `namespace` | Kubernetes namespace (default: `telemetry`) |
| `otel_operator_enabled` | Deploy OTel Operator + collectors (default: `true`) |
| `elasticsearch_enabled` | Deploy Elasticsearch |
| `kibana_enabled` | Deploy Kibana |
| `victoria_metrics_enabled` | Deploy VictoriaMetrics cluster |
| `kube_prometheus_enabled` | Deploy kube-prometheus-stack / Grafana |
| `infra_metrics_enabled` | Deploy infra-metrics OTel collector |
| `instrumentation_enabled` | Deploy auto-instrumentation CRD |
| `gateway_min_replicas` | Min Gateway pods (must be >= 2) |
| `data_retention_days` | Elasticsearch index retention |

---

## Provider Versions

| Provider | Version |
|----------|---------|
| hashicorp/kubernetes | `~> 2.25` |
| hashicorp/helm | `~> 2.12` |
| gavinbunney/kubectl | `~> 1.14` |
| hashicorp/aws | `~> 5.0` |
| hashicorp/tls | `>= 4.0` |

> `gavinbunney/kubectl` is used for all CRD-backed resources instead of `kubernetes_manifest` to avoid plan-time CRD validation failures on fresh deploys.

---

## Troubleshooting

### Kibana pre-install hook stuck

```bash
kubectl delete configmap -n telemetry kibana-kibana-helm-scripts
kubectl delete secret   -n telemetry sh.helm.release.v1.kibana.v1
kubectl delete secret   -n telemetry kibana-kibana-es-token
terraform destroy -target='module.telemetry.module.kibana[0]'
```

### Jaeger "all shards failed" (ES 8.x fielddata)

ES 8.x blocks `terms` aggregations on `text` fields without `fielddata:true`.
Fixed permanently by:
1. Priority-100 index templates (`jaeger-service-override`, `jaeger-span-override`) applied by the ILM job on every apply.
2. `es.create-index-templates: "false"` in Jaeger Helm values prevents Jaeger from overriding them.

### Trace forwarding issues

```bash
kubectl logs -n telemetry -l app.kubernetes.io/name=otel-agent-collector   --tail=50
kubectl logs -n telemetry -l app.kubernetes.io/name=otel-gateway-collector --tail=50
```

---

**Terraform** >= 1.5 | **Kubernetes** >= 1.24 | **Environment**: staging (`ap-south-1`, `intangles-qa-cluster`)
