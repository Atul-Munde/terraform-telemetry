# Production-Grade OpenTelemetry Collector & Jaeger on Kubernetes

A complete Terraform-based infrastructure-as-code solution for deploying OpenTelemetry Collector and Jaeger distributed tracing on Kubernetes.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐      ┌──────────────────┐            │
│  │   Microservice   │─────▶│   OTel Collector │            │
│  │   +OTLP Client   │      │   (Deployment)   │            │
│  └──────────────────┘      │   - Batch/Retry  │            │
│                             │   - Sampling     │            │
│  ┌──────────────────┐      │   - HPA Enabled  │            │
│  │   Microservice   │─────▶│                  │            │
│  │   +OTLP Client   │      └─────────┬────────┘            │
│  └──────────────────┘                │                      │
│                                       │                      │
│                                       ▼                      │
│                          ┌────────────────────┐             │
│                          │  Jaeger Collector  │             │
│                          └─────────┬──────────┘             │
│                                    │                         │
│                                    ▼                         │
│                          ┌────────────────────┐             │
│                          │  Elasticsearch     │             │
│                          │  (StatefulSet)     │             │
│                          └─────────┬──────────┘             │
│                                    │                         │
│                                    ▼                         │
│                          ┌────────────────────┐             │
│                          │   Jaeger Query     │             │
│                          │   (UI + API)       │             │
│                          └────────────────────┘             │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Features

### ✅ Production-Ready
- **High Availability**: Multiple replicas with PodDisruptionBudgets
- **Auto-Scaling**: HPA for OTel Collector based on CPU/Memory
- **Health Monitoring**: Liveness and readiness probes
- **Graceful Updates**: Rolling update strategies
- **Resource Management**: Proper requests and limits

### ✅ Security
- **RBAC**: ServiceAccounts with least-privilege roles
- **Secrets Management**: Kubernetes secrets for credentials
- **Network Policies**: (Optional) Namespace isolation
- **TLS**: Support for secure communication

### ✅ Scalability
- **Horizontal Scaling**: OTel Collector with HPA
- **Batching & Buffering**: Optimized telemetry pipelines
- **Storage Backend**: Elasticsearch via Helm chart
- **Retention Policies**: Configurable data retention

### ✅ Infrastructure as Code
- **Terraform Modules**: Reusable, composable components
- **Environment Parity**: Consistent dev/staging/prod
- **Remote State**: S3 backend with state locking
- **Version Control**: Pinned provider versions

## Directory Structure

```
.
├── README.md
├── main.tf                      # Root module
├── variables.tf                 # Root variables
├── outputs.tf                   # Root outputs
├── versions.tf                  # Provider versions
├── backend.tf                   # Remote state configuration
├── terraform.tfvars.example     # Example variables
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   └── production/
│       ├── main.tf
│       └── terraform.tfvars
└── modules/
    ├── namespace/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── otel-collector/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   ├── configmap.tf
    │   ├── deployment.tf
    │   ├── service.tf
    │   └── hpa.tf
    ├── jaeger/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── elasticsearch/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Prerequisites

1. **Terraform** >= 1.5.0
2. **Kubernetes Cluster** (1.24+)
3. **kubectl** configured with cluster access
4. **Helm** >= 3.0 (for Jaeger charts)
5. **Storage Class** available in cluster (for Elasticsearch PVCs)

## Quick Start

### 1. Prerequisites Setup

**First-time setup requires:**

1. **AWS S3 Backend** (see [docs/SETUP.md](docs/SETUP.md) for details)
   ```bash
   # Create S3 bucket and DynamoDB table
   aws s3api create-bucket --bucket otel-terraform-state-setup \
     --region ap-south-1 --create-bucket-configuration LocationConstraint=ap-south-1
   
   aws dynamodb create-table --table-name terraform-state-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST --region ap-south-1
   ```

2. **Kubernetes Nodes** (label and taint for dedicated telemetry):
   ```bash
   # Label nodes
   kubectl label nodes <node-name> telemetry=true
   
   # Taint nodes (dedicate for telemetry only)
   kubectl taint nodes <node-name> telemetry=true:NoSchedule
   ```

3. **Storage Class** (verify gp3 exists):
   ```bash
   kubectl get storageclass gp3
   ```

### 2. Set Environment Variables

```bash
export KUBECONFIG=~/.kube/config
export TF_VAR_environment=dev
export AWS_REGION=ap-south-1  # For S3 backend
```

### 3. Initialize Terraform

```bash
cd environments/dev
terraform init
```

### 4. Review Plan

```bash
terraform plan
```

### 5. Apply Configuration

```bash
terraform apply
```

## Environment-Specific Deployments

### Development
```bash
cd environments/dev
terraform init
terraform apply
```

### Staging
```bash
cd environments/staging
terraform init
terraform apply
```

### Production
```bash
cd environments/production
terraform init
terraform apply
```

## Configuration

### Current Setup

**AWS Backend:**
- S3 Bucket: `otel-terraform-state-setup`
- Region: `ap-south-1` (Mumbai)
- DynamoDB: `terraform-state-lock`

**Kubernetes:**
- Namespace: `telemetry`
- Node Selector: `telemetry=true`
- Toleration: `telemetry=true:NoSchedule`
- Storage Class: `gp3` (AWS EBS)

### OpenTelemetry Collector

Key configuration options:

- **Receivers**: OTLP gRPC (4317), OTLP HTTP (4318)
- **Processors**: Batch, memory limiter, tail sampling
- **Exporters**: Jaeger, logging (for debugging)
- **Replicas**: 2-5 based on environment
- **HPA**: CPU/Memory based auto-scaling

### Jaeger

Deployed via Helm chart with:

- **Storage**: Elasticsearch backend
- **Components**: Collector, Query, Agent (optional)
- **UI Access**: ClusterIP (use port-forward or Ingress)
- **Retention**: Configurable span retention period

### Elasticsearch

- **Deployment**: StatefulSet for data persistence
- **Replicas**: 3 for production (HA)
- **Storage**: Persistent volumes (100Gi default)
- **Index Lifecycle**: Automatic rollover and deletion

## Accessing Services

### Jaeger UI

```bash
kubectl port-forward -n telemetry svc/jaeger-query 16686:16686
```

Then open: http://localhost:16686

### OpenTelemetry Collector Endpoints

From inside cluster:
- **OTLP gRPC**: `otel-collector.telemetry.svc.cluster.local:4317`
- **OTLP HTTP**: `otel-collector.telemetry.svc.cluster.local:4318`

### Elasticsearch

```bash
kubectl port-forward -n telemetry svc/elasticsearch 9200:9200
```

## Application Integration

### Example: Sending Traces to OTel Collector

**Go Application:**
```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
)

exporter, _ := otlptracegrpc.New(
    context.Background(),
    otlptracegrpc.WithEndpoint("otel-collector.telemetry.svc.cluster.local:4317"),
    otlptracegrpc.WithInsecure(),
)
```

**Python Application:**
```python
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

otlp_exporter = OTLPSpanExporter(
    endpoint="otel-collector.telemetry.svc.cluster.local:4317",
    insecure=True
)
```

**Environment Variables:**
```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.telemetry.svc.cluster.local:4318"
  - name: OTEL_SERVICE_NAME
    value: "my-service"
```

## Monitoring & Operations

### Check OTel Collector Status

```bash
kubectl get pods -n telemetry -l app=otel-collector
kubectl logs -n telemetry -l app=otel-collector --tail=100
```

### Check Jaeger Status

```bash
kubectl get pods -n telemetry -l app.kubernetes.io/name=jaeger
kubectl logs -n telemetry -l app.kubernetes.io/component=query
```

### Check Elasticsearch Health

```bash
kubectl exec -n telemetry elasticsearch-master-0 -- curl -s http://localhost:9200/_cluster/health?pretty
```

## Troubleshooting

### No Traces Appearing

1. Check OTel Collector logs
2. Verify Jaeger collector connectivity
3. Check Elasticsearch indices

### High Memory Usage

1. Adjust memory limiter in OTel config
2. Tune batch processor settings
3. Implement sampling strategies

## Security Best Practices

- [ ] Enable TLS for inter-service communication
- [ ] Use external secrets manager (AWS Secrets Manager, HashiCorp Vault)
- [ ] Implement NetworkPolicies for namespace isolation
- [ ] Enable Pod Security Standards
- [ ] Configure RBAC with minimal permissions

## License

MIT

---

**Last Updated**: February 2026  
**Terraform Version**: 1.5+  
**Kubernetes Version**: 1.24+
