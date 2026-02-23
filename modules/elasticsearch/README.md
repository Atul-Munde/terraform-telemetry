# Elasticsearch Module

Deploys Elasticsearch cluster using Helm chart for trace storage backend.

## Usage

```hcl
module "elasticsearch" {
  source = "./modules/elasticsearch"

  namespace      = "observability"
  environment    = "production"
  replicas       = 3
  storage_size   = "200Gi"
  storage_class  = "gp3"
  
  resources = {
    requests = { cpu = "1000m", memory = "2Gi" }
    limits   = { cpu = "2000m", memory = "4Gi" }
  }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| namespace | Kubernetes namespace | string | - |
| environment | Environment name | string | "dev" |
| replicas | Number of ES nodes | number | 3 |
| storage_size | PVC storage size | string | "50Gi" |
| storage_class | Storage class name | string | "" |
| resources | CPU/Memory requests and limits | object | See variables.tf |
| retention_days | Data retention in days | number | 7 |
| node_selector | Node selector labels | map(string) | {} |
| tolerations | Pod tolerations | list | [] |

## Outputs

| Name | Description |
|------|-------------|
| endpoint | Elasticsearch endpoint URL |
| service_name | Kubernetes service name |

## Security Notes

- xpack.security is disabled by default for internal clusters
- Enable authentication for production use with external access
- Consider using Kubernetes secrets for credentials
