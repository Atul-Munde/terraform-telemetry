#!/bin/bash

# Validation script to check the health of the telemetry stack
# Usage: ./scripts/validate.sh

set -e

NAMESPACE="telemetry"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo ""
echo "=================================================="
echo "Telemetry Stack Health Check"
echo "=================================================="
echo ""

# Check if namespace exists
echo "Checking namespace..."
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo_info "Namespace '$NAMESPACE' exists"
else
    echo_error "Namespace '$NAMESPACE' not found!"
    exit 1
fi

# Check OTel Collector pods
echo ""
echo "Checking OTel Collector..."
OTEL_PODS=$(kubectl get pods -n $NAMESPACE -l app=otel-collector --no-headers 2>/dev/null | wc -l)
OTEL_READY=$(kubectl get pods -n $NAMESPACE -l app=otel-collector --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ $OTEL_PODS -gt 0 ]; then
    echo_info "OTel Collector pods: $OTEL_READY/$OTEL_PODS ready"
    if [ $OTEL_READY -lt $OTEL_PODS ]; then
        echo_warn "Some OTel Collector pods are not ready"
        kubectl get pods -n $NAMESPACE -l app=otel-collector
    fi
else
    echo_error "No OTel Collector pods found!"
fi

# Check Jaeger pods
echo ""
echo "Checking Jaeger..."
JAEGER_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=jaeger --no-headers 2>/dev/null | wc -l)
JAEGER_READY=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=jaeger --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ $JAEGER_PODS -gt 0 ]; then
    echo_info "Jaeger pods: $JAEGER_READY/$JAEGER_PODS ready"
    if [ $JAEGER_READY -lt $JAEGER_PODS ]; then
        echo_warn "Some Jaeger pods are not ready"
        kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=jaeger
    fi
else
    echo_error "No Jaeger pods found!"
fi

# Check Elasticsearch
echo ""
echo "Checking Elasticsearch..."
ES_PODS=$(kubectl get pods -n $NAMESPACE -l app=elasticsearch --no-headers 2>/dev/null | wc -l)
ES_READY=$(kubectl get pods -n $NAMESPACE -l app=elasticsearch --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ $ES_PODS -gt 0 ]; then
    echo_info "Elasticsearch pods: $ES_READY/$ES_PODS ready"
    if [ $ES_READY -lt $ES_PODS ]; then
        echo_warn "Some Elasticsearch pods are not ready"
        kubectl get pods -n $NAMESPACE -l app=elasticsearch
    fi
    
    # Check Elasticsearch health
    if [ $ES_READY -gt 0 ]; then
        echo "  Checking cluster health..."
        ES_HEALTH=$(kubectl exec -n $NAMESPACE elasticsearch-0 -- curl -s http://localhost:9200/_cluster/health 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        if [ "$ES_HEALTH" == "green" ]; then
            echo_info "  Cluster health: green"
        elif [ "$ES_HEALTH" == "yellow" ]; then
            echo_warn "  Cluster health: yellow"
        else
            echo_error "  Cluster health: $ES_HEALTH"
        fi
    fi
else
    echo_error "No Elasticsearch pods found!"
fi

# Check Services
echo ""
echo "Checking Services..."
SERVICES=$(kubectl get svc -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
if [ $SERVICES -gt 0 ]; then
    echo_info "Services: $SERVICES found"
    kubectl get svc -n $NAMESPACE
else
    echo_error "No services found!"
fi

# Check PVCs
echo ""
echo "Checking Persistent Volume Claims..."
PVCS=$(kubectl get pvc -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
BOUND_PVCS=$(kubectl get pvc -n $NAMESPACE --field-selector=status.phase=Bound --no-headers 2>/dev/null | wc -l)

if [ $PVCS -gt 0 ]; then
    echo_info "PVCs: $BOUND_PVCS/$PVCS bound"
    if [ $BOUND_PVCS -lt $PVCS ]; then
        echo_warn "Some PVCs are not bound"
        kubectl get pvc -n $NAMESPACE
    fi
else
    echo_warn "No PVCs found"
fi

# Check HPA
echo ""
echo "Checking Horizontal Pod Autoscalers..."
HPAS=$(kubectl get hpa -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
if [ $HPAS -gt 0 ]; then
    echo_info "HPAs: $HPAS found"
    kubectl get hpa -n $NAMESPACE
else
    echo_warn "No HPAs found"
fi

# Test OTel Collector connectivity
echo ""
echo "Testing OTel Collector connectivity..."
if kubectl run test-connectivity --rm -i --restart=Never --image=curlimages/curl:latest -n $NAMESPACE -- \
    curl -s -o /dev/null -w "%{http_code}" http://otel-collector.$NAMESPACE.svc.cluster.local:13133/ 2>/dev/null | grep -q "200"; then
    echo_info "OTel Collector health endpoint is accessible"
else
    echo_error "Cannot reach OTel Collector health endpoint"
fi

# Summary
echo ""
echo "=================================================="
echo "Health Check Summary"
echo "=================================================="
TOTAL_PODS=$((OTEL_PODS + JAEGER_PODS + ES_PODS))
TOTAL_READY=$((OTEL_READY + JAEGER_READY + ES_READY))

if [ $TOTAL_READY -eq $TOTAL_PODS ] && [ $TOTAL_PODS -gt 0 ]; then
    echo_info "All systems operational! ($TOTAL_READY/$TOTAL_PODS pods ready)"
    echo ""
    echo "Access Jaeger UI:"
    echo "  kubectl port-forward -n $NAMESPACE svc/jaeger-query 16686:16686"
    echo "  http://localhost:16686"
    echo ""
    exit 0
else
    echo_warn "Some issues detected ($TOTAL_READY/$TOTAL_PODS pods ready)"
    echo ""
    echo "Troubleshooting commands:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl describe pod <pod-name> -n $NAMESPACE"
    echo "  kubectl logs <pod-name> -n $NAMESPACE"
    echo ""
    exit 1
fi
