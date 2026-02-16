# Deployment Guide

This guide walks you through deploying the OpenTelemetry Collector and Jaeger stack on Kubernetes using Terraform.

## Prerequisites Checklist

Before deploying, ensure you have:

- [ ] Kubernetes cluster (v1.24+) up and running
- [ ] kubectl installed and configured (`kubectl version`)
- [ ] Terraform installed (v1.5.0+) (`terraform version`)
- [ ] Helm installed (v3.0+) (`helm version`)
- [ ] Appropriate cluster permissions (cluster-admin or equivalent)
- [ ] Storage class available for Elasticsearch PVCs
- [ ] Sufficient cluster resources (see Resource Requirements below)

## Resource Requirements

### Minimum (Dev Environment)
- **Nodes**: 2-3 nodes
- **CPU**: 4 cores total
- **Memory**: 8 GB total
- **Storage**: 50 GB for Elasticsearch

### Recommended (Staging)
- **Nodes**: 3-5 nodes
- **CPU**: 8 cores total
- **Memory**: 16 GB total
- **Storage**: 100 GB for Elasticsearch

### Production
- **Nodes**: 5+ nodes
- **CPU**: 16+ cores total
- **Memory**: 32+ GB total
- **Storage**: 300+ GB for Elasticsearch

## Step-by-Step Deployment

### Step 1: Verify Cluster Access

```bash
# Check cluster connection
kubectl cluster-info

# Check available nodes
kubectl get nodes

# Check storage classes
kubectl get storageclass
```

### Step 2: Clone and Navigate

```bash
cd /Users/atulmunde/otel_terrform
```

### Step 3: Choose Your Environment

For development:
```bash
cd environments/dev
```

For staging:
```bash
cd environments/staging
```

For production:
```bash
cd environments/production
```

### Step 4: Review Configuration

Edit `terraform.tfvars` to adjust settings for your environment:

```bash
# Review current configuration
cat terraform.tfvars

# Make necessary changes
vim terraform.tfvars
```

Key settings to review:
- `elasticsearch_storage_class` - Set to your cluster's storage class
- `elasticsearch_storage_size` - Adjust based on retention needs
- `data_retention_days` - How long to keep traces
- Resource limits based on your cluster capacity

### Step 5: Initialize Terraform

```bash
terraform init
```

This will:
- Download required providers (Kubernetes, Helm)
- Initialize backend (if configured)
- Prepare modules

### Step 6: Review Execution Plan

```bash
terraform plan
```

Review the output carefully. You should see:
- Namespace creation
- ConfigMaps for OTel Collector
- Deployments for OTel Collector
- Helm release for Elasticsearch
- Helm release for Jaeger
- Services, HPAs, PDBs, etc.

### Step 7: Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm.

Expected deployment time:
- **Dev**: 3-5 minutes
- **Staging**: 5-8 minutes
- **Production**: 8-12 minutes

### Step 8: Verify Deployment

```bash
# Check namespace
kubectl get namespace telemetry

# Check all pods
kubectl get pods -n telemetry

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod --all -n telemetry --timeout=600s

# Check services
kubectl get svc -n telemetry

# Check PVCs
kubectl get pvc -n telemetry
```

Expected pods:
```
NAME                                    READY   STATUS    RESTARTS   AGE
otel-collector-xxxxx-xxxxx              1/1     Running   0          2m
jaeger-collector-xxxxx-xxxxx            1/1     Running   0          2m
jaeger-query-xxxxx-xxxxx                2/2     Running   0          2m
elasticsearch-master-0                  1/1     Running   0          3m
elasticsearch-master-1                  1/1     Running   0          2m
```

### Step 9: Access Jaeger UI

```bash
# Port forward Jaeger Query UI
kubectl port-forward -n telemetry svc/jaeger-query 16686:16686
```

Open browser: http://localhost:16686

### Step 10: Test with Sample Application

Deploy a test application that sends traces:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: otel-test
  namespace: default
spec:
  containers:
  - name: test
    image: curlimages/curl:latest
    command: 
      - sh
      - -c
      - |
        while true; do
          curl -X POST http://otel-collector.telemetry.svc.cluster.local:4318/v1/traces \
            -H "Content-Type: application/json" \
            -d '{
              "resourceSpans": [{
                "resource": {
                  "attributes": [{
                    "key": "service.name",
                    "value": {"stringValue": "test-service"}
                  }]
                },
                "scopeSpans": [{
                  "spans": [{
                    "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
                    "spanId": "051581bf3cb55c13",
                    "name": "test-span",
                    "kind": 1,
                    "startTimeUnixNano": "1544712660000000000",
                    "endTimeUnixNano": "1544712661000000000"
                  }]
                }]
              }]
            }'
          sleep 10
        done
    restartPolicy: Always
EOF
```

After a minute, you should see traces in Jaeger UI.

## Post-Deployment Configuration

### Configure Remote State (Production)

For production, configure remote state backend:

1. Edit `backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "k8s-otel-jaeger/production/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

2. Migrate state:
```bash
terraform init -migrate-state
```

### Setup Ingress (Optional)

If you want external access to Jaeger UI:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jaeger-ui
  namespace: telemetry
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - jaeger.yourdomain.com
    secretName: jaeger-tls
  rules:
  - host: jaeger.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jaeger-query
            port:
              number: 16686
```

### Setup Monitoring

Monitor the telemetry stack itself:

```bash
# Check HPA status
kubectl get hpa -n telemetry

# Check resource usage
kubectl top pods -n telemetry

# Check Elasticsearch health
kubectl exec -n telemetry elasticsearch-master-0 -- \
  curl -s http://localhost:9200/_cluster/health?pretty
```

## Troubleshooting Deployment

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n telemetry

# Describe problematic pod
kubectl describe pod <pod-name> -n telemetry

# Check logs
kubectl logs <pod-name> -n telemetry
```

### Elasticsearch Stuck in Pending

Usually due to PVC issues:

```bash
# Check PVC status
kubectl get pvc -n telemetry

# Describe PVC
kubectl describe pvc <pvc-name> -n telemetry

# Check storage class
kubectl get storageclass
```

Fix: Ensure your cluster has a default storage class or specify one in terraform.tfvars.

### OTel Collector CrashLoopBackOff

Check configuration:

```bash
kubectl logs -n telemetry -l app=otel-collector --tail=50

# Check configmap
kubectl get configmap otel-collector-config -n telemetry -o yaml
```

### Helm Release Failed

```bash
# Check Helm releases
helm list -n telemetry

# Get release status
helm status jaeger -n telemetry

# Check Helm logs
helm history jaeger -n telemetry
```

Fix and retry:
```bash
# Uninstall and let Terraform recreate
helm uninstall jaeger -n telemetry
terraform apply
```

### Insufficient Resources

If pods are pending due to insufficient resources:

```bash
kubectl describe pod <pod-name> -n telemetry | grep -A 5 Events
```

Solution: Scale down or add more nodes to your cluster.

## Updating the Stack

### Update Component Versions

1. Edit `terraform.tfvars`:
```hcl
otel_collector_version = "0.96.0"  # New version
jaeger_chart_version = "2.1.0"     # New version
```

2. Plan and apply:
```bash
terraform plan
terraform apply
```

### Scale Components

```bash
# Edit terraform.tfvars
otel_collector_replicas = 5
jaeger_collector_replicas = 3

# Apply changes
terraform apply
```

### Update Configuration

After changing OTel Collector config:

```bash
# Apply changes
terraform apply

# Restart pods to pick up new config
kubectl rollout restart deployment/otel-collector -n telemetry
```

## Cleanup

### Development/Testing

```bash
cd environments/dev
terraform destroy
```

### Production (Careful!)

```bash
cd environments/production

# Review what will be destroyed
terraform plan -destroy

# Backup any important data first!
# Then destroy
terraform destroy
```

## Next Steps

- [Application Integration Guide](./APPLICATION_INTEGRATION.md)
- [Operations Guide](./OPERATIONS.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Security Best Practices](./SECURITY.md)
