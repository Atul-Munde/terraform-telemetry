# VictoriaMetrics Module

Deploys a **VictoriaMetrics cluster** using the VictoriaMetrics Operator:

- **VM Operator** — Helm chart `victoria-metrics-operator` 0.59.1
- **VMCluster** — `vmstorage` (StatefulSet) + `vminsert` (Deployment) + `vmselect` (Deployment)
- **VMAgent** — scrapes cluster metrics, databases, and custom targets; writes to VMCluster
- **VMAlert** — evaluates alerting rules; fires to Alertmanager
- **VMAuth** — optional auth proxy (disabled by default)
- **HPA** — auto-scales vminsert and vmselect on CPU
- **S3 backup** — optional VMBackup via IRSA (no static credentials)
- **StorageClass** — creates `vm-storage-gp3` EBS gp3 class (toggleable)

## Usage

```hcl
module "victoria_metrics" {
  source = "./modules/victoria-metrics"
  count  = var.victoria_metrics_enabled ? 1 : 0

  namespace   = "telemetry"
  environment = "staging"

  vm_operator_chart_version = "0.59.1"
  vm_cluster_name           = "victoria-metrics"

  # Cluster topology
  vmstorage_replicas    = 3
  vminsert_replicas     = 3
  vmselect_replicas     = 3
  replication_factor    = 2
  retention_period      = "7d"

  # Storage
  vmstorage_storage_size    = "100Gi"
  vmselect_cache_storage_size = "20Gi"
  storage_class_name        = "vm-storage-gp3"
  create_storage_class      = true

  # HPA
  vminsert_min_replicas = 3
  vminsert_max_replicas = 6
  vmselect_min_replicas = 3
  vmselect_max_replicas = 6

  # VMAgent
  vmagent_enabled = true

  # VMAlert
  vmalert_enabled  = true
  alertmanager_url = "http://kube-prometheus-stack-alertmanager.telemetry.svc.cluster.local:9093"

  # DB scraping
  mongodb_scrape_enabled          = true
  mongodb_exporter_service_labels = { "app.kubernetes.io/name" = "mongodb" }
  mongodb_exporter_port           = "http-metrics"

  postgres_scrape_enabled     = true
  postgres_exporter_label_key = "pg-exporter-service"
  postgres_exporter_port      = 9187

  # Ingress
  vm_create_ingress     = true
  vmselect_ingress_host = "vm.test.intangles.com"
  alb_certificate_arn   = "arn:aws:acm:ap-south-1:..."
  alb_group_name        = "intangles-ingress"
}
```

## Inputs

### VM Operator

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Kubernetes namespace | string | `"telemetry"` |
| `environment` | Environment name | string | — |
| `vm_operator_chart_version` | Helm chart version for vm-operator | string | `"0.59.1"` |
| `vm_operator_namespace` | Namespace for the Operator controller pod | string | `"victoria-metrics-operator-system"` |
| `vm_operator_replicas` | Operator replicas | number | `1` |
| `vm_cluster_name` | VMCluster CR name (derived into service names) | string | `"vmcluster"` |

### VMCluster Topology

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vmstorage_replicas` | vmstorage StatefulSet replicas (>= 2×replication_factor − 1) | number | `3` |
| `vminsert_replicas` | Baseline vminsert replicas | number | `3` |
| `vmselect_replicas` | Baseline vmselect replicas | number | `3` |
| `replication_factor` | Copies per written sample | number | `2` |
| `retention_period` | Data retention (e.g. `"7d"`, `"1M"`) | string | `"7d"` |

### Storage

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vmstorage_storage_size` | PVC size per vmstorage pod | string | `"100Gi"` |
| `vmselect_cache_storage_size` | PVC size for vmselect query cache | string | `"20Gi"` |
| `storage_class_name` | StorageClass name | string | `"vm-storage-gp3"` |
| `create_storage_class` | Create the StorageClass (disable if pre-existing) | bool | `true` |

### HPA

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vminsert_min_replicas` | HPA min for vminsert | number | `3` |
| `vminsert_max_replicas` | HPA max for vminsert | number | `10` |
| `vmselect_min_replicas` | HPA min for vmselect | number | `3` |
| `vmselect_max_replicas` | HPA max for vmselect | number | `10` |

### VMAgent / VMAlert

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vmagent_enabled` | Deploy VMAgent | bool | `true` |
| `vmalert_enabled` | Deploy VMAlert | bool | `false` |
| `alertmanager_url` | Alertmanager URL for VMAlert | string | `""` |

### DB Scraping

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `mongodb_scrape_enabled` | Scrape MongoDB exporters | bool | `false` |
| `mongodb_exporter_namespace` | Namespace to restrict to (empty = all) | string | `""` |
| `mongodb_exporter_service_labels` | Label selectors for MongoDB Services | map(string) | `{}` |
| `mongodb_exporter_port` | Named port on MongoDB exporter Service | string | `"http-metrics"` |
| `postgres_scrape_enabled` | Scrape PostgreSQL exporters | bool | `false` |
| `postgres_exporter_namespace` | Namespace to restrict to (empty = all) | string | `""` |
| `postgres_exporter_label_key` | Label key present on all postgres-exporter Services | string | `"pg-exporter-service"` |
| `postgres_exporter_port` | Metrics port on postgres-exporter | number | `9187` |
| `scylladb_scrape_enabled` | Scrape ScyllaDB native metrics | bool | `false` |
| `redis_scrape_enabled` | Scrape redis-exporter | bool | `false` |

### Backup

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `backup_enabled` | Create S3 bucket and CronJob vmbackup | bool | `false` |
| `backup_schedule` | Backup cron expression | string | `"0 2 * * *"` |
| `backup_s3_bucket_name` | S3 bucket name (empty = auto-generated) | string | `""` |
| `backup_s3_region` | AWS region for S3 | string | `"ap-south-1"` |
| `backup_retention_days` | S3 lifecycle expiry for backups | number | `30` |
| `eks_oidc_provider_arn` | EKS OIDC ARN for IRSA trust policy | string | `""` |

### Ingress

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vm_create_ingress` | Create ALB Ingress for vmselect UI | bool | `false` |
| `vmselect_ingress_host` | Public hostname | string | `""` |
| `alb_certificate_arn` | ACM cert ARN | string | `""` |
| `alb_group_name` | ALB IngressGroup name | string | `""` |
| `vm_ingress_class_name` | IngressClass | string | `"alb"` |

## Outputs

| Name | Description |
|------|-------------|
| `vminsert_endpoint` | Internal URL for Prometheus remote-write to vminsert |
| `vmselect_endpoint` | Internal URL for PromQL queries from vmselect |
| `prometheus_remote_write_url` | Full remote-write URL (`/insert/0/prometheus/api/v1/write`) |
| `grafana_datasource_url` | Grafana Prometheus-compatible datasource URL (`/select/0/prometheus`) |
| `vmselect_ui_url` | Public VMUI URL (when `create_ingress=true`) |
| `vmauth_url` | Internal VMAuth URL (when `vmauth_enabled=true`) |
| `backup_s3_bucket` | S3 bucket name (when `backup_enabled=true`) |
| `backup_s3_bucket_arn` | S3 bucket ARN (when `backup_enabled=true`) |
| `vmbackup_iam_role_arn` | IRSA role ARN for vmbackup (when `backup_enabled=true`) |
| `storage_class_name` | StorageClass used for vmstorage PVCs |
| `vmcluster_name` | VMCluster CR name |
| `namespace` | Deployed namespace |

## Architecture

```
┌────────────────────────── VMCluster ──────────────────────────────┐
│                                                                   │
│  vminsert x3 (HPA 3-6) ─────────────────► vmstorage x3          │
│  receives remote-write                     StatefulSet            │
│  routes with replication=2                 100 Gi gp3 each        │
│                                                                   │
│  vmselect x3 (HPA 3-6) ◄─────────────────────────────────────── │
│  serves PromQL / MetricsQL queries                                │
└───────────────────────────────────────────────────────────────────┘
         ▲                               ▲
         │ remote-write                  │ PromQL
   VMAgent scrapes               Grafana / VMAlert
   cluster + DBs
```

## Replication

With `replication_factor = 2` and `vmstorage_replicas = 3`:
- Each written sample is stored on 2 of 3 vmstorage nodes
- The cluster can survive 1 vmstorage node failure without data loss
- vminsert routes writes using consistent hashing across all vmstorage nodes

## Backup

VMBackup accesses S3 using a Kubernetes ServiceAccount with an IAM role attached via IRSA  
(no AWS credentials stored as Secrets). The IAM role is created by this module when  
`backup_enabled = true` and `eks_oidc_provider_arn` is provided.

Backup bucket name is output as `backup_s3_bucket` after apply.
