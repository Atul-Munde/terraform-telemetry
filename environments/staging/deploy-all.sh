#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Full stack deploy: ES, Kibana, Jaeger, OTel Operator + Agent + Gateway
# Usage:
#   export TF_VAR_elastic_password="Intangles@2026"
#   export TF_VAR_kibana_encryption_key="Intangles2026RandomSecureKey32!!"
#   bash deploy-all.sh
# ---------------------------------------------------------------------------
set -euo pipefail

: "${TF_VAR_elastic_password:?TF_VAR_elastic_password is not set}"
: "${TF_VAR_kibana_encryption_key:?TF_VAR_kibana_encryption_key is not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Deploys (in dependency order):
#   1. namespace
#   2. elasticsearch  (with fixed secret.password so kibana pre-install works)
#   3. kibana
#   4. jaeger
#   5. kube-prometheus-stack
#   6. otel-operator Helm chart  ← installs CRDs first
#   7. OpenTelemetryCollector + Instrumentation CRs  ← needs CRDs from step 6

echo "=== [1/3] Applying everything except OTel CRs ==="
# Pre-clean any lingering Kibana hooks from previous failed runs
# kubectl delete job pre-install-kibana-kibana -n telemetry --ignore-not-found 2>&1 || true
# kubectl delete sa pre-install-kibana-kibana post-delete-kibana-kibana -n telemetry --ignore-not-found 2>&1 || true
# kubectl delete role,rolebinding pre-install-kibana-kibana post-delete-kibana-kibana -n telemetry --ignore-not-found 2>&1 || true
# kubectl delete configmap kibana-kibana-helm-scripts -n telemetry --ignore-not-found 2>&1 || true

# Install all Helm releases including the operator (which installs CRDs)
# OTel collector CRs (kubernetes_manifest) are skipped until CRDs are ready
terraform apply \
  -var-file=terraform.tfvars \
  "-target=module.telemetry.module.namespace" \
  "-target=module.telemetry.module.elasticsearch[0]" \
  "-target=module.telemetry.module.kibana[0]" \
  "-target=module.telemetry.module.jaeger" \
  "-target=module.telemetry.module.kube_prometheus[0]" \
  "-target=module.telemetry.module.otel_operator[0].helm_release.otel_operator" \
  -auto-approve

echo "=== [2/3] Waiting 30s for OTel Operator CRDs to register ==="
sleep 30
kubectl wait --for=condition=established crd/opentelemetrycollectors.opentelemetry.io --timeout=60s 2>&1 || true
kubectl wait --for=condition=established crd/instrumentations.opentelemetry.io --timeout=60s 2>&1 || true

echo "=== [3/3] Applying OTel Collector CRs, RBAC, HPA, ServiceMonitor ==="
terraform apply \
  -var-file=terraform.tfvars \
  -auto-approve

echo "=== Done — current pod status ==="
kubectl get pods -n telemetry
