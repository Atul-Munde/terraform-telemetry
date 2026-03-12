# Quickstart

Get up and running fast.

---

## 1. Configure kubectl

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name intangles-qa-cluster \
  --profile mum-test
```

## 2. Verify the stack is running

```bash
kubectl get pods -n telemetry
```

Expected pods (staging):

```
NAME                                               READY   STATUS
otel-agent-collector-<node-hash>                   1/1     Running   ← 1 per node
otel-gateway-collector-0                            1/1     Running
otel-gateway-collector-1                            1/1     Running
otel-infra-metrics-<hash>                           1/1     Running
elasticsearch-master-0                              1/1     Running
elasticsearch-master-1                              1/1     Running
elasticsearch-master-2                              1/1     Running
elasticsearch-data-0                                1/1     Running
elasticsearch-data-1                                1/1     Running
elasticsearch-coordinating-<hash>                   1/1     Running   ← 2 replicas
jaeger-query-<hash>                                 1/1     Running   ← 2 replicas
jaeger-collector-<hash>                             1/1     Running   ← 2 replicas
kibana-<hash>                                       1/1     Running
vminsert-victoria-metrics-<hash>                    1/1     Running   ← 3 replicas
vmselect-victoria-metrics-<hash>                    1/1     Running   ← 3 replicas
vmstorage-victoria-metrics-<node>                   1/1     Running   ← 3 replicas
vmagent-<hash>                                      2/2     Running
vmalert-<hash>                                      1/1     Running
```

## 3. Open the UIs

| UI | URL |
|----|-----|
| Jaeger | https://jaeger.test.intangles.com |
| Kibana | https://kibana.test.intangles.com |
| Grafana | https://grafana.test.intangles.com |
| VictoriaMetrics | https://vm.test.intangles.com |

## 4. Send a test trace

```bash
# From inside the cluster
kubectl run trace-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -X POST http://otel-agent-collector.telemetry.svc.cluster.local:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {"attributes": [{"key":"service.name","value":{"stringValue":"quickstart-test"}}]},
      "scopeSpans": [{
        "spans": [{
          "traceId":"01020304050607080910111213141516",
          "spanId":"0102030405060708",
          "name":"test-span",
          "kind":1,
          "startTimeUnixNano":"1700000000000000000",
          "endTimeUnixNano":"1700000001000000000",
          "status":{"code":1}
        }]
      }]
    }]
  }'
```

Then search for `quickstart-test` in Jaeger UI.

## 5. Instrument your app

See [APPLICATION_INTEGRATION.md](APPLICATION_INTEGRATION.md) for SDK setup.

Shortest path for Node.js in-cluster:

```bash
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.telemetry.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

## 6. Deploy / update the stack

```bash
cd environments/staging

TF_VAR_elastic_password='<password>' \
TF_VAR_kibana_encryption_key='<32-char-key>' \
terraform apply -auto-approve
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for full deployment instructions.
