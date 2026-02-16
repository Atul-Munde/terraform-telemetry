# Quick Start Guide

Get your OpenTelemetry Collector and Jaeger stack running in under 10 minutes!

## Prerequisites

- Kubernetes cluster (1.24+)
- kubectl configured
- Terraform (1.5.0+)
- Helm (3.0+)

## Quick Deploy (Development)

### 1. Navigate to Dev Environment

```bash
cd /Users/atulmunde/otel_terrform/environments/dev
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Deploy

```bash
terraform apply -auto-approve
```

Wait 3-5 minutes for all pods to be ready.

### 4. Verify

```bash
kubectl get pods -n telemetry
```

You should see pods running:
- `otel-collector-*` (1 replica)
- `jaeger-collector-*` (2 replicas)
- `jaeger-query-*` (2 replicas)
- `elasticsearch-master-0` and `elasticsearch-master-1` (2 replicas)

### 5. Access Jaeger UI

```bash
kubectl port-forward -n telemetry svc/jaeger-query 16686:16686
```

Open browser: http://localhost:16686

## Send Test Traces

### Quick Test with curl

```bash
kubectl run -it --rm otel-test --image=curlimages/curl --restart=Never -- \
  curl -X POST http://otel-collector.telemetry.svc.cluster.local:4318/v1/traces \
    -H "Content-Type: application/json" \
    -d '{
      "resourceSpans": [{
        "resource": {
          "attributes": [{
            "key": "service.name",
            "value": {"stringValue": "quickstart-test"}
          }]
        },
        "scopeSpans": [{
          "spans": [{
            "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
            "spanId": "051581bf3cb55c13",
            "name": "hello-world-span",
            "kind": 1,
            "startTimeUnixNano": "'$(date +%s)000000000'",
            "endTimeUnixNano": "'$(date +%s)100000000'"
          }]
        }]
      }]
    }'
```

### Check Jaeger UI

Refresh Jaeger UI and select `quickstart-test` service. You should see your trace!

## OTel Collector Endpoints

Your applications should send traces to:

**HTTP (recommended):**
```
http://otel-collector.telemetry.svc.cluster.local:4318
```

**gRPC:**
```
otel-collector.telemetry.svc.cluster.local:4317
```

## Environment Variables for Your Apps

Add to your application deployments:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.telemetry.svc.cluster.local:4318"
  - name: OTEL_SERVICE_NAME
    value: "my-service"
```

## Common Commands

### Check Everything

```bash
kubectl get all -n telemetry
```

### View OTel Collector Logs

```bash
kubectl logs -n telemetry -l app=otel-collector --tail=50 -f
```

### View Jaeger Logs

```bash
kubectl logs -n telemetry -l app.kubernetes.io/component=query --tail=50 -f
```

### Check Elasticsearch Health

```bash
kubectl exec -n telemetry elasticsearch-master-0 -- \
  curl -s http://localhost:9200/_cluster/health?pretty
```

### Scale OTel Collector

```bash
kubectl scale deployment otel-collector -n telemetry --replicas=5
```

## Cleanup

```bash
cd /Users/atulmunde/otel_terrform/environments/dev
terraform destroy -auto-approve
```

## Next Steps

- **Production Setup**: See [Deployment Guide](./DEPLOYMENT.md)
- **Application Integration**: See [Application Integration Guide](./APPLICATION_INTEGRATION.md)
- **Advanced Configuration**: See [Operations Guide](./OPERATIONS.md)

## Troubleshooting

### Pods Not Starting?

```bash
kubectl describe pod <pod-name> -n telemetry
```

### PVC Pending?

Check storage class:
```bash
kubectl get storageclass
```

Set in `terraform.tfvars`:
```hcl
elasticsearch_storage_class = "your-storage-class-name"
```

### No Traces Appearing?

1. Check OTel Collector is receiving:
```bash
kubectl logs -n telemetry -l app=otel-collector --tail=20
```

2. Check Jaeger Collector:
```bash
kubectl logs -n telemetry -l app.kubernetes.io/component=collector --tail=20
```

3. Verify Elasticsearch:
```bash
kubectl exec -n telemetry elasticsearch-master-0 -- \
  curl http://localhost:9200/_cat/indices
```

## Get Help

- Check full documentation in `docs/` folder
- Review module configuration in `modules/` folder
- Examine logs: `kubectl logs -n telemetry <pod-name>`

---

**Time to first trace: ~5 minutes** ⚡️
