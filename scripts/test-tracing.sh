#!/bin/bash
# Test OpenTelemetry Operator pipeline:
#   Test app → OTel Agent (DaemonSet) → OTel Gateway (StatefulSet, tail-sampling)
#   → Jaeger (traces) + Prometheus (metrics) + Elasticsearch (logs)

set -euo pipefail

NAMESPACE="${1:-telemetry}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

cleanup() {
  echo ""
  echo -e "${YELLOW}Stopping port-forwards...${NC}"
  [[ ${#PF_PIDS[@]} -gt 0 ]] && kill "${PF_PIDS[@]}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PF_PIDS=()

port_forward() {
  local label="$1" svc="$2" local_port="$3" remote_port="$4"
  echo -e "${CYAN}  Port-forward ${label}: localhost:${local_port} → ${svc}:${remote_port}${NC}"
  kubectl port-forward -n "$NAMESPACE" "svc/${svc}" "${local_port}:${remote_port}" \
    --address 127.0.0.1 >/dev/null 2>&1 &
  PF_PIDS+=($!)
}

# ─── Step 1: Health check ────────────────────────────────────────────────────
echo -e "${YELLOW}Step 1: Component health check${NC}"

echo -e "\n  OTel Operator pods (opentelemetry-operator-system):"
kubectl get pods -n opentelemetry-operator-system --no-headers \
  | awk '{printf "  %-55s %s/%s\n", $1, $2, $3}' || true

echo -e "\n  Telemetry stack pods:"
kubectl get pods -n "$NAMESPACE" --no-headers \
  | grep -E "otel-agent|otel-gateway|jaeger|grafana|prometheus-[0-9]|elasticsearch-master|kibana" \
  | awk '{printf "  %-55s %-20s %s\n", $1, $3, $4}' || true

echo -e "\n  OTelCollector CRD status:"
kubectl get opentelemetrycollectors -n "$NAMESPACE" \
  --no-headers 2>/dev/null \
  | awk '{printf "  %-30s mode=%-12s ready=%s\n", $1, $2, $4}' || true

echo -e "\n  Instrumentation CRD:"
kubectl get instrumentations -n "$NAMESPACE" \
  --no-headers 2>/dev/null \
  | awk '{printf "  %-32s endpoint=%s\n", $1, $3}' || true

# ─── Step 2: Agent READY check ──────────────────────────────────────────────
echo -e "\n${YELLOW}Step 2: Verify otel-agent is Ready${NC}"
AGENT_NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers \
  | grep "otel-agent" | grep -c -v "1/1.*Running" || true)
if [[ "$AGENT_NOT_READY" -gt 0 ]]; then
  echo -e "${RED}  ✗ ${AGENT_NOT_READY} agent pod(s) not ready — check logs:${NC}"
  echo "    kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=opentelemetry-collector --prefix | head -40"
  echo ""
else
AGENT_COUNT=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "otel-agent" || true)
  echo -e "${GREEN}  ✓ All ${AGENT_COUNT} otel-agent pods Running (1/1)${NC}"
fi

# ─── Step 3: Port-forwards ───────────────────────────────────────────────────
echo -e "\n${YELLOW}Step 3: Starting port-forwards${NC}"
port_forward "Jaeger UI"      "jaeger-query"                            16686  16686
port_forward "OTel Agent"     "otel-agent-collector"                    4318   4318
port_forward "OTel Agent(gRPC)" "otel-agent-collector"                  4317   4317
port_forward "Grafana"        "kube-prometheus-stack-grafana"           3000   80
port_forward "Prometheus"     "kube-prometheus-stack-prometheus"        9090   9090
port_forward "Alertmanager"   "kube-prometheus-stack-alertmanager"      9093   9093
port_forward "Kibana"         "kibana-kibana"                           5601   5601
sleep 6

# ─── Step 4: Send test trace ─────────────────────────────────────────────────
echo -e "\n${YELLOW}Step 4: Sending test trace via OTel Agent OTLP/HTTP${NC}"

# Wait for port-forward to be ready (retry up to 15s)
for i in $(seq 1 15); do
  if curl -sf --max-time 1 http://localhost:4318/ >/dev/null 2>&1 || \
     curl -sf --max-time 1 -X POST http://localhost:4318/v1/traces \
       -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1; then
    break
  fi
  [[ $i -eq 15 ]] && { echo -e "${RED}  ✗ Port-forward to otel-agent-collector:4318 not ready after 15s${NC}"; exit 1; }
  sleep 1
done

# Use current time so Jaeger doesn't filter it as "too old"
NOW_NS=$(python3 -c "import time; print(int(time.time() * 1e9))")
END_NS=$(python3 -c "import time; print(int(time.time() * 1e9) + 500_000_000)")
TRACE_ID=$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]')
SPAN_ID=$(openssl rand -hex 8 | tr '[:lower:]' '[:upper:]')
CHILD_SPAN_ID=$(openssl rand -hex 8 | tr '[:lower:]' '[:upper:]')

HTTP_STATUS=$(curl -s -o /tmp/otel_response.json -w "%{http_code}" \
  -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d "{
    \"resourceSpans\": [{
      \"resource\": {
        \"attributes\": [
          {\"key\": \"service.name\",      \"value\": {\"stringValue\": \"test-service\"}},
          {\"key\": \"service.version\",   \"value\": {\"stringValue\": \"1.0.0\"}},
          {\"key\": \"deployment.environment\", \"value\": {\"stringValue\": \"staging\"}}
        ]
      },
      \"scopeSpans\": [{
        \"scope\": {\"name\": \"test-tracer\", \"version\": \"1.0\"},
        \"spans\": [
          {
            \"traceId\": \"${TRACE_ID}\",
            \"spanId\": \"${SPAN_ID}\",
            \"name\": \"GET /api/orders\",
            \"kind\": 2,
            \"startTimeUnixNano\": \"${NOW_NS}\",
            \"endTimeUnixNano\": \"${END_NS}\",
            \"attributes\": [
              {\"key\": \"http.method\",      \"value\": {\"stringValue\": \"GET\"}},
              {\"key\": \"http.url\",         \"value\": {\"stringValue\": \"http://api.staging.internal/api/orders\"}},
              {\"key\": \"http.status_code\", \"value\": {\"intValue\": 200}},
              {\"key\": \"http.route\",       \"value\": {\"stringValue\": \"/api/orders\"}}
            ],
            \"status\": {\"code\": 1}
          },
          {
            \"traceId\": \"${TRACE_ID}\",
            \"spanId\": \"${CHILD_SPAN_ID}\",
            \"parentSpanId\": \"${SPAN_ID}\",
            \"name\": \"db.query SELECT orders\",
            \"kind\": 3,
            \"startTimeUnixNano\": \"$(python3 -c "import time; print(int(time.time() * 1e9) + 10_000_000)")\",
            \"endTimeUnixNano\": \"$(python3 -c "import time; print(int(time.time() * 1e9) + 200_000_000)")\",
            \"attributes\": [
              {\"key\": \"db.system\",     \"value\": {\"stringValue\": \"postgresql\"}},
              {\"key\": \"db.statement\",  \"value\": {\"stringValue\": \"SELECT * FROM orders WHERE user_id=?\"}},
              {\"key\": \"db.name\",       \"value\": {\"stringValue\": \"orders_db\"}}
            ],
            \"status\": {\"code\": 1}
          }
        ]
      }]
    }]
  }" 2>/dev/null) || HTTP_STATUS="curl_failed"

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo -e "${GREEN}  ✓ Trace accepted by Agent (HTTP 200)${NC}"
  echo "    traceId : ${TRACE_ID}"
  echo "    spans   : GET /api/orders  +  db.query SELECT orders (parent→child)"
else
  echo -e "${RED}  ✗ Agent returned HTTP ${HTTP_STATUS}${NC}"
  cat /tmp/otel_response.json
fi

# ─── Step 5: Tail-sampling note ──────────────────────────────────────────────
echo -e "\n${YELLOW}Step 5: Tail-sampling note${NC}"
echo "  Gateway waits 30s before deciding to sample this trace."
echo "  Staging keeps 50% of normal traces; slow (>2s) and error traces are always kept."
echo "  Wait ~35s before searching Jaeger or Elasticsearch."

# ─── Step 6: Elasticsearch index check ───────────────────────────────────────
echo -e "\n${YELLOW}Step 6: Elasticsearch index check${NC}"
ES_PASS=$(kubectl get secret -n "$NAMESPACE" elasticsearch-credentials \
  -o jsonpath='{.data.ELASTIC_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "Intangles@2026")
kubectl exec -n "$NAMESPACE" elasticsearch-master-0 -- \
  curl -s -k -u "elastic:${ES_PASS}" \
  "https://localhost:9200/_cat/indices/jaeger-*?v&h=health,status,index,docs.count" \
  2>/dev/null | head -20 \
  || echo "  (elasticsearch not reachable or no jaeger indices yet)"

# ─── Step 6b: Kibana health check ────────────────────────────────────────────
echo -e "\n${YELLOW}Step 6b: Kibana status${NC}"
KIBANA_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers \
  | awk '/kibana-kibana/{print $1}' | head -1)
if [[ -n "$KIBANA_POD" ]]; then
  KIBANA_STATUS=$(kubectl exec -n "$NAMESPACE" "$KIBANA_POD" -- \
    curl -s --max-time 5 http://localhost:5601/api/status \
    2>/dev/null | python3 -c \
    "import sys,json; d=json.load(sys.stdin); s=d.get('status',{}).get('overall',{}); print(s.get('level','unknown'))" \
    2>/dev/null || echo "not ready")
  if [[ "$KIBANA_STATUS" == "available" ]]; then
    echo -e "${GREEN}  ✓ Kibana status: ${KIBANA_STATUS}${NC}"
  else
    echo -e "${YELLOW}  ⚠ Kibana status: ${KIBANA_STATUS} (may still be initialising)${NC}"
  fi
  echo -e "  Version: $(kubectl exec -n "$NAMESPACE" "$KIBANA_POD" -- \
    curl -s --max-time 5 http://localhost:5601/api/status 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version',{}).get('number','unknown'))" \
    2>/dev/null || echo 'unknown')"
else
  echo -e "${RED}  ✗ No Kibana pod found in namespace ${NAMESPACE}${NC}"
fi

# ─── Step 7: Gateway pipeline metrics ────────────────────────────────────────
echo -e "\n${YELLOW}Step 7: Gateway telemetry — pipeline throughput (from Prometheus scrape)${NC}"
GATEWAY_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep "otel-gateway-collector-0" | awk '{print $1}')
if [[ -n "$GATEWAY_POD" ]]; then
  kubectl exec -n "$NAMESPACE" "$GATEWAY_POD" -- \
    wget -qO- http://localhost:8888/metrics 2>/dev/null \
    | grep -E "^otelcol_(receiver_accepted|processor_dropped|exporter_sent)_spans" \
    | head -15 \
    || echo "  (metrics endpoint not ready yet)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
GRAFANA_PASS=$(kubectl get secret -n "$NAMESPACE" kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not found>")

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  All port-forwards active — endpoints below${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "  🔭 Jaeger UI       http://localhost:16686"
echo "     Search  →  Service: test-service  (wait ~35s for tail-sampling)"
echo "     traceId : ${TRACE_ID}"
echo ""
echo "  📊 Grafana         http://localhost:3000"
echo "     user: admin   password: ${GRAFANA_PASS}"
echo "     Dashboards → OTel Collector / Kubernetes"
echo ""
echo "  📈 Prometheus      http://localhost:9090"
echo "     Try: otelcol_receiver_accepted_spans_total"
echo ""
echo "  🔔 Alertmanager    http://localhost:9093"
echo ""
echo "  � Kibana          http://localhost:5601"
echo "     user: elastic   password: ${ES_PASS:-Intangles@2026}"
echo "     → Discover → select jaeger-* index pattern to explore traces"
echo ""
echo "  🔍 Elasticsearch search (run after ~35s):"
echo "     kubectl exec -n $NAMESPACE elasticsearch-master-0 -- \\"
echo "       curl -s -k -u elastic:${ES_PASS:-Intangles@2026} 'https://localhost:9200/jaeger-span-*/_search?pretty&size=3'"
echo ""
echo "  📡 Agent pipeline metrics:"
echo "     kubectl exec -n $NAMESPACE deploy/otel-agent-collector -- wget -qO- http://localhost:8888/metrics | grep otelcol_"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop port-forwards${NC}"
echo ""

[[ ${#PF_PIDS[@]} -gt 0 ]] && wait "${PF_PIDS[0]}" || sleep infinity
