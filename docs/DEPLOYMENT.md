# Deployment Guide

Deploying the telemetry stack to `intangles-qa-cluster` (`ap-south-1`).

---

## Prerequisites

- Terraform >= 1.5
- `kubectl` configured: `aws eks update-kubeconfig --region ap-south-1 --name intangles-qa-cluster --profile mum-test`
- Helm >= 3.12
- AWS profile `mum-test` with EKS + S3 + IAM permissions

---

## Deploy (Staging)

```bash
cd /path/to/otel_terrform/environments/staging

# 1. Init Terraform (first time or after provider changes)
terraform init \
  -backend-config="bucket=intangles-tf-state" \
  -backend-config="key=staging/telemetry.tfstate" \
  -backend-config="region=ap-south-1"

# 2. Plan
terraform plan \
  -var="elastic_password=<password>" \
  -var="kibana_encryption_key=<32-char-key>"

# 3. Apply
TF_VAR_elastic_password='<password>' \
TF_VAR_kibana_encryption_key='<32-char-key>' \
terraform apply -auto-approve
```

> The `kibana_encryption_key` must be exactly 32 characters.  
> Never commit credentials to `terraform.tfvars`.

---

## Apply Script (if using .tf_apply.sh)

From the workspace root:

```bash
TF_VAR_elastic_password='<password>' \
TF_VAR_kibana_encryption_key='<32-char-key>' \
zsh .tf_apply.sh -auto-approve
```

---

## Verify Deployment

```bash
# All pods
kubectl get pods -n telemetry

# OTel Agent DaemonSet (1 per node)
kubectl get pods -n telemetry -l app.kubernetes.io/name=otel-agent-collector

# OTel Gateway StatefulSet (min 2)
kubectl get pods -n telemetry -l app.kubernetes.io/name=otel-gateway-collector

# Elasticsearch — dedicated roles
kubectl get pods -n telemetry -l chart=elasticsearch

# Jaeger
kubectl get pods -n telemetry -l app.kubernetes.io/name=jaeger

# VictoriaMetrics
kubectl get pods -n telemetry | grep -E "vminsert|vmselect|vmstorage|vmagent|vmalert"

# Kibana
kubectl get pods -n telemetry -l app=kibana
```

Expected state after a healthy apply:

| Pod pattern | Expected count |
|-------------|---------------|
| `otel-agent-collector-*` | 1 per node |
| `otel-gateway-collector-*` | 2–8 |
| `otel-infra-metrics-*` | 1 |
| `elasticsearch-master-*` | 3 |
| `elasticsearch-data-*` | 2 |
| `elasticsearch-coordinating-*` | 2 |
| `kibana-*` | 1 |
| `jaeger-query-*` | 2 |
| `jaeger-collector-*` | 2 |
| `vminsert-*` | 3 |
| `vmselect-*` | 3 |
| `vmstorage-*` | 3 |
| `vmagent-*` | 1 |
| `vmalert-*` | 1 |

---

## Targeted Module Redeploy

To destroy and redeploy a specific module:

```bash
# Redeploy Kibana
terraform destroy -target='module.telemetry.module.kibana[0]' -auto-approve
TF_VAR_elastic_password='...' TF_VAR_kibana_encryption_key='...' terraform apply -auto-approve

# Redeploy OTel Operator
terraform destroy -target='module.telemetry.module.otel_operator[0]' -auto-approve
terraform apply -auto-approve
```

---

## Destroying the Stack

```bash
TF_VAR_elastic_password='<password>' \
TF_VAR_kibana_encryption_key='<32-char-key>' \
terraform destroy -auto-approve
```

> Note: PVCs (Elasticsearch, VictoriaMetrics) are not automatically deleted. Delete them manually if unused:
> ```bash
> kubectl delete pvc -n telemetry --all
> ```

---

## Outputs After Apply

Key outputs printed after a successful apply:

```
otel_agent_grpc_endpoint     = "otel-agent-collector.telemetry.svc.cluster.local:4317"
otel_agent_http_endpoint     = "http://otel-agent-collector.telemetry.svc.cluster.local:4318"
vm_prometheus_remote_write_url = "http://vminsert-victoria-metrics.telemetry.svc.cluster.local:8480/insert/0/prometheus/api/v1/write"
kibana_url                   = "https://kibana.test.intangles.com"
jaeger_url                   = "https://jaeger.test.intangles.com"
grafana_url                  = "https://grafana.test.intangles.com"
vm_ui_url                    = "https://vm.test.intangles.com"
```

---

## Upgrading Chart Versions

Update the relevant variable in `environments/staging/terraform.tfvars`:

```hcl
jaeger_chart_version        = "2.0.0"
kibana_chart_version        = "8.5.1"
otel_operator_chart_version = "0.66.0"
vm_operator_chart_version   = "<new-version>"
```

Then `terraform apply`. Helm will upgrade the release in-place.

---

## Adding New Nodes for OTel Agent Coverage

The Agent DaemonSet uses nodeSelector `otel-agent=true`. Label new nodes:

```bash
kubectl label node <node-name> otel-agent=true
```

The DaemonSet will automatically schedule an Agent pod on the new node.
