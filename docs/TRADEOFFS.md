# Design Decisions & Tradeoffs

Key architectural choices made in this stack and the reasoning behind them.

---

## OTel Operator (Agent + Gateway) vs Standalone Collector

**Chosen**: OTel Operator managing Agent DaemonSet + Gateway StatefulSet.

| | OTel Operator (current) | Standalone Collector |
|-|------------------------|---------------------|
| Agent placement | 1 pod per node (DaemonSet) — zero cross-node network hops for trace data | Single Deployment — all pods send to central collector across nodes |
| Tail sampling | Gateway StatefulSet with consistent hashing — all spans for a trace reach the same pod | Stateless Deployment — spans may spread across pods, breaking tail sampling |
| Auto-instrumentation | Operator manages Instrumentation CRD — no SDK code changes needed | Manual SDK configuration per service |
| Upgrade path | CRD-driven — just change image tags in variables | Redeploy Deployment |
| Complexity | Higher (Operator + CRDs + RBAC) | Lower (single Deployment) |

**Decision**: Tail sampling correctness and auto-instrumentation support justify the added complexity.

---

## Gateway as StatefulSet vs Deployment

**Chosen**: StatefulSet with headless service.

Tail sampling buffers all spans for a trace in memory until the decision wait expires. If spans for the same trace land on different pods, they cannot be sampled together.

A headless StatefulSet + consistent hashing ensures all spans with the same `traceID` route to the same pod. A Deployment with random load balancing would break this guarantee.

**Minimum 2 pods** is enforced in `variables.tf` validation:
```hcl
condition = var.gateway_min_replicas >= 2
```
This prevents SPOF on a single tail-sampling pod.

---

## VictoriaMetrics vs Prometheus (Standalone)

**Chosen**: VictoriaMetrics cluster.

| | VictoriaMetrics | Prometheus (standalone) |
|-|-----------------|------------------------|
| Storage efficiency | ~7× better compression | Baseline |
| High availability | VMCluster with replication factor 2 | Single Prometheus = SPOF |
| Horizontal scaling | vminsert/vmselect scale independently | Limited (sharding complex) |
| Remote write | Native, optimised | Supported but heavier |
| Long-term retention | Efficient at scale | Requires Thanos/Cortex for HA+LTR |

kube-prometheus-stack is still deployed for its CRDs (ServiceMonitor, PodMonitor, PrometheusRule) and Alertmanager. Prometheus itself is optional — VMAgent handles scraping.

---

## Elasticsearch Node Role Separation (Staging)

**Chosen**: Dedicated master / data / coordinating roles.

| Setup | Master | Data | Coordinating | Fault tolerance |
|-------|--------|------|-------------|----------------|
| All-in-one (dev) | any 1 of N | any 1 of N | any 1 of N | Low |
| **Dedicated roles (staging)** | 3 dedicated | 2 dedicated | 2 dedicated | Master: quorum in 3, data: 1 failure |

Dedicating master nodes prevents data-heavy operations from destabilising cluster state. Coordinating nodes absorb query fan-out, protecting data nodes.

A 2-node all-in-one setup (quorum=2) means **zero fault tolerance** — if one node is upgraded or fails, the cluster goes red. Never use 2-node in anything above dev.

---

## `kubectl_manifest` vs `kubernetes_manifest`

**Chosen**: `gavinbunney/kubectl` for CRD-backed resources.

`hashicorp/kubernetes_manifest` validates every managed resource against the live API server at **plan time**. This means:
- Fresh cluster with no CRDs installed → plan fails
- Destroy + reapply with `-target` → plan fails because OTel CRDs no longer exist

`kubectl_manifest` skips plan-time validation, matches `kubectl apply` behaviour. All OTel resources (OpenTelemetryCollector, Instrumentation, ServiceMonitor) use `kubectl_manifest`.

---

## Jaeger `es.create-index-templates: false`

Jaeger's built-in index templates create `text` fields for `serviceName`, `operationName`, `traceID`, `spanID` **without** `fielddata:true`. ES 8.x blocks `terms` aggregations on such fields (required for `/api/services` and span filter dropdowns).

**Fix**: Register priority-100 templates with `fielddata:true` via the ILM job, and disable Jaeger's own template creation to prevent override.

---

## kube-prometheus Namespace Scoping

`kube_prometheus_operator_watch_namespaces = ["telemetry"]` restricts the operator to the `telemetry` namespace. This avoids CRD conflicts with an older Prometheus Operator already running in the `observability` namespace of the cluster.

Without scoping, two operators would both watch all namespaces and could process each other's CRD resources, causing reconciliation loops.

---

## Tail Sampling Decision Wait (30 s)

30 seconds is chosen to accommodate async queue-based architectures where a parent span (received immediately) must wait for child spans from slow consumers. Shorter waits (5–10 s) cause incomplete traces.

The tradeoff is higher memory usage on Gateway pods (30 s × throughput × avg spans/trace buffered in memory per pod). The `tail_sampling_num_traces` variable limits the buffer ceiling.
