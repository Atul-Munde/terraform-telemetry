# Kibana Module

Deploys Kibana via Helm chart (version must match the Elasticsearch chart version).  
Kibana connects to Elasticsearch using the `elastic` superuser over HTTPS.  
Credentials are stored in a Kubernetes Secret — never written to Helm values.

## Usage

```hcl
module "kibana" {
  source = "./modules/kibana"

  namespace              = "telemetry"
  environment            = "staging"
  chart_version          = "8.5.1"   # must match ES chart version
  elasticsearch_host     = "https://elasticsearch-master.telemetry.svc.cluster.local:9200"
  elastic_password       = var.elastic_password
  kibana_encryption_key  = var.kibana_encryption_key

  replicas      = 1
  storage_class = "gp3"
  storage_size  = "5Gi"

  create_ingress      = true
  ingress_host        = "kibana.test.intangles.com"
  alb_certificate_arn = "arn:aws:acm:ap-south-1:..."
  alb_group_name      = "intangles-ingress"
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Kubernetes namespace | string | — |
| `environment` | Environment name | string | — |
| `chart_version` | Kibana Helm chart version — must match ES | string | `"8.5.1"` |
| `replicas` | Number of Kibana replicas | number | `2` |
| `resources` | CPU/memory requests and limits | object | see variables.tf |
| `elasticsearch_host` | Full HTTPS URL to ES (includes `https://` and port) | string | — |
| `elastic_password` | ES `elastic` superuser password — use `TF_VAR_elastic_password` | string | — |
| `kibana_encryption_key` | 32-character key for `xpack.encryptedSavedObjects.encryptionKey` | string | — |
| `storage_class` | StorageClass for Kibana PVC | string | `""` |
| `storage_size` | PVC size for saved objects | string | `"5Gi"` |
| `log_level` | Kibana log level | string | `"warn"` |
| `base_path` | Server base path (e.g. `/kibana`) — empty for root | string | `""` |
| `node_selector` | Pod node selector | map(string) | `{}` |
| `tolerations` | Pod tolerations | list | `[]` |
| `labels` | Extra resource labels | map(string) | `{}` |
| `create_ingress` | Create AWS ALB Ingress | bool | `false` |
| `ingress_host` | FQDN for the Kibana ALB listener | string | `""` |
| `alb_certificate_arn` | ACM certificate ARN for HTTPS | string | `""` |
| `alb_group_name` | ALB IngressGroup name (shared ALB) | string | `""` |
| `ingress_class_name` | IngressClass name | string | `"alb"` |

## Outputs

| Name | Description |
|------|-------------|
| `endpoint` | Internal host:port (`kibana-kibana.<ns>.svc.cluster.local:5601`) |
| `connection_url` | Internal HTTP URL |
| `public_url` | Public HTTPS URL when `create_ingress=true`, otherwise internal URL |
| `service_name` | Kubernetes Service name (`kibana-kibana`) |
| `helm_release_name` | Helm release name |

## Credentials & Security

- `elastic_password` and `kibana_encryption_key` are stored in a `kibana-credentials` Kubernetes Secret.
- Helm values reference the secret via `valueFrom` — credentials never appear in `helm get values`.
- The `kibana_encryption_key` must be **exactly 32 characters** or Kibana will refuse to start.
- The chart version must match the Elasticsearch chart version to avoid version incompatibility errors.
- Supply credentials via `TF_VAR_elastic_password` and `TF_VAR_kibana_encryption_key` — never commit to tfvars.

## Heap Sizing

Node.js heap is auto-calculated as 50% of the memory limit (mirrors the Elasticsearch heap convention).  
Example: `limits.memory = "2Gi"` → `NODE_OPTIONS="--max-old-space-size=1024"`.

## ALB Ingress

When `create_ingress = true`, the module creates an internet-facing ALB Ingress:
- HTTPS-only (port 443, SSL redirect from 80)
- Target type: IP
- Health check path: `/api/status`
- Joins shared ALB when `alb_group_name` is set

## Troubleshooting

### Pre-install hook stuck

If you see `kibana-kibana-helm-scripts` ConfigMap blocking a redeploy:

```bash
kubectl delete configmap  -n telemetry kibana-kibana-helm-scripts
kubectl delete secret     -n telemetry sh.helm.release.v1.kibana.v1
kubectl delete secret     -n telemetry kibana-kibana-es-token
terraform destroy -target='module.telemetry.module.kibana[0]'
```
