#!/bin/bash

# Deployment script for OpenTelemetry Collector & Jaeger stack
# Usage: ./scripts/deploy.sh <environment>
# Example: ./scripts/deploy.sh dev

set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$PROJECT_ROOT/environments/$ENVIRONMENT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    echo_error "Invalid environment: $ENVIRONMENT"
    echo "Usage: $0 <dev|staging|production>"
    exit 1
fi

# Check if environment directory exists
if [ ! -d "$ENV_DIR" ]; then
    echo_error "Environment directory not found: $ENV_DIR"
    exit 1
fi

echo_info "Deploying to environment: $ENVIRONMENT"
echo_info "Environment directory: $ENV_DIR"

# Check prerequisites
echo_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo_error "kubectl not found. Please install kubectl."
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo_error "terraform not found. Please install terraform."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo_error "helm not found. Please install helm."
    exit 1
fi

# Check Kubernetes connection
echo_info "Checking Kubernetes connection..."
if ! kubectl cluster-info &> /dev/null; then
    echo_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

CLUSTER=$(kubectl config current-context)
echo_info "Connected to cluster: $CLUSTER"

# Confirm production deployment
if [ "$ENVIRONMENT" == "production" ]; then
    echo_warn "You are about to deploy to PRODUCTION!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo_info "Deployment cancelled."
        exit 0
    fi
fi

# Navigate to environment directory
cd "$ENV_DIR"

# Initialize Terraform
echo_info "Initializing Terraform..."
terraform init -upgrade

# Validate configuration
echo_info "Validating Terraform configuration..."
terraform validate

if [ $? -ne 0 ]; then
    echo_error "Terraform validation failed!"
    exit 1
fi

# Plan
echo_info "Creating Terraform execution plan..."
terraform plan -out=tfplan

# Review plan
echo_warn "Review the plan above."
read -p "Do you want to apply these changes? (yes/no): " apply_confirm

if [ "$apply_confirm" != "yes" ]; then
    echo_info "Deployment cancelled."
    rm -f tfplan
    exit 0
fi

# Apply
echo_info "Applying Terraform configuration..."
terraform apply tfplan

if [ $? -ne 0 ]; then
    echo_error "Terraform apply failed!"
    rm -f tfplan
    exit 1
fi

# Cleanup
rm -f tfplan

# Wait for pods to be ready
echo_info "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod --all -n telemetry --timeout=600s

if [ $? -eq 0 ]; then
    echo_info "All pods are ready!"
else
    echo_warn "Some pods may not be ready yet. Check with: kubectl get pods -n telemetry"
fi

# Output useful information
echo ""
echo_info "=================================================="
echo_info "Deployment completed successfully!"
echo_info "=================================================="
echo ""
echo_info "Check status:"
echo "  kubectl get all -n telemetry"
echo ""
echo_info "Access Jaeger UI:"
echo "  kubectl port-forward -n telemetry svc/jaeger-query 16686:16686"
echo "  Then open: http://localhost:16686"
echo ""
echo_info "OTel Collector endpoints:"
echo "  OTLP gRPC: otel-collector.telemetry.svc.cluster.local:4317"
echo "  OTLP HTTP: otel-collector.telemetry.svc.cluster.local:4318"
echo ""
echo_info "View logs:"
echo "  kubectl logs -n telemetry -l app=otel-collector --tail=50 -f"
echo ""

exit 0
