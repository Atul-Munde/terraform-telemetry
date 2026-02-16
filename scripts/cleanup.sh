#!/bin/bash

# Cleanup script for OpenTelemetry Collector & Jaeger stack
# Usage: ./scripts/cleanup.sh <environment>
# Example: ./scripts/cleanup.sh dev

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

echo_warn "=================================================="
echo_warn "WARNING: This will destroy the $ENVIRONMENT stack!"
echo_warn "=================================================="
echo_warn "Environment: $ENVIRONMENT"
echo_warn "Directory: $ENV_DIR"
echo ""

# Extra confirmation for production
if [ "$ENVIRONMENT" == "production" ]; then
    echo_error "YOU ARE ABOUT TO DESTROY PRODUCTION!"
    echo_error "This will delete all traces and data!"
    echo ""
    read -p "Type 'DELETE-PRODUCTION' to confirm: " confirm
    if [ "$confirm" != "DELETE-PRODUCTION" ]; then
        echo_info "Cleanup cancelled."
        exit 0
    fi
else
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    if [ "$confirm" != "yes" ]; then
        echo_info "Cleanup cancelled."
        exit 0
    fi
fi

# Navigate to environment directory
cd "$ENV_DIR"

# Create destroy plan
echo_info "Creating Terraform destroy plan..."
terraform plan -destroy -out=destroy.tfplan

# Review plan
echo_warn "Review the destroy plan above."
read -p "Proceed with destruction? (yes/no): " destroy_confirm

if [ "$destroy_confirm" != "yes" ]; then
    echo_info "Cleanup cancelled."
    rm -f destroy.tfplan
    exit 0
fi

# Destroy
echo_info "Destroying resources..."
terraform apply destroy.tfplan

if [ $? -ne 0 ]; then
    echo_error "Terraform destroy failed!"
    echo_error "You may need to manually clean up resources."
    rm -f destroy.tfplan
    exit 1
fi

# Cleanup plan file
rm -f destroy.tfplan

# Check if namespace still exists
if kubectl get namespace telemetry &> /dev/null; then
    echo_warn "Namespace 'telemetry' still exists."
    read -p "Force delete namespace? (yes/no): " ns_confirm
    if [ "$ns_confirm" == "yes" ]; then
        kubectl delete namespace telemetry --force --grace-period=0
    fi
fi

echo ""
echo_info "=================================================="
echo_info "Cleanup completed!"
echo_info "=================================================="
echo ""

exit 0
