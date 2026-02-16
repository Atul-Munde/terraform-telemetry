# Application Integration Guide

This guide shows you how to integrate your applications with the OpenTelemetry Collector to send distributed traces.

## Overview

After deploying the telemetry stack, applications need to:
1. Initialize OpenTelemetry SDK
2. Configure OTLP exporter to send to OTel Collector
3. Instrument code to create spans
4. Deploy with proper configuration

## Collector Endpoints

The OTel Collector exposes these endpoints within the cluster:

- **OTLP gRPC**: `otel-collector.telemetry.svc.cluster.local:4317`
- **OTLP HTTP**: `otel-collector.telemetry.svc.cluster.local:4318`

## Configuration Methods

### Method 1: Environment Variables (Recommended)

Set these environment variables in your application deployment:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.telemetry.svc.cluster.local:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
  - name: OTEL_SERVICE_NAME
    value: "my-service"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "environment=production,version=1.0.0"
```

### Method 2: Code Configuration

Configure in application code (see language-specific examples below).

## Language-Specific Integration

### Go

#### Installation

```bash
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
go get go.opentelemetry.io/otel/sdk/trace
go get go.opentelemetry.io/otel/sdk/resource
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
```

#### Basic Setup

```go
package main

import (
    "context"
    "log"
    "os"
    "time"

    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)

func initTracer() func() {
    ctx := context.Background()

    // Create OTLP exporter
    exporter, err := otlptracegrpc.New(
        ctx,
        otlptracegrpc.WithEndpoint("otel-collector.telemetry.svc.cluster.local:4317"),
        otlptracegrpc.WithInsecure(),
        otlptracegrpc.WithDialOption(grpc.WithBlock()),
    )
    if err != nil {
        log.Fatalf("Failed to create exporter: %v", err)
    }

    // Create resource
    res, err := resource.New(
        ctx,
        resource.WithAttributes(
            semconv.ServiceName("my-go-service"),
            semconv.ServiceVersion("1.0.0"),
        ),
        resource.WithFromEnv(),
        resource.WithProcess(),
        resource.WithOS(),
        resource.WithContainer(),
        resource.WithHost(),
    )
    if err != nil {
        log.Fatalf("Failed to create resource: %v", err)
    }

    // Create tracer provider
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(res),
        sdktrace.WithSampler(sdktrace.AlwaysSample()),
    )

    otel.SetTracerProvider(tp)

    return func() {
        ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()
        if err := tp.Shutdown(ctx); err != nil {
            log.Printf("Error shutting down tracer provider: %v", err)
        }
    }
}

func main() {
    cleanup := initTracer()
    defer cleanup()

    // Your application code here
    tracer := otel.Tracer("my-app")
    ctx, span := tracer.Start(context.Background(), "main-operation")
    defer span.End()

    // Do work...
}
```

#### HTTP Server Instrumentation

```go
import (
    "net/http"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
    cleanup := initTracer()
    defer cleanup()

    handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Write([]byte("Hello World"))
    })

    wrappedHandler := otelhttp.NewHandler(handler, "hello")
    http.ListenAndServe(":8080", wrappedHandler)
}
```

### Python

#### Installation

```bash
pip install opentelemetry-api
pip install opentelemetry-sdk
pip install opentelemetry-exporter-otlp-proto-grpc
pip install opentelemetry-instrumentation-flask  # For Flask
```

#### Basic Setup

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

# Create resource
resource = Resource.create({
    "service.name": "my-python-service",
    "service.version": "1.0.0",
    "deployment.environment": "production",
})

# Create tracer provider
tracer_provider = TracerProvider(resource=resource)

# Create OTLP exporter
otlp_exporter = OTLPSpanExporter(
    endpoint="otel-collector.telemetry.svc.cluster.local:4317",
    insecure=True
)

# Add span processor
tracer_provider.add_span_processor(
    BatchSpanProcessor(otlp_exporter)
)

# Set global tracer provider
trace.set_tracer_provider(tracer_provider)

# Get tracer
tracer = trace.get_tracer(__name__)

# Use tracer
with tracer.start_as_current_span("my-operation"):
    # Do work
    print("Hello from traced operation")
```

#### Flask Auto-Instrumentation

```python
from flask import Flask
from opentelemetry.instrumentation.flask import FlaskInstrumentor

app = Flask(__name__)

# Initialize tracing (use setup from above)
# ...

# Auto-instrument Flask
FlaskInstrumentor().instrument_app(app)

@app.route("/")
def hello():
    return "Hello World"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

### Node.js / TypeScript

#### Installation

```bash
npm install @opentelemetry/api
npm install @opentelemetry/sdk-node
npm install @opentelemetry/auto-instrumentations-node
npm install @opentelemetry/exporter-trace-otlp-grpc
```

#### Basic Setup

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'my-node-service',
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'grpc://otel-collector.telemetry.svc.cluster.local:4317',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

// Graceful shutdown
process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => console.log('Tracing terminated'))
    .catch((error) => console.log('Error terminating tracing', error))
    .finally(() => process.exit(0));
});

// Your application code
import express from 'express';
const app = express();

app.get('/', (req, res) => {
  res.send('Hello World');
});

app.listen(3000);
```

### Java (Spring Boot)

#### Maven Dependencies

```xml
<dependencies>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-api</artifactId>
        <version>1.34.1</version>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-sdk</artifactId>
        <version>1.34.1</version>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-exporter-otlp</artifactId>
        <version>1.34.1</version>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry.instrumentation</groupId>
        <artifactId>opentelemetry-spring-boot-starter</artifactId>
        <version>1.32.0-alpha</version>
    </dependency>
</dependencies>
```

#### Application Configuration

```yaml
# application.yml
otel:
  exporter:
    otlp:
      endpoint: http://otel-collector.telemetry.svc.cluster.local:4318
  service:
    name: my-java-service
  resource:
    attributes:
      environment: production
      version: 1.0.0
```

## Kubernetes Deployment Configuration

### Complete Example Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
  labels:
    app: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: app
        image: my-app:1.0.0
        ports:
        - containerPort: 8080
          name: http
        env:
        # OpenTelemetry Configuration
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.telemetry.svc.cluster.local:4318"
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: "http/protobuf"
        - name: OTEL_SERVICE_NAME
          value: "my-app"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "environment=production,version=1.0.0"
        
        # Kubernetes metadata
        - name: K8S_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: K8S_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: K8S_NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: default
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
    name: http
  type: ClusterIP
```

## Testing Integration

### 1. Deploy Your Application

```bash
kubectl apply -f my-app-deployment.yaml
```

### 2. Generate Some Traffic

```bash
# Get pod name
POD=$(kubectl get pod -l app=my-app -o jsonpath='{.items[0].metadata.name}')

# Port forward
kubectl port-forward $POD 8080:8080

# Generate requests
for i in {1..10}; do
  curl http://localhost:8080/
  sleep 1
done
```

### 3. Check Traces in Jaeger

```bash
# Port forward Jaeger UI
kubectl port-forward -n telemetry svc/jaeger-query 16686:16686
```

Open http://localhost:16686 and search for your service.

### 4. Verify OTel Collector Received Traces

```bash
kubectl logs -n telemetry -l app=otel-collector --tail=50 | grep "my-app"
```

## Best Practices

### 1. Service Naming

Use consistent naming:
```
<team>.<service>.<component>
# Example: platform.api.authentication
```

### 2. Resource Attributes

Always include:
- `service.name`
- `service.version`
- `deployment.environment`
- `service.namespace` (team/department)

### 3. Span Naming

Use meaningful span names:
- ✅ `GET /api/users/{id}`
- ✅ `db.query.users.findById`
- ❌ `operation`
- ❌ `span1`

### 4. Error Handling

Always set span status on errors:

```go
if err != nil {
    span.RecordError(err)
    span.SetStatus(codes.Error, err.Error())
    return err
}
```

### 5. Sampling Decisions

Let the collector handle sampling - instrument everything at the application level.

## Troubleshooting

### No Traces Appearing

1. **Check OTel Collector connectivity**:
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://otel-collector.telemetry.svc.cluster.local:4318/v1/traces
```

2. **Check application logs** for OTLP export errors

3. **Verify service name** is set correctly

### High Latency

1. **Use batching** in SDK configuration
2. **Reduce sampling rate** if needed
3. **Check collector resources**

### Missing Span Attributes

Ensure resource detection is enabled in SDK initialization.

## Next Steps

- [Operations Guide](./OPERATIONS.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Performance Tuning](./PERFORMANCE.md)
