# Metrics Pipeline

How metrics flow from sources to VictoriaMetrics and Grafana.

---

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Cluster Metrics Sources                                        │
│  • kube-state-metrics (pod/node/deployment state)               │
│  • node-exporter (CPU/memory/disk per node)                     │
│  • kubelet (container metrics via /metrics/cadvisor)            │
│  • API server, controller-manager, scheduler                    │
│  • MongoDB exporter (port http-metrics)                         │
│  • PostgreSQL / TimescaleDB exporter (port 9187)                │
└───────────────────────────┬─────────────────────────────────────┘
                            │  Prometheus scrape
                            ▼
                    ┌───────────────┐
                    │   VMAgent     │  scrapes all ServiceMonitors
                    │   (CRD)       │  in telemetry namespace
                    └───────┬───────┘
                            │  Prometheus remote-write
                            ▼
              ┌─────────────────────────────────┐
              │  VictoriaMetrics Cluster         │
              │  vminsert x3  ─────────────────► vmstorage x3  │
              │  (HAProxy-like, replication=2)                  │
              │  vmselect x3  ◄─────────────────               │
              └──────────┬──────────────────────┘
                         │  PromQL / MetricsQL
                         ▼
                     Grafana
              (kube-prometheus-stack)
```

Also:
- OTel Gateway pushes application metrics from SDKs directly to vminsert via `prometheusremotewrite` exporter.
- OTel Infra-Metrics collector scrapes DB/queue endpoints and pushes to vminsert.

---

## VMAgent Scrape Configuration (Staging)

### Kubernetes cluster metrics
Scraped automatically via ServiceMonitors registered by kube-prometheus-stack:
- `kube-state-metrics`
- `node-exporter`
- `kubelet` / `cadvisor`
- `apiserver`, `controller-manager`, `scheduler`, `proxy`

kube-prometheus-stack operator is scoped to the `telemetry` namespace (`kube_prometheus_operator_watch_namespaces = ["telemetry"]`) to avoid conflicts with other Prometheus operators in the cluster.

### MongoDB scraping

```hcl
mongodb_scrape_enabled         = true
mongodb_exporter_namespace      = ""               # all namespaces
mongodb_exporter_service_labels = {
  "app.kubernetes.io/component" = "metrics"
  "app.kubernetes.io/name"      = "mongodb"
}
mongodb_exporter_port = "http-metrics"
```

### PostgreSQL / TimescaleDB scraping

```hcl
postgres_scrape_enabled     = true
postgres_exporter_namespace = ""    # all namespaces
postgres_exporter_label_key = "pg-exporter-service"
postgres_exporter_port      = 9187
```

---

## VictoriaMetrics Cluster Topology (Staging)

| Component | Replicas | Role |
|-----------|----------|------|
| vminsert | 3 (HPA 3–6) | Receives remote-write, distributes to vmstorage |
| vmstorage | 3 | Stores time-series data (100 Gi gp3 each) |
| vmselect | 3 (HPA 3–6) | Serves PromQL/MetricsQL queries |

- Replication factor: **2** (each series stored on 2 of 3 vmstorage nodes)
- Retention: **7 days** (`vm_retention_period = "7d"`)
- Storage class: `vm-storage-gp3` (EBS gp3, created by Terraform)
- vmselect cache: 20 Gi per pod

---

## VictoriaMetrics Alerting

VMAlert evaluates alerting rules against vmselect and fires to Alertmanager:

```
VMAlert → kube-prometheus-stack-alertmanager.telemetry.svc.cluster.local:9093
```

VMAlert is enabled in staging (`vmalert_enabled = true`) for rule validation before production.

---

## Grafana Datasources

Grafana (kube-prometheus-stack) has two pre-configured datasources:

| Name | URL | Type |
|------|-----|------|
| VictoriaMetrics | `http://vmselect-victoria-metrics.telemetry.svc.cluster.local:8481/select/0/prometheus` | Prometheus-compatible |
| Jaeger | `http://jaeger-query.telemetry.svc.cluster.local:16686` | Jaeger |

Access Grafana: https://grafana.test.intangles.com

---

## VMBackup (S3)

VictoriaMetrics data is backed up to S3:
- IAM role created via IRSA (no static credentials)
- Backup bucket output as `vm_backup_s3_bucket` after apply
- Backup schedule and retention configured in the `victoria-metrics` module

---

## OTel Gateway → VictoriaMetrics

Application metrics collected by the OTel SDK are pushed by the Gateway to vminsert:

```yaml
# Gateway config (simplified)
exporters:
  prometheusremotewrite/vm:
    endpoint: http://vminsert-victoria-metrics.telemetry.svc.cluster.local:8480/insert/0/prometheus/api/v1/write
```

This feeds application-level metrics (latency, error rates, custom counters) into the same Grafana instance as infrastructure metrics.

---

## Querying Metrics

### Grafana
https://grafana.test.intangles.com — use the VictoriaMetrics datasource.

### VictoriaMetrics UI (vmui)
https://vm.test.intangles.com — direct MetricsQL/PromQL interface.

### Direct API
```bash
# Query via vmselect (internal)
curl 'http://vmselect-victoria-metrics.telemetry.svc.cluster.local:8481/select/0/prometheus/api/v1/query?query=up'

# Send metrics via vminsert (internal)
curl -X POST \
  'http://vminsert-victoria-metrics.telemetry.svc.cluster.local:8480/insert/0/prometheus/api/v1/write' \
  --data-binary @metrics.bin
```
