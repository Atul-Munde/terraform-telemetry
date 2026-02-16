#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🚀 Starting Telemetry Stack Deployment..."

# Check if namespace is terminating and wait for it to be gone
if kubectl get namespace telemetry -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Terminating"; then
    echo "⏳ Namespace is terminating, waiting for deletion..."
    
    # Force finalize to speed up deletion
    kubectl get namespace telemetry -o json 2>/dev/null | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/telemetry/finalize -f - 2>/dev/null || true
    
    # Wait for namespace to be completely gone
    while kubectl get namespace telemetry 2>/dev/null; do
        echo "    Still terminating..."
        sleep 3
    done
    echo "✓ Namespace deleted"
fi

# Check if namespace exists
if kubectl get namespace telemetry &>/dev/null; then
    echo "✓ Namespace 'telemetry' exists"
    
    # Check if it's in Terraform state
    if ! terraform state list 2>/dev/null | grep -q "kubernetes_namespace.this"; then
        echo "📥 Importing existing namespace into Terraform state..."
        terraform import 'module.telemetry.module.namespace.kubernetes_namespace.this[0]' telemetry || true
    fi
else
    echo "✓ Namespace 'telemetry' will be created"
fi

# Unlock state if locked
LOCK_ID=$(terraform force-unlock -help 2>&1 | grep "Lock Info" | head -1 || true)
if [ ! -z "$LOCK_ID" ]; then
    echo "🔓 Unlocking Terraform state..."
    terraform force-unlock -force "$LOCK_ID" 2>/dev/null || true
fi

# Apply Terraform configuration
echo "📦 Applying Terraform configuration..."
terraform apply -auto-approve

# Wait for pods to be ready
echo "⏳ Waiting for pods to be ready..."
sleep 10

kubectl wait --for=condition=ready pod -l app=otel-collector -n telemetry --timeout=300s 2>/dev/null || echo "⚠️  OTel Collector pods not ready yet"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=jaeger -n telemetry --timeout=300s 2>/dev/null || echo "⚠️  Jaeger pods not ready yet"  
kubectl wait --for=condition=ready pod -l app=elasticsearch -n telemetry --timeout=300s 2>/dev/null || echo "⚠️  Elasticsearch pods not ready yet"

echo ""
echo "✅ Deployment Complete!"
echo ""
echo "📊 Pod Status:"
kubectl get pods -n telemetry
echo ""
echo "🔗 Access Jaeger UI:"
echo "   kubectl port-forward -n telemetry svc/jaeger-query 16686:16686"
echo "   http://localhost:16686"
echo ""
echo "📡 OTel Collector Endpoints:"
echo "   gRPC: otel-collector.telemetry.svc.cluster.local:4317"
echo "   HTTP: otel-collector.telemetry.svc.cluster.local:4318"
