# Elasticsearch Module

Deploys a **production-grade HA Elasticsearch cluster** on Kubernetes using the
Elastic Helm chart (v8.5.1). The cluster uses **dedicated node roles** — three
separate Helm releases for master, data+ingest, and coordinating nodes.

## Architecture

```
                     ┌──────────────────────────┐
                     │   Consumers (Jaeger,      │
                     │   Kibana, OTel Gateway)   │
                     └──────────┬───────────────┘
                                │ HTTPS :9200
                     ┌──────────▼───────────────┐
                     │  Coordinating Nodes (2+)  │
                     │  roles: []  (stateless)   │
                     └──────────┬───────────────┘
                                │
                 ┌──────────────┴──────────────┐
                 │                             │
      ┌──────────▼──────────┐      ┌───────────▼─────────┐
      │  Master Nodes (3)   │      │  Data+Ingest Nodes  │
      │  roles: [master]    │      │  roles: [data,      │
      │  quorum: 2          │      │   data_content,     │
      │  cluster state only │      │   data_hot, ingest] │
      └─────────────────────┘      └─────────────────────┘
```

**Key design decisions:**
- All consumers connect through **coordinating nodes** (stateless scatter-gather)
- Master nodes are lightweight — cluster state and shard allocation only
- Data + ingest roles combined to keep pod count manageable
- Hard anti-affinity on master/data ensures one pod per K8s node
- `topologySpreadConstraints` distribute pods evenly across hosts

## Usage

```hcl
module "elasticsearch" {
  source = "./modules/elasticsearch"

  namespace    = "telemetry"
  environment  = "production"
  cluster_name = "elasticsearch"
  anti_affinity = "hard"
  storage_class = "gp3"

  node_roles = {
    master = {
      replicas     = 3
      storage_size = "10Gi"
      resources = {
        requests = { cpu = "500m",  memory = "1Gi" }
        limits   = { cpu = "1000m", memory = "2Gi" }
      }
    }
    data = {
      replicas     = 3
      storage_size = "200Gi"
      resources = {
        requests = { cpu = "2000m", memory = "4Gi" }
        limits   = { cpu = "4000m", memory = "8Gi" }
      }
    }
    coordinating = {
      replicas = 2
      resources = {
        requests = { cpu = "1000m", memory = "2Gi" }
        limits   = { cpu = "2000m", memory = "4Gi" }
      }
    }
  }

  elastic_password    = var.elastic_password   # via TF_VAR_elastic_password
  retention_days      = 14
  custom_ilm_policies = {
    "jaeger-span"    = 7
    "jaeger-service" = 30
  }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| namespace | Kubernetes namespace | `string` | — (required) |
| environment | Environment name | `string` | — (required) |
| cluster_name | ES cluster name / Helm release prefix | `string` | `"elasticsearch"` |
| node_roles | Per-role replicas, storage, resources | `object(...)` | See variables.tf |
| anti_affinity | Master/data anti-affinity: `"hard"` or `"soft"` | `string` | `"hard"` |
| storage_class | StorageClass for PVCs | `string` | `""` |
| elastic_password | `elastic` superuser password (sensitive) | `string` | `""` |
| retention_days | Global ILM retention days | `number` | `7` |
| custom_ilm_policies | Map of index prefix → retention days | `map(number)` | `{}` |
| node_selector | Node selector for scheduling | `map(string)` | `{}` |
| tolerations | Pod tolerations | `list(object)` | `[]` |

## Outputs

| Name | Description |
|------|-------------|
| endpoint | Coordinating node endpoint (`<cluster>-coordinating.<ns>.svc:9200`) |
| connection_url | Full URL with protocol (https/http based on security) |
| service_name | Coordinating service name |
| master_endpoint | Master node endpoint (internal use only) |
| cluster_name | Elasticsearch cluster name |
| helm_release_names | Map of all three Helm release names |

## Security

- **X-Pack security** enabled when `elastic_password` is set (non-empty)
- Credentials stored in `elasticsearch-credentials` K8s Secret
- HTTP TLS disabled (terminated at ALB/load balancer)
- Transport TLS disabled (pod-to-pod — consider enabling for sensitive data)
- `lifecycle { prevent_destroy = true }` on master + data releases prevents accidental deletion

## ILM (Index Lifecycle Management)

A Kubernetes Job runs after all node groups are ready and configures:
- A **global ILM policy** with `retention_days` day delete phase
- A **global index template** (priority 99) applying the global policy to `*`
- **Per-prefix ILM policies** and templates (priority 200) from `custom_ilm_policies`

The Job name includes a hash of the ILM config, so policy changes trigger automatic re-creation.
