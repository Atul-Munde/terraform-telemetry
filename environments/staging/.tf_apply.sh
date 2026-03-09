#!/bin/zsh

export TF_VAR_elastic_password='Intangles@2026'
export TF_VAR_kibana_encryption_key='Intangles2026RandomSecureKey32!!'
export TF_VAR_dash0_auth_token='Bearer auth_uPbyf1XkiclCTALKB7YsniymdTBcUAXB'
export TF_VAR_elasticsearch_endpoint='https://localhost:9200'

# ---------------------------------------------------------------------------
# Try to connect to Elasticsearch via port-forward
# ---------------------------------------------------------------------------
echo "Checking if Elasticsearch is already running..."
kubectl port-forward -n telemetry svc/elasticsearch-master 9200:9200 &
PF_PID=$!
sleep 10

if curl -sk -u "elastic:${TF_VAR_elastic_password}" https://localhost:9200/_cluster/health > /dev/null 2>&1; then
  # -------------------------------------------------------------------------
  # ES is running — single full apply (day-2 operations)
  # -------------------------------------------------------------------------
  echo "Elasticsearch connected. Running full apply..."
  terraform apply -compact-warnings "$@" 2>&1
  EXIT_CODE=$?
  kill $PF_PID 2>/dev/null
  wait $PF_PID 2>/dev/null
  exit $EXIT_CODE
fi

# ---------------------------------------------------------------------------
# ES is NOT running — two-phase deploy (fresh setup)
# ---------------------------------------------------------------------------
echo "Elasticsearch not reachable. Running two-phase deploy..."
kill $PF_PID 2>/dev/null
wait $PF_PID 2>/dev/null

# Phase 1: Deploy all modules (Helm releases, K8s resources) — no ILM
echo ""
echo "=== Phase 1: Deploying infrastructure (skipping ILM) ==="
terraform apply -compact-warnings \
  -target=module.telemetry.module.namespace \
  -target=module.telemetry.module.elasticsearch \
  -target=module.telemetry.module.kibana \
  -target=module.telemetry.module.jaeger \
  -target=module.telemetry.module.otel_operator \
  -target=module.telemetry.module.kube_prometheus \
  -target=module.telemetry.module.victoria_metrics \
  "$@" 2>&1

if [ $? -ne 0 ]; then
  echo "ERROR: Phase 1 failed."
  exit 1
fi

# Wait for Elasticsearch pods to be ready
echo ""
echo "Waiting for Elasticsearch pods to become ready..."
kubectl rollout status statefulset/elasticsearch-master -n telemetry --timeout=300s

if [ $? -ne 0 ]; then
  echo "ERROR: Elasticsearch pods did not become ready in time."
  exit 1
fi

# Phase 2: Port-forward + full apply (ILM policies & index templates)
echo ""
echo "=== Phase 2: Applying ILM policies and index templates ==="
kubectl port-forward -n telemetry svc/elasticsearch-master 9200:9200 &
PF_PID=$!
sleep 5

if ! curl -sk -u "elastic:${TF_VAR_elastic_password}" https://localhost:9200/_cluster/health > /dev/null 2>&1; then
  echo "ERROR: Cannot connect to Elasticsearch after deploy. Check pod status."
  kill $PF_PID 2>/dev/null
  exit 1
fi
echo "Elasticsearch connected. Applying ILM resources..."

terraform apply -compact-warnings "$@" 2>&1
EXIT_CODE=$?

kill $PF_PID 2>/dev/null
wait $PF_PID 2>/dev/null
exit $EXIT_CODE
