# Architecture

This document describes the full telemetry stack deployed on `intangles-qa-cluster` (EKS, `ap-south-1`).

---

## Signal Flow

```
Applications (any namespace)
        │
        │  OTLP gRPC :4317 / HTTP :4318
        ▼
┌────────────────────────────────────────────────────────────────┐
│  OTel Agent  (DaemonSet — otel-agent-collector)                │
│  • one pod per node (nodeSelector: otel-agent=true)            │
│  • receivers: otlp, kubeletstats (TLS skip for EKS)            │
│  • exporters: otlp → Gateway                                   │
└──────────────────────────┬─────────────────────────────────────┘
                           │  OTLP gRPC :4317
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  OTel Gateway  (StatefulSet — otel-gateway-collector)          │
│  • min 2 pods, HPA 2–8 (CPU + memory)                         │
│  • headless service → load balancer consistent hashing         │
│  • tail sampling processor (30 s decision wait)                │
│  • exporters:                                                  │
│    - otlp/jaeger  → jaeger-collector.telemetry:4317            │
│    - prometheusremotewrite → vminsert-*.telemetry:8480         │
│    - file/elasticsearch → elasticsearch-master.telemetry:9200  │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│  OTel Infra-Metrics  (Deployment)                              │
│  • scrapes MongoDB / PostgreSQL / custom endpoints             │
│  • pushes metrics to vminsert via remote-write                 │
└────────────────────────────────────────────────────────────────┘

┌─────────────────────┐   ┌─────────────────────────────────────┐
│  Jaeger             │   │  VictoriaMetrics  (cluster mode)    │
│  2 collector pods   │   │  vminsert x3 → vmstorage x3         │
│  2 query pods       │   │  vmselect x3  (HPA 3-6 each)        │
│  backend: ES 8.x    │   │  replication factor 2               │
│  (jaeger-* indices) │   │  VMAgent scrapes cluster+DBs        │
│                     │   │  VMAlert → Alertmanager             │
│  Kibana (UI)        │   │  Grafana (kube-prometheus-stack)    │
└─────────────────────┘   └─────────────────────────────────────┘
```

---

## Kubernetes Resources

### OTel Operator (controller-manager)

- Helm chart: `opentelemetry-operator` 0.66.0
- 2 replicas (HA leader-election)
- Watches `OpenTelemetryCollector` and `Instrumentation` CRDs
- Deploys Agent (DaemonSet), Gateway (StatefulSet), and Infra-Metrics (Deployment) from CRDs

### OTel Agent (DaemonSet)

- Kind: `OpenTelemetryCollector` (mode: `daemonset`)
- Image: `otel/opentelemetry-collector-contrib:0.105.0`
- Service: `otel-agent-collector.telemetry.svc.cluster.local` (ports 4317 / 4318)
- NodeSelector: `otel-agent=true`
- Receivers: `otlp`, `kubeletstats`
- Exporters: `otlp` → Gateway gRPC

### OTel Gateway (StatefulSet)

- Kind: `OpenTelemetryCollector` (mode: `statefulset`)
- Image: `otel/opentelemetry-collector-contrib:0.105.0`
- Headless service: `otel-gateway-collector.telemetry.svc.cluster.local`
- Ports: 4317 (gRPC), 4318 (HTTP), 8889 (Prometheus metrics)
- Processors: `tail_sampling`, `batch`, `memory_limiter`
- HPA: min 2 / max 8 pods
- Exporters: `otlp/jaeger`, `prometheusremotewrite/vm`, optionally `file` (logs to ES)

### OTel Instrumentation CRD

- Auto-instruments Node.js pods in target namespace
- Activated by annotation: `instrumentation.opentelemetry.io/inject-nodejs`

---

## Elasticsearch (Staging)

Dedicated node-role topology:

| Role | Replicas | Storage |
|------|----------|---------|
| master | 3 | 10 Gi gp3 |
| data | 2 | 75 Gi gp3 |
| coordinating | 2 | — (no PVC) |

- Anti-affinity: `hard` (pods spread across nodes)
- HTTPS + xpack security enabled
- ILM job registers Jaeger fielddata index templates on every apply:
  - `jaeger-service-override` (priority 100) — `fielddata:true` on serviceName, operationName
  - `jaeger-span-override` (priority 100) — `fielddata:true` on serviceName, operationName, traceID, spanID

---

## Jaeger

- Helm chart: `jaeger` 2.0.0
- 2 query replicas + 2 collector replicas
- Backend: Elasticsearch (index prefix `jaeger`)
- `es.create-index-templates: "false"` — prevents Jaeger from overriding fielddata templates
- Public UI: `https://jaeger.test.intangles.com` (ALB ingress)

---

## VictoriaMetrics

- Operator-managed VMCluster CRD
- 3× vmstorage (100 Gi gp3 each, replication factor 2)
- 3× vminsert (HPA 3–6)
- 3× vmselect (HPA 3–6, 20 Gi cache each)
- VMAgent scrapes: cluster metrics, MongoDB (port `http-metrics`), PostgreSQL (port 9187)
- VMAlert → Alertmanager at `kube-prometheus-stack-alertmanager.telemetry.svc.cluster.local:9093`
- VMBackup → S3 via IRSA (IAM Role for Service Accounts)
- Public VMUI: `https://vm.test.intangles.com` (ALB ingress)
- Retention: 7 days

---

## kube-prometheus-stack

- Operator watch namespaces restricted to `telemetry` (avoids CRD conflicts with other operators)
- Provisions Grafana with pre-configured datasources:
  - VictoriaMetrics vmselect (PromQL-compatible)
  - Jaeger query server
- Public Grafana: `https://grafana.test.intangles.com` (ALB ingress)

---

## Networking / Ingress

All public UIs are exposed via AWS ALB:

| Host | Service |
|------|---------|
| kibana.test.intangles.com | Kibana |
| grafana.test.intangles.com | Grafana |
| jaeger.test.intangles.com | Jaeger query |
| vm.test.intangles.com | VictoriaMetrics UI |
| otel.test.intangles.com | OTel Agent HTTP (OTLP) |

ALB group: `intangles-ingress`
ACM cert: `arn:aws:acm:ap-south-1:294202164463:certificate/6aaf4f38-c00f-4ad2-bf41-ae4ab88123a0`

---

## Terraform Structure

```
/
├── main.tf              root module — composes all sub-modules
├── variables.tf         all input variables with defaults
├── outputs.tf           key endpoints output after apply
├── versions.tf          provider version constraints
├── backend.tf           S3 backend config
├── terraform.tfvars.example
│
├── modules/
│   ├── namespace/       Kubernetes namespace resource
│   ├── otel-operator/   OTel Operator Helm + CRD resources (Agent, Gateway, InfraMetrics, Instrumentation)
│   │   ├── main.tf           Helm release
│   │   ├── collector-agent.tf     Agent DaemonSet CRD (kubectl_manifest)
│   │   ├── collector-gateway.tf   Gateway StatefulSet CRD (kubectl_manifest)
│   │   ├── collector-infra-metrics.tf  Infra scraper CRD
│   │   ├── instrumentation.tf     Auto-instrumentation CRD (kubectl_manifest)
│   │   ├── servicemonitor.tf      ServiceMonitor CRD (kubectl_manifest)
│   │   ├── hpa.tf                 HPA for Gateway
│   │   ├── rbac.tf                ClusterRole + bindings
│   │   └── secrets.tf             Credentials secrets
│   ├── elasticsearch/   Helm + ILM/fielddata Job
│   ├── kibana/          Helm + ALB ingress
│   ├── jaeger/          Helm + ALB ingress
│   ├── kube-prometheus/ kube-prometheus-stack Helm
│   └── victoria-metrics/ VM Operator + VMCluster + VMAgent + VMAlert + S3 + IRSA
│
└── environments/
    ├── dev/             dev-specific main.tf + tfvars
    ├── staging/         staging main.tf + tfvars (active)
    └── production/      production main.tf + tfvars
```

### Provider Notes

| Provider | Why |
|----------|-----|
| `hashicorp/kubernetes ~> 2.25` | Core k8s resources (deployments, services, secrets) |
| `hashicorp/helm ~> 2.12` | Helm chart releases |
| `gavinbunney/kubectl ~> 1.14` | CRD-backed manifests — skips plan-time CRD validation (unlike `kubernetes_manifest`) |
| `hashicorp/aws ~> 5.0` | ALB, ACM, S3, IAM (IRSA for VMBackup) |
| `hashicorp/tls >= 4.0` | TLS certificate resources for ES |

---

## Module Dependency Graph

```
namespace
  └── elasticsearch
       ├── kibana
       └── jaeger
            └── otel_operator
                 └── kube_prometheus
                      └── victoria_metrics
```

(`depends_on` enforces this ordering — Jaeger waits for ES, OTel Operator waits for Jaeger endpoint.)
