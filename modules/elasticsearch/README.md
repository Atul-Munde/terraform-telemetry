# Elasticsearch Module

Deploys an Elasticsearch cluster (single-role all-in-one) via Helm chart.  
Used as the storage backend for Jaeger traces and optionally for application logs.

After every `terraform apply` an ILM setup Job runs to:
- Register index lifecycle policies (configurable per prefix + a global policy)
- Register index templates that apply the ILM policy to matching indices
- Register Jaeger fielddata override templates (`jaeger-service-override`, `jaeger-span-override`,
  both at priority 100) so ES 8.x `terms` aggregations work on Jaeger indices

## Usage

```hcl
module "elasticsearch" {
  source = "./modules/elasticsearch"

  namespace     = "telemetry"
  environment   = "staging"
  replicas      = 3
  storage_size  = "100Gi"
  storage_class = "gp3"
  elastic_password = var.elastic_password   # via TF_VAR_elastic_password

  resources = {
    requests = { cpu = "1000m", memory = "2Gi" }
    limits   = { cpu = "2000m", memory = "4Gi" }
  }

  retention_days = 7
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Kubernetes namespace | string | — |
| `environment` | Environment name (dev/staging/production) | string | — |
| `replicas` | Number of Elasticsearch nodes | number | `3` |
| `storage_size` | PVC size per node | string | `"100Gi"` |
| `storage_class` | StorageClass name (empty = cluster default) | string | `""` |
| `resources` | CPU/memory requests and limits per pod | object | see variables.tf |
| `retention_days` | Global index retention in days | number | `7` |
| `elastic_password` | `elastic` superuser password — use `TF_VAR_elastic_password` | string | `""` |
| `node_selector` | Pod node selector labels | map(string) | `{}` |
| `tolerations` | Pod tolerations | list | `[]` |
| `labels` | Extra labels applied to all resources | map(string) | `{}` |
| `custom_ilm_policies` | Map of index prefix → retention days | map(number) | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `endpoint` | HTTPS endpoint URL (`https://elasticsearch-master.<namespace>.svc.cluster.local:9200`) |
| `service_name` | Kubernetes Service name (`elasticsearch-master`) |

## Security

- **xpack.security is enabled automatically** when `elastic_password` is non-empty (the module sets `xpack_security_enabled = true` in Helm values).
- Credentials are stored in a Kubernetes Secret and never written to Helm values or tfvars.
- All connections use HTTPS (`https://elasticsearch-master.<namespace>.svc.cluster.local:9200`).
- Always supply the password via `TF_VAR_elastic_password` — never commit it.

## ILM / Index Templates

The ILM setup Job runs as a post-install Kubernetes Job on every apply.  
It registers:

1. **Global ILM policy** — applies to all `telemetry-*` indices, deletes after `retention_days`
2. **Per-prefix policies** — from `custom_ilm_policies` map
3. **`jaeger-service-override`** (priority 100) — sets `fielddata:true` on `serviceName`, `operationName`  
4. **`jaeger-span-override`** (priority 100) — sets `fielddata:true` on `serviceName`, `operationName`, `traceID`, `spanID`, `process.serviceName`

These override Jaeger's default templates (which use bare `text` fields) and prevent the  
"all shards failed" error that occurs when ES 8.x attempts aggregations on `text` fields  
without `fielddata:true`.
