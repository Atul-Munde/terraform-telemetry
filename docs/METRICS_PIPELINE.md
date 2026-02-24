# Metrics Pipeline: End-to-End Flow

This document covers the complete metrics collection and observability pipeline —
from application pods → OTel Agent → OTel Gateway → Prometheus — including how
tail sampling coexists with metrics, how Prometheus discovers the gateway, and
what each configuration decision means.

---

## Table of Contents

1. [Full Architecture Diagram](#1-full-architecture-diagram)
2. [Stage 1 — OTel Agent (DaemonSet)](#2-stage-1--otel-agent-daemonset)
3. [Stage 2 — OTel Gateway (StatefulSet)](#3-stage-2--otel-gateway-statefulset)
4. [Stage 3 — Prometheus Discovery Chain](#4-stage-3--prometheus-discovery-chain)
5. [How Tail Sampling and Metrics Coexist](#5-how-tail-sampling-and-metrics-coexist)
6. [Per-Pod Metric Differentiation](#6-per-pod-metric-differentiation)
7. [Why 4 Scrape Targets Became 2 (Headless Service Fix)](#7-why-4-scrape-targets-became-2-headless-service-fix)
8. [Where serviceMonitorSelector Is Defined](#8-where-servicemonitorselector-is-defined)
9. [Is the service.instance.id Processor Needed?](#9-is-the-serviceinstanceid-processor-needed)
10. [Useful PromQL Queries](#10-useful-promql-queries)

---

## 1. Full Architecture Diagram

```
┌──────────────────────────────────── KUBERNETES CLUSTER ─────────────────────────────────────┐
│                                                                                               │
│  ┌─────────────────────────────── AGENT (DaemonSet) ──────────────────────────────────────┐ │
│  │  One pod per node — runs on every node with label otel-agent=true                       │ │
│  │                                                                                          │ │
│  │  Receives  ←── OTLP traces/metrics from app pods on SAME node                          │ │
│  │  Collects  ←── kubeletstats: container/pod/node CPU, memory, filesystem metrics        │ │
│  │  Enriches  ←── k8sattributes: injects k8s.pod.name, k8s.namespace, k8s.node.name      │ │
│  │                                                                                          │ │
│  │  TRACE export: loadbalancing exporter (consistent-hash by traceID)                     │ │
│  │    → headless DNS resolves to all gateway pod IPs                                       │ │
│  │    → traceID-AAA always routed to gateway-0                                             │ │
│  │    → traceID-BBB always routed to gateway-1                                             │ │
│  │    (ensures all spans of a trace land on the SAME gateway pod)                          │ │
│  │                                                                                          │ │
│  │  METRIC export: OTLP → gateway :4317 (round-robin OK — no ordering needed)             │ │
│  └──────────────────────────────────────────────────────────────────────────────────────── ┘ │
│                          │ traces (hash-routed)          │ metrics (OTLP)                    │
│                          ▼                               ▼                                   │
│  ┌──────────────────────────────── GATEWAY (StatefulSet) ──────────────────────────────── ┐ │
│  │  2 stable pods — gateway-0, gateway-1 — on different nodes (pod anti-affinity)          │ │
│  │                                                                                          │ │
│  │   gateway-0 (192.168.13.58)            gateway-1 (192.168.27.137)                      │ │
│  │   ┌──────────────────────────┐         ┌──────────────────────────┐                    │ │
│  │   │  TRACES pipeline         │         │  TRACES pipeline         │                    │ │
│  │   │  memory_limiter          │         │  memory_limiter          │                    │ │
│  │   │  filter/noise            │         │  filter/noise            │                    │ │
│  │   │  transform/clean-attrs   │         │  transform/clean-attrs   │                    │ │
│  │   │  transform/peer-service  │         │  transform/peer-service  │                    │ │
│  │   │  tail_sampling (30s wait)│         │  tail_sampling (30s wait)│                    │ │
│  │   │  batch                   │         │  batch                   │                    │ │
│  │   │  → otlp/jaeger           │         │  → otlp/jaeger           │                    │ │
│  │   └──────────────────────────┘         └──────────────────────────┘                    │ │
│  │                                                                                          │ │
│  │   ┌──────────────────────────┐         ┌──────────────────────────┐                    │ │
│  │   │  METRICS pipeline        │         │  METRICS pipeline        │                    │ │
│  │   │  memory_limiter          │         │  memory_limiter          │                    │ │
│  │   │  batch                   │         │  batch                   │                    │ │
│  │   │  → prometheus exporter   │         │  → prometheus exporter   │                    │ │
│  │   │    :8889/metrics         │         │    :8889/metrics         │                    │ │
│  │   │    resource attrs        │         │    resource attrs        │                    │ │
│  │   │    → Prometheus labels   │         │    → Prometheus labels   │                    │ │
│  │   └────────────┬─────────────┘         └───────────┬──────────────┘                    │ │
│  └────────────────┼─────────────────────────────────── ┼───────────────────────────────── ┘ │
│                   │ :8889                               │ :8889                              │
│                   └────────────────┬────────────────────┘                                   │
│                                    │                                                         │
│                    otel-gateway-collector-headless (ClusterIP: None)                        │
│                    Endpoints: 192.168.13.58:8889, 192.168.27.137:8889                       │
│                                    │                                                         │
│  ┌─────────────────────────────── PROMETHEUS DISCOVERY ───────────────────────────────── ┐ │
│  │                                                                                          │ │
│  │  Step 1 — Prometheus CR (set by Helm chart default):                                    │ │
│  │    spec.serviceMonitorSelector:                                                          │ │
│  │      matchLabels: { release: kube-prometheus-stack }                                    │ │
│  │    spec.serviceMonitorNamespaceSelector: {}  ← watches ALL namespaces                   │ │
│  │                          │                                                               │ │
│  │  Step 2 — ServiceMonitor otel-gateway (servicemonitor.tf):                              │ │
│  │    metadata.labels:                                                                      │ │
│  │      release: kube-prometheus-stack          ← passes Step 1 filter                     │ │
│  │    spec.selector.matchLabels:                                                            │ │
│  │      app.kubernetes.io/name: otel-gateway-collector                                     │ │
│  │      app.kubernetes.io/managed-by: opentelemetry-operator                               │ │
│  │      operator.opentelemetry.io/collector-service-type: headless  ← 1 service only      │ │
│  │    spec.endpoints:                                                                       │ │
│  │      port: prometheus  interval: 30s  path: /metrics                                    │ │
│  │                          │                                                               │ │
│  │  Step 3 — Service otel-gateway-collector-headless matches selector                      │ │
│  │                          │                                                               │ │
│  │  Step 4 — Prometheus resolves Endpoints → scrapes pod IPs directly                      │ │
│  │    GET http://192.168.13.58:8889/metrics   (gateway-0)  health=up                       │ │
│  │    GET http://192.168.27.137:8889/metrics  (gateway-1)  health=up                       │ │
│  │    2 targets total                                                                       │ │
│  └──────────────────────────────────────────────────────────────────────────────────────── ┘ │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Stage 1 — OTel Agent (DaemonSet)

**File:** `modules/otel-operator/collector-agent.tf`

The Agent runs one pod per node. Its responsibilities:

### Receiving application telemetry
Apps send OTLP to the Agent on the same node via:
- gRPC: `otel-agent-collector.telemetry.svc.cluster.local:4317`
- HTTP: `http://otel-agent-collector.telemetry.svc.cluster.local:4318`

### Collecting infrastructure metrics
The `kubeletstats` receiver scrapes the node's kubelet API to collect:
- `container.cpu.time`, `container.memory.usage` — per container
- `k8s.pod.cpu.time`, `k8s.pod.memory.usage` — per pod
- `k8s.node.cpu.time`, `k8s.node.memory.usage` — per node

Each metric is tagged with `k8s.pod.name`, `k8s.pod.uid`, `k8s.namespace.name`,
`k8s.node.name` by the `k8sattributes` processor.

### Routing traces to the correct gateway pod
The `loadbalancing` exporter uses **consistent-hash on traceID**:

```
traceID hash % number_of_gateway_pods → always same pod for same trace
```

This is critical for tail sampling — all spans of trace-AAA must arrive at gateway-0
so it has the full picture to make a keep/drop decision after 30 seconds.

The headless service `otel-gateway-collector-headless` DNS returns **all pod IPs**,
not a VIP, so the load balancer can address each pod individually.

### Routing metrics to the gateway
Metrics do **not** need consistent routing. They are forwarded via OTLP to the
gateway ClusterIP service (round-robin). Each gateway pod independently exposes
whatever metrics it received at `:8889`.

---

## 3. Stage 2 — OTel Gateway (StatefulSet)

**File:** `modules/otel-operator/collector-gateway.tf`

The Gateway runs as a StatefulSet (not a Deployment) — stable pod names and network
identity are required for tail sampling correctness.

### Why StatefulSet is mandatory for tail sampling

With a Deployment, pods get random names and can be rescheduled freely. The
loadbalancing exporter on the Agent routes by consistent-hash to pod IPs, but if
a pod is replaced (new IP), in-flight traces may split across pods. StatefulSet
keeps `gateway-0` and `gateway-1` as stable identities.

### Traces pipeline

```
receivers:  [otlp]
processors:
  memory_limiter       → shed load before OOM; always first
  filter/noise         → drop health probes, ELB checks, SDK self-traces,
                         bare tcp/dns/redis-connect spans
  transform/clean-attrs → delete process.command, process.executable,
                          os.type, os.version, db.connection_string
  transform/peer-service → derive peer.service for DB/queue spans
                           (mongodb, redis, postgresql, rabbitmq)
  tail_sampling        → wait 30s for all spans of a trace to arrive, then:
                         - always keep: status_code=ERROR
                         - always keep: latency > threshold_ms
                         - keep 50%: normal traces (probabilistic)
  batch                → group spans before export; always last
exporters:  [otlp/jaeger]
```

The `tail_sampling.decision_wait: 30s` covers async processing (e.g. a request
triggers a queue job that completes up to ~20s later — all those spans are needed
before deciding to keep or drop the trace).

### Metrics pipeline

```
receivers:  [otlp]
processors:
  memory_limiter       → shed load if memory pressure
  batch                → buffer before writing to exporter
exporters:  [prometheus]
  endpoint: 0.0.0.0:8889
  resource_to_telemetry_conversion: enabled: true
```

No sampling on metrics — all metrics pass through. The prometheus exporter
exposes a `/metrics` scrape endpoint on port `8889`. The
`resource_to_telemetry_conversion: enabled: true` setting is critical — it
converts every OTel resource attribute (e.g. `k8s.pod.name`) into a Prometheus
label on each metric series.

### Self-telemetry (port 8888)

The gateway's own internal OTel Collector metrics (spans received, spans dropped,
exporter queue depth, memory usage) are exposed on port `8888`. These are
**separate** from the application metrics on `8889`. Configured via:

```hcl
service.telemetry.metrics = {
  level   = "detailed"
  address = "0.0.0.0:8888"
}
```

---

## 4. Stage 3 — Prometheus Discovery Chain

**File:** `modules/otel-operator/servicemonitor.tf`

Prometheus does not scrape pods or services directly. The Prometheus Operator
watches for `ServiceMonitor` CRDs and generates Prometheus scrape configs from them.

### Step 1 — Prometheus CR: which ServiceMonitors to watch

The `kube-prometheus-stack` Helm chart installs a `Prometheus` CR with:

```yaml
spec:
  serviceMonitorSelector:
    matchLabels:
      release: kube-prometheus-stack     # only watch SMs with this label
  serviceMonitorNamespaceSelector: {}    # watch all namespaces
```

This is **set automatically by the Helm chart** — not defined in `values.yaml.tpl`.
Any ServiceMonitor without `release: kube-prometheus-stack` is completely ignored
by Prometheus.

### Step 2 — ServiceMonitor: which service to scrape

```hcl
metadata.labels:
  release: "kube-prometheus-stack"        # passes Step 1 filter

spec.selector.matchLabels:
  app.kubernetes.io/name: "otel-gateway-collector"
  app.kubernetes.io/managed-by: "opentelemetry-operator"
  operator.opentelemetry.io/collector-service-type: "headless"

spec.endpoints:
  - port: "prometheus"    # named port on the service = 8889
    interval: "30s"
    path: "/metrics"
```

### Step 3 — Service: must have matching labels and named port

The OTel Operator creates 3 services automatically for every collector CRD:

| Service | Type | Port label | Has 8889? |
|---|---|---|---|
| `otel-gateway-collector` | ClusterIP (VIP) | `collector-service-type: base` | ✅ |
| `otel-gateway-collector-headless` | ClusterIP: None | `collector-service-type: headless` | ✅ |
| `otel-gateway-collector-monitoring` | ClusterIP (VIP) | `collector-service-type: monitoring` | ❌ (8888 only) |

The ServiceMonitor selector includes `collector-service-type: headless` so only the
headless service matches — preventing duplicate scrape targets (see Section 7).

### Step 4 — Endpoints: Prometheus scrapes pod IPs directly

Prometheus Operator reads the `Endpoints` object for the matched service.
For a StatefulSet with 2 pods, this contains:

```
192.168.13.58:8889   → otel-gateway-collector-0
192.168.27.137:8889  → otel-gateway-collector-1
```

Prometheus scrapes **each IP independently** — never via the VIP/ClusterIP.
This is true for both headless and base services; headless is chosen to keep
the selector unambiguous.

---

## 5. How Tail Sampling and Metrics Coexist

They run in **completely separate pipelines** inside the same gateway pod and
share no state:

```
                        gateway pod
                   ┌─────────────────────────────┐
OTLP traces ──────▶│  traces pipeline            │──► Jaeger
                   │  (has tail_sampling, 30s)   │
                   │                             │
OTLP metrics ─────▶│  metrics pipeline           │──► :8889/metrics
                   │  (no sampling, just batch)  │         ▲
                   └─────────────────────────────┘         │
                                                     Prometheus scrapes
```

Tail sampling decisions on traces have zero impact on metrics. A trace that gets
**dropped** by tail sampling still contributes its metrics (span counts, latencies)
to the metrics pipeline — these are aggregated before sampling decisions are made.

---

## 6. Per-Pod Metric Differentiation

With 2 gateway pods and `resource_to_telemetry_conversion: enabled: true`, each
metric series in Prometheus automatically has labels identifying which pod the
metric came from.

### Labels added by the OTel pipeline

Set by the Agent's `kubeletstats` receiver + `k8sattributes` processor, then
promoted to Prometheus labels by `resource_to_telemetry_conversion`:

| Prometheus Label | OTel Resource Attribute | Example Value |
|---|---|---|
| `k8s_pod_name` | `k8s.pod.name` | `my-app-xyz` |
| `k8s_namespace_name` | `k8s.namespace.name` | `default` |
| `k8s_node_name` | `k8s.node.name` | `ip-192-168-4-15...` |
| `k8s_pod_uid` | `k8s.pod.uid` | `571022f9-...` |
| `k8s_container_name` | `k8s.container.name` | `app` |
| `cloud_availability_zone` | `cloud.availability_zone` | `ap-south-1a` |
| `cloud_region` | `cloud.region` | `ap-south-1` |
| `host_name` | `host.name` | node hostname |

### Labels added by Prometheus itself

| Prometheus Label | Source |
|---|---|
| `instance` | `<pod-ip>:8889` — which gateway pod served the scrape |
| `job` | derived from the ServiceMonitor name |
| `namespace` | `telemetry` |

### Example scraped metric

```
container_cpu_utilization_ratio{
  k8s_pod_name="my-app-xyz-7d8f9c",
  k8s_node_name="ip-192-168-4-15.ap-south-1.compute.internal",
  k8s_namespace_name="default",
  k8s_container_name="app",
  cloud_availability_zone="ap-south-1a",
  cloud_region="ap-south-1",
  instance="192.168.13.58:8889",
  job="serviceMonitor/telemetry/otel-gateway/0"
} 0.012
```

Each pod's metrics appear as separate time series even though both gateway pods
serve data — the `instance` label distinguishes them, and the `k8s_pod_name` label
identifies the application pod the metric is about.

---

## 7. Why 4 Scrape Targets Became 2 (Headless Service Fix)

### The problem

The OTel Operator creates 3 services for the gateway, all sharing the label
`app.kubernetes.io/name: otel-gateway-collector`. The original ServiceMonitor
selector only had 2 labels (`name` + `managed-by`), which matched **both** the
`base` (ClusterIP) and `headless` services.

```
selector matches:  otel-gateway-collector         (base, ClusterIP)
                   otel-gateway-collector-headless (headless, ClusterIP: None)

Both have endpoints: pod-0 IP, pod-1 IP

Result: 4 scrape targets
  base-service     → pod-0   ← duplicate
  base-service     → pod-1   ← duplicate
  headless-service → pod-0
  headless-service → pod-1
→ every metric stored twice in Prometheus
```

### The fix

Added `operator.opentelemetry.io/collector-service-type: headless` to the
ServiceMonitor selector — only the headless service carries this label.

```
selector matches:  otel-gateway-collector-headless (headless only)

Result: 2 scrape targets
  headless-service → pod-0  ✅
  headless-service → pod-1  ✅
```

### Why headless and not base?

Both work identically — Prometheus always resolves the `Endpoints` object to pod
IPs regardless of whether the service has a ClusterIP or not. Headless is the
conventional choice for StatefulSets because it explicitly communicates
"individual pod identity matters here", but `collector-service-type: base` would
produce the same 2 correct targets.

---

## 8. Where serviceMonitorSelector Is Defined

**It is not defined in any Terraform file** — it is set automatically by the
`kube-prometheus-stack` Helm chart.

```
modules/kube-prometheus/templates/values.yaml.tpl
  └── no serviceMonitorSelector key
           ↓ helm install kube-prometheus-stack
           
Prometheus CR (auto-created by Helm):
  spec:
    serviceMonitorSelector:
      matchLabels:
        release: "kube-prometheus-stack"    ← chart default
    serviceMonitorNamespaceSelector: {}     ← watch all namespaces
```

This is why the `release: kube-prometheus-stack` label on the ServiceMonitor in
`servicemonitor.tf` is required — without it, Prometheus Operator ignores the
ServiceMonitor entirely even if the service selector is correct.

### To override (watch all ServiceMonitors without label filter)

Add to `prometheusSpec` in `values.yaml.tpl`:

```yaml
prometheusSpec:
  serviceMonitorSelectorNilUsesHelmValues: false
  serviceMonitorSelector: {}
  serviceMonitorNamespaceSelector: {}
```

With this, the `release: kube-prometheus-stack` label on the ServiceMonitor is no
longer needed. The current label-based approach is stricter and more explicit.

---

## 9. Is the service.instance.id Processor Needed?

The processor in question:

```yaml
processors:
  resource:
    attributes:
      - key: service.instance.id
        from_attribute: k8s.pod.name
        action: insert
```

### On the gateway — NO, do not add it

Adding this on the gateway would stamp the **gateway's own pod name** as
`service.instance.id` on application traces passing through. This would overwrite
the application pod's identity — incorrect behavior.

For metric differentiation, it is already redundant:
- `resource_to_telemetry_conversion` promotes `k8s.pod.name` → `k8s_pod_name` label
- Prometheus adds `instance: <pod-ip>:8889` automatically

### On the agent — implemented in collector-agent.tf

`service.instance.id` is an [OTel semantic convention](https://opentelemetry.io/docs/specs/semconv/resource/#service)
for uniquely identifying a service instance.

**When you need it:**
- Your services run multiple replicas and you want to know which specific pod
  handled a given request in Jaeger
- You want to spot per-pod anomalies (e.g. one pod has 10× more errors — bad node?)
- You want Jaeger's service dependency graph to show distinct nodes per pod

**When you can skip it:**
- Services are single-replica
- `k8s.pod.name` on individual spans is already enough for your debugging

The agent's `k8sattributes` processor already extracts `k8s.pod.name` — the
`resource` processor simply copies it into the standard `service.instance.id` field:

```hcl
# collector-agent.tf — resource processor (runs after k8sattributes)
resource = {
  attributes = [
    {
      key            = "service.instance.id"
      from_attribute = "k8s.pod.name"
      action         = "insert"   # only sets if not already present
    }
  ]
}
```

Inserted into all 3 agent pipelines (traces, metrics, logs) after `k8sattributes`:
```
memory_limiter → resourcedetection/eks → k8sattributes → resource → batch
```

Effect in Jaeger: each replica of a service appears as a distinct instance node,
making it easy to spot per-pod errors or latency outliers.

---

## 10. Useful PromQL Queries

```promql
# ── Collector health ──────────────────────────────────────────────────────

# Spans received by gateway per pod (per second over 5m)
sum by (instance) (rate(otelcol_receiver_accepted_spans_total[5m]))

# Spans dropped by tail sampling (should be low for error traces)
sum by (processor) (rate(otelcol_processor_dropped_spans_total[5m]))

# Exporter send queue depth (high = Jaeger backpressure)
otelcol_exporter_queue_size{exporter="otlp/jaeger"}

# ── Infrastructure metrics ───────────────────────────────────────────────

# Container CPU utilization per pod in telemetry namespace
container_cpu_utilization_ratio{k8s_namespace_name="telemetry"}

# Memory RSS per pod
container_memory_rss_bytes{k8s_namespace_name="telemetry"}

# ── Per-gateway-pod differentiation ─────────────────────────────────────

# See which gateway pod served which node's metrics
group by (instance, k8s_node_name) (container_cpu_time_seconds_total)

# Filter to a specific gateway pod only
container_memory_usage_bytes{instance="192.168.13.58:8889"}

# ── Verify both gateway pods are being scraped ───────────────────────────
# In Prometheus UI: Status → Targets → serviceMonitor/telemetry/otel-gateway/0
# Should show exactly 2 endpoints, both health=up
```

---

## Related Files

| File | Purpose |
|---|---|
| `modules/otel-operator/collector-agent.tf` | Agent DaemonSet config — kubeletstats, k8sattributes, loadbalancing exporter |
| `modules/otel-operator/collector-gateway.tf` | Gateway StatefulSet config — tail_sampling, prometheus exporter on :8889 |
| `modules/otel-operator/servicemonitor.tf` | ServiceMonitor CRD — tells Prometheus how to discover gateway |
| `modules/kube-prometheus/templates/values.yaml.tpl` | Helm values for kube-prometheus-stack (no serviceMonitorSelector needed — chart sets default) |
| `modules/kube-prometheus/main.tf` | Helm release for kube-prometheus-stack |
