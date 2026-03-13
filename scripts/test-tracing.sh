#!/bin/bash
# End-to-end pipeline test:
#   App → OTel Agent (DaemonSet) → OTel Gateway (tail-sampling)
#         ├─ Traces  → Jaeger (OTLP gRPC) → Elasticsearch
#         └─ Metrics → VictoriaMetrics vminsert (prometheusremotewrite)
#                      → vmselect / VMUI / Grafana

set -euo pipefail

NAMESPACE="${1:-telemetry}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper: print check result
check() {
  local label="$1" ok="$2"
  if [[ "$ok" == "true" ]]; then
    echo -e "${GREEN}  ✓ ${label}${NC}"
  else
    echo -e "${RED}  ✗ ${label}${NC}"
  fi
}

cleanup() {
  echo ""
  echo -e "${YELLOW}Stopping port-forwards...${NC}"
  [[ ${#PF_PIDS[@]} -gt 0 ]] && kill "${PF_PIDS[@]}" 2>/dev/null || true
  for _port in 4318 4317 16686 8481 8480 3000 9090 9093 5601; do
    lsof -ti "tcp:${_port}" 2>/dev/null | xargs kill -9 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

PF_PIDS=()

port_forward() {
  local label="$1" svc="$2" local_port="$3" remote_port="$4"
  echo -e "${CYAN}  ↳ ${label}: localhost:${local_port} -> ${svc}:${remote_port}${NC}"
  kubectl port-forward -n "$NAMESPACE" "svc/${svc}" "${local_port}:${remote_port}" \
    --address 127.0.0.1 >/dev/null 2>&1 &
  PF_PIDS+=($!)
}

# ─── Step 1: Component health ─────────────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 1: Component health ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "\n  Pods:"
kubectl get pods -n "$NAMESPACE" --no-headers \
  | grep -E "otel-agent|otel-gateway|jaeger|grafana|prometheus-[0-9]|elasticsearch-master|kibana|vmstorage|vminsert|vmselect|vmagent|vm-operator" \
  | awk '{
      status=$3; ready=$2
      color="\033[0;32m"
      if (status != "Running") color="\033[0;31m"
      else if (ready != "1/1" && ready != "2/2" && ready != "3/3") color="\033[1;33m"
      printf "  " color "%-52s %-8s %s\033[0m\n", $1, ready, status
    }' || true

echo -e "\n  OTelCollectors:"
kubectl get opentelemetrycollectors -n "$NAMESPACE" --no-headers 2>/dev/null \
  | awk '{printf "  %-28s mode=%-10s ready=%s\n", $1, $2, $4}' || true

echo -e "\n  VMCluster:"
kubectl get vmcluster -n "$NAMESPACE" --no-headers 2>/dev/null \
  | awk '{printf "  %-28s status=%s\n", $1, $2}' || true

# ─── Step 2: Port-forwards ────────────────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 2: Port-forwards ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
# Kill any stale port-forwards (by name AND by each port) to avoid
# zombie tunnels that accept connections but hang without forwarding.
pkill -f "kubectl port-forward" 2>/dev/null || true
for _port in 4318 4317 16686 8481 8480 3000 9090 9093 5601; do
  lsof -ti "tcp:${_port}" 2>/dev/null | xargs kill -9 2>/dev/null || true
done
sleep 3
port_forward "OTel Agent HTTP"      "otel-agent-collector"               4318   4318
port_forward "OTel Agent gRPC"      "otel-agent-collector"               4317   4317
port_forward "Jaeger UI"            "jaeger-query"                       16686  16686
port_forward "VMSelect (VMUI)"      "vmselect-vmcluster"                 8481   8481
port_forward "VMInsert"             "vminsert-vmcluster"                 8480   8480
port_forward "Grafana"              "kube-prometheus-stack-grafana"      3000   80
port_forward "Prometheus"           "kube-prometheus-stack-prometheus"   9090   9090
port_forward "Alertmanager"         "kube-prometheus-stack-alertmanager" 9093   9093
port_forward "Kibana"               "kibana-kibana"                      5601   5601
sleep 10

# ─── Step 3: Backend health checks ────────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 3: Backend health checks ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

AGENT_OK=$(curl -sf --max-time 3 -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 && echo true || echo false)
check "OTel Agent HTTP (4318)" "$AGENT_OK"

JAEGER_OK=$(curl -sf --max-time 3 http://localhost:16686/ >/dev/null 2>&1 && echo true || echo false)
check "Jaeger UI (16686)" "$JAEGER_OK"

VMSELECT_OK=$(curl -sf --max-time 3 http://localhost:8481/health >/dev/null 2>&1 && echo true || echo false)
check "VMSelect health (8481)" "$VMSELECT_OK"

VMINSERT_OK=$(curl -sf --max-time 3 http://localhost:8480/health >/dev/null 2>&1 && echo true || echo false)
check "VMInsert health (8480)" "$VMINSERT_OK"

GRAFANA_OK=$(curl -sf --max-time 3 http://localhost:3000/api/health >/dev/null 2>&1 && echo true || echo false)
check "Grafana (3000)" "$GRAFANA_OK"

# ─── Step 4: Send test trace ─────────────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 4: Send test trace via OTel Agent ━━━━━━━━━━━━━━━━━━━━━━${NC}"

NOW_NS=$(python3 -c "import time; print(int(time.time() * 1e9))")
TRACE_ID=$(openssl rand -hex 16)
SPAN_ID=$(openssl rand -hex 8)
CHILD_SPAN_ID=$(openssl rand -hex 8)
ERROR_SPAN_ID=$(openssl rand -hex 8)

HTTP_STATUS=$(curl -s --max-time 10 -o /tmp/otel_trace_resp.json -w "%{http_code}" \
  -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d "{
    \"resourceSpans\": [{
      \"resource\": {
        \"attributes\": [
          {\"key\": \"service.name\",           \"value\": {\"stringValue\": \"test-service\"}},
          {\"key\": \"service.version\",        \"value\": {\"stringValue\": \"1.0.0\"}},
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
            \"endTimeUnixNano\": \"$(python3 -c "import time; print(int(time.time() * 1e9) + 500_000_000)")\",
            \"attributes\": [
              {\"key\": \"http.method\",      \"value\": {\"stringValue\": \"GET\"}},
              {\"key\": \"http.url\",         \"value\": {\"stringValue\": \"http://api.staging/api/orders\"}},
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
              {\"key\": \"db.system\",    \"value\": {\"stringValue\": \"postgresql\"}},
              {\"key\": \"db.statement\", \"value\": {\"stringValue\": \"SELECT * FROM orders WHERE user_id=?\"}},
              {\"key\": \"db.name\",      \"value\": {\"stringValue\": \"orders_db\"}}
            ],
            \"status\": {\"code\": 1}
          },
          {
            \"traceId\": \"${TRACE_ID}\",
            \"spanId\": \"${ERROR_SPAN_ID}\",
            \"parentSpanId\": \"${SPAN_ID}\",
            \"name\": \"POST /api/payment\",
            \"kind\": 2,
            \"startTimeUnixNano\": \"$(python3 -c "import time; print(int(time.time() * 1e9) + 220_000_000)")\",
            \"endTimeUnixNano\": \"$(python3 -c "import time; print(int(time.time() * 1e9) + 490_000_000)")\",
            \"attributes\": [
              {\"key\": \"http.method\",      \"value\": {\"stringValue\": \"POST\"}},
              {\"key\": \"http.status_code\", \"value\": {\"intValue\": 500}},
              {\"key\": \"exception.message\",\"value\": {\"stringValue\": \"Payment gateway timeout\"}}
            ],
            \"status\": {\"code\": 2, \"message\": \"Payment gateway timeout\"}
          }
        ]
      }]
    }]
  }" 2>/dev/null) || HTTP_STATUS="curl_failed"

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo -e "${GREEN}  ✓ Trace accepted by Agent (HTTP 200)${NC}"
  echo "    traceId : ${TRACE_ID}"
  echo "    spans   : GET /api/orders → db.query (child) + POST /api/payment (error, always sampled)"
else
  echo -e "${RED}  ✗ Agent returned HTTP ${HTTP_STATUS}${NC}"
  cat /tmp/otel_trace_resp.json 2>/dev/null || true
fi

# ─── Step 5: Send test metrics ────────────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 5: Send test metrics via OTel Agent ━━━━━━━━━━━━━━━━━━━━${NC}"

METRIC_NOW_NS=$(python3 -c "import time; print(int(time.time() * 1e9))")
METRICS_STATUS=$(curl -s --max-time 10 -o /tmp/otel_metrics_resp.json -w "%{http_code}" \
  -X POST http://localhost:4318/v1/metrics \
  -H "Content-Type: application/json" \
  -d "{
    \"resourceMetrics\": [{
      \"resource\": {
        \"attributes\": [
          {\"key\": \"service.name\",           \"value\": {\"stringValue\": \"test-service\"}},
          {\"key\": \"deployment.environment\", \"value\": {\"stringValue\": \"staging\"}}
        ]
      },
      \"scopeMetrics\": [{
        \"scope\": {\"name\": \"test-meter\", \"version\": \"1.0\"},
        \"metrics\": [
          {
            \"name\": \"http_requests_total\",
            \"description\": \"Total HTTP requests\",
            \"sum\": {
              \"dataPoints\": [{
                \"attributes\": [
                  {\"key\": \"method\", \"value\": {\"stringValue\": \"GET\"}},
                  {\"key\": \"status\", \"value\": {\"stringValue\": \"200\"}}
                ],
                \"startTimeUnixNano\": \"${METRIC_NOW_NS}\",
                \"timeUnixNano\": \"${METRIC_NOW_NS}\",
                \"asDouble\": 42
              }],
              \"aggregationTemporality\": 2,
              \"isMonotonic\": true
            }
          },
          {
            \"name\": \"http_request_duration_seconds\",
            \"description\": \"HTTP request latency histogram\",
            \"gauge\": {
              \"dataPoints\": [{
                \"attributes\": [{\"key\": \"method\", \"value\": {\"stringValue\": \"GET\"}}],
                \"timeUnixNano\": \"${METRIC_NOW_NS}\",
                \"asDouble\": 0.042
              }]
            }
          }
        ]
      }]
    }]
  }" 2>/dev/null) || METRICS_STATUS="curl_failed"

if [[ "$METRICS_STATUS" == "200" ]]; then
  echo -e "${GREEN}  ✓ Metrics accepted by Agent (HTTP 200)${NC}"
  echo "    metrics : http_requests_total{method=GET,status=200}=42"
  echo "              http_request_duration_seconds{method=GET}=0.042"
  echo "    Flow    : Agent → Gateway → prometheusremotewrite → vminsert → vmstorage"
else
  echo -e "${RED}  ✗ Agent returned HTTP ${METRICS_STATUS}${NC}"
  cat /tmp/otel_metrics_resp.json 2>/dev/null || true
fi

# ─── Step 6: Tail-sampling note ──────────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 6: Tail-sampling (35s wait) ━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Gateway waits 30s before deciding which traces to sample:"
echo "  • Error spans   → always kept  (POST /api/payment span qualifies)"
echo "  • Slow (>2s)    → always kept"
echo "  • Normal traces → 50% sampled"
echo "  Waiting 35s before querying Jaeger and VictoriaMetrics..."
sleep 35

# ─── Step 7: Verify trace in Jaeger ──────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 7: Verify trace in Jaeger ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
JAEGER_RESULT=$(curl -sf --max-time 5 \
  "http://localhost:16686/api/traces/${TRACE_ID}" 2>/dev/null \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
spans = sum(len(t.get('spans',[])) for t in d.get('data',[]))
print(spans)
" 2>/dev/null || echo "0")

if [[ "$JAEGER_RESULT" -ge 1 ]]; then
  check "Trace found in Jaeger (${JAEGER_RESULT} spans)" "true"
else
  check "Trace not yet in Jaeger" "false"
  echo "    Retry: curl -s 'http://localhost:16686/api/traces/${TRACE_ID}' | python3 -m json.tool"
fi

# ─── Step 8: Verify metrics in VictoriaMetrics ────────────────────────────────
echo -e "\n${BLUE}━━━ Step 8: Verify metrics in VictoriaMetrics ━━━━━━━━━━━━━━━━━━━${NC}"

VM_RESULT=$(curl -sf --max-time 5 \
  "http://localhost:8481/select/0/prometheus/api/v1/query?query=http_requests_total%7Bservice_name%3D%22test-service%22%7D" \
  2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('data', {}).get('result', [])
print(len(results))
" 2>/dev/null || echo "0")

if [[ "$VM_RESULT" -ge 1 ]]; then
  check "http_requests_total found in VictoriaMetrics (${VM_RESULT} series)" "true"
else
  # Broad scan for any OTel/HTTP metrics
  VM_BROAD=$(curl -sf --max-time 5 \
    'http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values' \
    2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
names = [n for n in d.get('data', []) if 'http_request' in n or 'otelcol' in n]
print(', '.join(names[:8]) if names else 'none yet')
" 2>/dev/null || echo "not reachable")
  echo -e "${YELLOW}  ⚠ http_requests_total not yet in VM (batch interval ~10s)${NC}"
  echo "    OTel/HTTP metrics already in VM: ${VM_BROAD}"
fi

# Check OTel collector self-metrics forwarded via prometheusremotewrite
OTELCOL_IN_VM=$(curl -sf --max-time 5 \
  'http://localhost:8481/select/0/prometheus/api/v1/query?query=otelcol_receiver_accepted_spans_total' \
  2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('data', {}).get('result', [])
if results:
    val = results[0].get('value', [None, '?'])[1]
    print('value={} ({} series)'.format(val, len(results)))
else:
    print('not found (pipeline may still be propagating)')
" 2>/dev/null || echo "not reachable")
echo "  otelcol_receiver_accepted_spans_total in VM: ${OTELCOL_IN_VM}"

# ─── Step 9: Gateway pipeline counters ─────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 9: Gateway pipeline counters ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
GW_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers \
  | grep "otel-gateway-collector-0" | awk '{print $1}' || true)
if [[ -n "$GW_POD" ]]; then
  kubectl exec -n "$NAMESPACE" "$GW_POD" -- \
    wget -qO- http://localhost:8888/metrics 2>/dev/null \
    | grep -E "^otelcol_(receiver_accepted|processor_dropped|exporter_sent|exporter_queue)" \
    | sort | sed 's/^/  /' || echo "  (metrics endpoint not ready)"
else
  echo "  (no gateway pod found)"
fi

# ─── Step 10: Elasticsearch index check ──────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 10: Elasticsearch — Jaeger indices ━━━━━━━━━━━━━━━━━━━━━${NC}"
ES_PASS=$(kubectl get secret -n "$NAMESPACE" elasticsearch-credentials \
  -o jsonpath='{.data.ELASTIC_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
kubectl exec -n "$NAMESPACE" elasticsearch-master-0 -- \
  curl -s -k -u "elastic:${ES_PASS}" \
  "https://localhost:9200/_cat/indices/jaeger-*?v&h=health,status,index,docs.count" \
  2>/dev/null | head -20 \
  || echo "  (elasticsearch not reachable or no jaeger indices yet)"

# ─── Step 11: OTel Agent pipeline counters ────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 11: OTel Agent pipeline counters ━━━━━━━━━━━━━━━━━━━━━━━${NC}"
AGENT_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers \
  | grep "otel-agent-collector" | head -1 | awk '{print $1}' || true)
if [[ -n "$AGENT_POD" ]]; then
  kubectl exec -n "$NAMESPACE" "$AGENT_POD" -- \
    wget -qO- http://localhost:8888/metrics 2>/dev/null \
    | grep -E "^otelcol_(receiver_accepted|exporter_sent)" \
    | sort | sed 's/^/  /' || echo "  (metrics endpoint not ready)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
GRAFANA_PASS=$(kubectl get secret -n "$NAMESPACE" kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not found>")

echo ""
echo -e "${BLUE}Pipeline:${NC}"
echo "  Traces  : App --[OTLP]--> Agent --[loadbalancing/traceId]--> Gateway --[otlp/jaeger]--> Jaeger --> ES"
echo "  Metrics : App --[OTLP]--> Agent --[otlp/gateway]-----------> Gateway --[prometheusremotewrite]--> vminsert --> vmstorage"
echo ""
echo -e "${GREEN}Endpoints (port-forwards active):${NC}"
echo ""
echo "  Jaeger            http://localhost:16686"
echo "    traceId  : ${TRACE_ID}"
echo "    service  : test-service  (ERROR span always sampled by tail-sampler)"
echo ""
echo "  VictoriaMetrics   http://localhost:8481/select/0/vmui/"
echo "  VictoriaMetrics   https://vm.test.intangles.com/select/0/vmui/"
echo "    query: http_requests_total"
echo "    query: otelcol_receiver_accepted_spans_total"
echo ""
echo "  Grafana           http://localhost:3000"
echo "    user: admin   password: ${GRAFANA_PASS}"
echo "    Datasource -> VictoriaMetrics"
echo "    URL: http://vmselect-vmcluster.telemetry.svc.cluster.local:8481/select/0/prometheus"
echo ""
echo "  Prometheus        http://localhost:9090"
echo "  Alertmanager      http://localhost:9093"
echo ""
echo "  Kibana            http://localhost:5601"
echo "    user: elastic   password: ${ES_PASS:-<set ES_PASS env var>}"
echo "    Discover -> jaeger-span-* -> filter: traceID: ${TRACE_ID}"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  # Did the metric reach vminsert?"
echo "  curl -s 'http://localhost:8481/select/0/prometheus/api/v1/query?query=http_requests_total' | python3 -m json.tool"
echo ""
echo "  # All metric names stored in VictoriaMetrics"
echo "  curl -s 'http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values' | python3 -m json.tool"
echo ""
echo "  # Find trace in Elasticsearch"
echo "  kubectl exec -n ${NAMESPACE} elasticsearch-master-0 -- \\"
echo "    curl -sk -u elastic:${ES_PASS:-<set ES_PASS env var>} \\"
echo "    'https://localhost:9200/jaeger-span-*/_search?pretty&size=3&q=traceID:${TRACE_ID}'"
echo ""
echo "  # Stream gateway logs (real-time)"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=otel-gateway -f --prefix"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop port-forwards${NC}"
echo ""

[[ ${#PF_PIDS[@]} -gt 0 ]] && wait "${PF_PIDS[0]}" || while true; do sleep 86400; done
