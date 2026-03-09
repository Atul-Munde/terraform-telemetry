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
  echo "Elasticsearch connected. Running full plan..."
  terraform plan -compact-warnings "$@" 2>&1
  EXIT_CODE=$?
  kill $PF_PID 2>/dev/null
  wait $PF_PID 2>/dev/null
  exit $EXIT_CODE
fi

# ES not running — plan without ILM resources
echo "WARNING: Elasticsearch not reachable. Planning without ILM resources."
echo "         ILM policies will be applied in Phase 2 of .tf_apply.sh"
kill $PF_PID 2>/dev/null
wait $PF_PID 2>/dev/null

terraform plan -compact-warnings \
  -target=module.telemetry.module.namespace \
  -target=module.telemetry.module.elasticsearch \
  -target=module.telemetry.module.kibana \
  -target=module.telemetry.module.jaeger \
  -target=module.telemetry.module.otel_operator \
  -target=module.telemetry.module.kube_prometheus \
  -target=module.telemetry.module.victoria_metrics \
  "$@" 2>&1
