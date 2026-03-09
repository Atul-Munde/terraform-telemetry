#!/bin/zsh

export TF_VAR_elastic_password='Intangles@2026'
export TF_VAR_kibana_encryption_key='Intangles2026RandomSecureKey32!!'
export TF_VAR_dash0_auth_token='Bearer auth_uPbyf1XkiclCTALKB7YsniymdTBcUAXB'
export TF_VAR_elasticsearch_endpoint='https://localhost:9200'

# Start port-forward in background
echo "Starting Elasticsearch port-forward..."
kubectl port-forward -n telemetry svc/elasticsearch-master 9200:9200 &
PF_PID=$!
sleep 10

if ! curl -sk -u "elastic:${TF_VAR_elastic_password}" https://localhost:9200/_cluster/health > /dev/null 2>&1; then
  echo "ERROR: Cannot connect to Elasticsearch. Check kubectl context."
  kill $PF_PID 2>/dev/null
  exit 1
fi
echo "Elasticsearch connected."

terraform plan -compact-warnings "$@" 2>&1

kill $PF_PID 2>/dev/null
wait $PF_PID 2>/dev/null
