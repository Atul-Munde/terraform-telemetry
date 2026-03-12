# Application Integration Guide

How to instrument your applications to send telemetry to the OTel stack.

---

## Endpoints

| Protocol | Endpoint | Use case |
|----------|----------|----------|
| OTLP gRPC | `otel-agent-collector.telemetry.svc.cluster.local:4317` | **Recommended — same cluster** |
| OTLP HTTP | `http://otel-agent-collector.telemetry.svc.cluster.local:4318` | SDK default (HTTP) |
| OTLP HTTP public | `https://otel.test.intangles.com` | External clients |

> Always send to the **Agent** (DaemonSet) — never directly to the Gateway.  
> The Agent runs on the same node as your pod and forwards to the Gateway with tail sampling.

---

## Node.js

### Using `@opentelemetry/sdk-node`

```js
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-grpc');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');

const sdk = new NodeSDK({
  serviceName: 'my-service',
  traceExporter: new OTLPTraceExporter({
    url: 'http://otel-agent-collector.telemetry.svc.cluster.local:4317',
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: 'http://otel-agent-collector.telemetry.svc.cluster.local:4317',
    }),
  }),
});

sdk.start();
```

### Environment variables (preferred)

```bash
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.telemetry.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
```

---

## Java

```bash
OTEL_SERVICE_NAME=my-java-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.telemetry.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

```bash
java -javaagent:/path/to/opentelemetry-javaagent.jar -jar myapp.jar
```

---

## Python

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
```

```bash
OTEL_SERVICE_NAME=my-python-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.telemetry.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
opentelemetry-instrument python app.py
```

---

## Auto-Instrumentation (OTel Operator)

No code changes needed. The OTel Operator injects the SDK into pods automatically.

### Enable for a namespace (Node.js)

```bash
kubectl annotate namespace <app-namespace> \
  instrumentation.opentelemetry.io/inject-nodejs="telemetry/nodejs-instrumentation"
kubectl rollout restart deployment -n <app-namespace>
```

### Enable for a specific deployment

Add annotation to the pod spec:

```yaml
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-nodejs: "telemetry/nodejs-instrumentation"
```

### Supported runtimes

| Runtime | Annotation value |
|---------|-----------------|
| Node.js | `telemetry/nodejs-instrumentation` |
| Java | `telemetry/java-instrumentation` *(if configured)* |
| Python | `telemetry/python-instrumentation` *(if configured)* |

---

## Kubernetes Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
  namespace: default
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-nodejs: "telemetry/nodejs-instrumentation"
    spec:
      containers:
        - name: app
          image: my-service:latest
          env:
            - name: OTEL_SERVICE_NAME
              value: "my-service"
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "deployment.environment=staging,team=platform"
```

---

## Verifying Traces

1. Open Jaeger UI: https://jaeger.test.intangles.com
2. Select your service name
3. Click "Find Traces"

If no traces appear:
```bash
# Check Agent received data
kubectl logs -n telemetry -l app.kubernetes.io/name=otel-agent-collector --tail=30 | grep -i "export\|error"

# Check Gateway processed traces
kubectl logs -n telemetry -l app.kubernetes.io/name=otel-gateway-collector --tail=30 | grep -i "sampling\|jaeger\|error"
```

---

## Verifying Metrics

Metrics flow: App → Agent → Gateway → VictoriaMetrics  
Query in Grafana: https://grafana.test.intangles.com  
VictoriaMetrics UI: https://vm.test.intangles.com

```bash
# Check VMAgent scraped your service
kubectl logs -n telemetry -l app.kubernetes.io/name=vmagent --tail=30 | grep "my-service"
```

---

## Resource Attributes

Add these to help with filtering:

```bash
OTEL_RESOURCE_ATTRIBUTES="deployment.environment=staging,team=platform,service.version=1.2.3"
```
