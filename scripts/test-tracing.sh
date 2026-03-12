#!/bin/bash
# End-to-end pipeline validation:
#
#   [1] Send OTLP trace → OTel Agent HTTP :4318
#   [2] Agent forwards  → OTel Gateway (loadbalancing by traceId)
#   [3] Gateway         → Jaeger Collector (OTLP gRPC :4317)  [after tail-sample decision]
#   [4] Jaeger          → Elasticsearch  (jaeger-span-YYYY-MM-DD index)
#   [5] Jaeger Query    → /api/traces/:traceId verified
#
# Usage: bash scripts/test-tracing.sh [namespace]

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

# ─── Step 3b: Baseline pipeline counters (before trace) ──────────────────────
echo -e "\n${BLUE}━━━ Step 3b: Baseline counters (before trace) ━━━━━━━━━━━━━━━━━━${NC}"

AGENT_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers \
  | grep "otel-agent-collector" | head -1 | awk '{print $1}' || true)
GW_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers \
  | grep "otel-gateway-collector-0" | awk '{print $1}' || true)

_counter() {
  local pod="$1" metric="$2"
  kubectl exec -n "$NAMESPACE" "$pod" -- \
    wget -qO- http://localhost:8888/metrics 2>/dev/null \
    | grep "^${metric}" | awk '{print $NF}' | head -1 || echo "0"
}

AGENT_SPANS_BEFORE=0
GW_SPANS_BEFORE=0
GW_EXPORTED_BEFORE=0

if [[ -n "$AGENT_POD" ]]; then
  AGENT_SPANS_BEFORE=$(_counter "$AGENT_POD" "otelcol_receiver_accepted_spans_total")
  echo "  Agent  receiver_accepted_spans : ${AGENT_SPANS_BEFORE}"
fi
if [[ -n "$GW_POD" ]]; then
  GW_SPANS_BEFORE=$(_counter "$GW_POD" "otelcol_receiver_accepted_spans_total")
  GW_EXPORTED_BEFORE=$(_counter "$GW_POD" "otelcol_exporter_sent_spans_total")
  echo "  Gateway receiver_accepted_spans: ${GW_SPANS_BEFORE}"
  echo "  Gateway exporter_sent_spans    : ${GW_EXPORTED_BEFORE}"
fi

# ─── Step 4: Send test trace ─────────────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 4: Send trace → OTel Agent HTTP :4318 ━━━━━━━━━━━━━━━━━━${NC}"

# Write Python sender to temp file — avoids all shell quoting issues
cat > /tmp/send_trace.py << 'PYEOF'
import json, time, subprocess, random, sys

t   = int(time.time() * 1e9)
tid = random.randbytes(16).hex()
s0  = random.randbytes(8).hex()
s1  = random.randbytes(8).hex()
s2  = random.randbytes(8).hex()

payload = {
  "resourceSpans": [{
    "resource": {"attributes": [
      {"key": "service.name",           "value": {"stringValue": "test-service"}},
      {"key": "service.version",        "value": {"stringValue": "1.0.0"}},
      {"key": "deployment.environment", "value": {"stringValue": "staging"}}
    ]},
    "scopeSpans": [{
      "scope": {"name": "test-tracer", "version": "1.0"},
      "spans": [
        {
          "traceId": tid, "spanId": s0,
          "name": "GET /api/orders", "kind": 2,
          "startTimeUnixNano": str(t),
          "endTimeUnixNano":   str(t + 500_000_000),
          "attributes": [
            {"key": "http.method",      "value": {"stringValue": "GET"}},
            {"key": "http.url",         "value": {"stringValue": "http://api.staging/api/orders"}},
            {"key": "http.status_code", "value": {"intValue": 200}},
            {"key": "http.route",       "value": {"stringValue": "/api/orders"}}
          ],
          "status": {"code": 1}
        },
        {
          "traceId": tid, "spanId": s1, "parentSpanId": s0,
          "name": "db.query SELECT orders", "kind": 3,
          "startTimeUnixNano": str(t + 10_000_000),
          "endTimeUnixNano":   str(t + 200_000_000),
          "attributes": [
            {"key": "db.system",    "value": {"stringValue": "postgresql"}},
            {"key": "db.statement", "value": {"stringValue": "SELECT * FROM orders WHERE user_id=?"}},
            {"key": "db.name",      "value": {"stringValue": "orders_db"}}
          ],
          "status": {"code": 1}
        },
        {
          "traceId": tid, "spanId": s2, "parentSpanId": s0,
          "name": "POST /api/payment", "kind": 2,
          "startTimeUnixNano": str(t + 220_000_000),
          "endTimeUnixNano":   str(t + 490_000_000),
          "attributes": [
            {"key": "http.method",       "value": {"stringValue": "POST"}},
            {"key": "http.status_code",  "value": {"intValue": 500}},
            {"key": "exception.message", "value": {"stringValue": "Payment gateway timeout"}}
          ],
          "status": {"code": 2, "message": "Payment gateway timeout"}
        }
      ]
    }]
  }]
}

with open("/tmp/otel_trace_payload.json", "w") as f:
    json.dump(payload, f)

r = subprocess.run(
    ["curl", "-s", "--max-time", "10",
     "-o", "/tmp/otel_trace_resp.json", "-w", "%{http_code}",
     "-X", "POST", "http://localhost:4318/v1/traces",
     "-H", "Content-Type: application/json",
     "-d", "@/tmp/otel_trace_payload.json"],
    capture_output=True, text=True
)
status = r.stdout.strip() or "curl_failed"

# Write shell-sourceable vars file
with open("/tmp/otel_trace_vars.sh", "w") as f:
    f.write(f'TRACE_ID="{tid}"\n')
    f.write(f'HTTP_STATUS="{status}"\n')
PYEOF

python3 /tmp/send_trace.py
# shellcheck source=/dev/null
source /tmp/otel_trace_vars.sh

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

cat > /tmp/send_metrics.py << 'PYEOF'
import json, time, subprocess

t = int(time.time() * 1e9)
payload = {
  "resourceMetrics": [{
    "resource": {"attributes": [
      {"key": "service.name",           "value": {"stringValue": "test-service"}},
      {"key": "deployment.environment", "value": {"stringValue": "staging"}}
    ]},
    "scopeMetrics": [{
      "scope": {"name": "test-meter", "version": "1.0"},
      "metrics": [
        {
          "name": "http_requests_total",
          "description": "Total HTTP requests",
          "sum": {
            "dataPoints": [{"attributes": [
              {"key": "method", "value": {"stringValue": "GET"}},
              {"key": "status", "value": {"stringValue": "200"}}
            ], "startTimeUnixNano": str(t), "timeUnixNano": str(t), "asDouble": 42}],
            "aggregationTemporality": 2, "isMonotonic": True
          }
        },
        {
          "name": "http_request_duration_seconds",
          "description": "HTTP request latency histogram",
          "gauge": {
            "dataPoints": [{"attributes": [
              {"key": "method", "value": {"stringValue": "GET"}}
            ], "timeUnixNano": str(t), "asDouble": 0.042}]
          }
        }
      ]
    }]
  }]
}
with open("/tmp/otel_metrics_payload.json", "w") as f:
    json.dump(payload, f)
r = subprocess.run(
    ["curl", "-s", "--max-time", "10",
     "-o", "/tmp/otel_metrics_resp.json", "-w", "%{http_code}",
     "-X", "POST", "http://localhost:4318/v1/metrics",
     "-H", "Content-Type: application/json",
     "-d", "@/tmp/otel_metrics_payload.json"],
    capture_output=True, text=True
)
print(r.stdout.strip() or "curl_failed")
PYEOF

METRICS_STATUS=$(python3 /tmp/send_metrics.py)

if [[ "$METRICS_STATUS" == "200" ]]; then
  echo -e "${GREEN}  ✓ Metrics accepted by Agent (HTTP 200)${NC}"
  echo "    metrics : http_requests_total{method=GET,status=200}=42"
  echo "              http_request_duration_seconds{method=GET}=0.042"
  echo "    Flow    : Agent → Gateway → prometheusremotewrite → vminsert → vmstorage"
else
  echo -e "${RED}  ✗ Agent returned HTTP ${METRICS_STATUS}${NC}"
  cat /tmp/otel_metrics_resp.json 2>/dev/null || true
fi

# ─── Step 5b: Pipeline counter delta (Agent → Gateway) ───────────────────────
echo -e "\n${BLUE}━━━ Step 5b: Hop 1 — Agent received? ━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
sleep 5  # let agent flush to gateway

if [[ -n "$AGENT_POD" ]]; then
  AGENT_SPANS_AFTER=$(_counter "$AGENT_POD" "otelcol_receiver_accepted_spans_total")
  DELTA=$(python3 -c "
a='${AGENT_SPANS_AFTER}'; b='${AGENT_SPANS_BEFORE}'
try:
    print(int(float(a)) - int(float(b)))
except:
    print('?')
")
  if [[ "$DELTA" != "0" && "$DELTA" != "?" ]]; then
    check "Agent accepted +${DELTA} spans (receiver_accepted_spans_total)" "true"
  else
    check "Agent counter unchanged (spans may have been dropped or not yet flushed)" "false"
    echo "    Before: ${AGENT_SPANS_BEFORE}  After: ${AGENT_SPANS_AFTER}"
    echo "    Check agent logs: kubectl logs -n ${NAMESPACE} ${AGENT_POD} --tail=20"
  fi
fi

# ─── Step 6: Tail-sampling wait ──────────────────────────────────────────────
echo -e "\n${BLUE}━━━ Step 6: Tail-sampling wait (Gateway decides in ~30s) ━━━━━━━━${NC}"
echo "  Policy: ERROR spans are ALWAYS sampled (POST /api/payment has status=ERROR)"
echo "  This trace WILL be kept. Waiting up to 45s for gateway decision..."
echo ""
WAITED=0
GW_EXPORTED_OK=false
while [[ $WAITED -lt 45 ]]; do
  sleep 5; WAITED=$((WAITED + 5))
  if [[ -n "$GW_POD" ]]; then
    GW_EXPORTED_NOW=$(_counter "$GW_POD" "otelcol_exporter_sent_spans_total")
    DELTA=$(python3 -c "
a='${GW_EXPORTED_NOW}'; b='${GW_EXPORTED_BEFORE}'
try:
    print(int(float(a)) - int(float(b)))
except:
    print('0')
")
    if [[ "$DELTA" != "0" && "$DELTA" != "?" ]]; then
      check "Hop 2 — Gateway exported +${DELTA} spans to Jaeger (${WAITED}s)" "true"
      GW_EXPORTED_OK=true
      break
    else
      echo -e "  ${YELLOW}⏳ ${WAITED}s — gateway exporter_sent_spans unchanged, still waiting...${NC}"
    fi
  else
    sleep 5; WAITED=$((WAITED + 5))
  fi
done
if [[ "$GW_EXPORTED_OK" != "true" ]]; then
  check "Gateway did not export spans within 45s" "false"
  echo "    Check gateway logs: kubectl logs -n ${NAMESPACE} ${GW_POD:-otel-gateway-collector-0} --tail=30"
fi

# ─── Step 7: Verify trace in Jaeger (with retry) ─────────────────────────────
echo -e "\n${BLUE}━━━ Step 7: Hop 3+4 — Jaeger Query + Elasticsearch ━━━━━━━━━━━━━${NC}"
echo "  Polling Jaeger /api/traces/${TRACE_ID} (up to 40s)..."

JAEGER_RESULT=0
for attempt in 1 2 3 4 5 6 7 8; do
  sleep 5
  JAEGER_RESULT=$(curl -sf --max-time 5 \
    "http://localhost:16686/api/traces/${TRACE_ID}" 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
spans = sum(len(t.get('spans',[])) for t in d.get('data',[]))
print(spans)
" 2>/dev/null || echo "0")
  if [[ "$JAEGER_RESULT" -ge 1 ]]; then
    check "Hop 3 — Trace visible in Jaeger Query (${JAEGER_RESULT} spans, attempt ${attempt})" "true"
    break
  fi
  echo -e "  ${YELLOW}  attempt ${attempt}: not yet in Jaeger...${NC}"
done

if [[ "$JAEGER_RESULT" -lt 1 ]]; then
  check "Trace NOT found in Jaeger after 40s" "false"
  echo "    Manual retry: curl -s 'http://localhost:16686/api/traces/${TRACE_ID}' | python3 -m json.tool"
fi

# ─── Step 7b: Verify trace in Elasticsearch ──────────────────────────────────
echo ""
TODAY=$(date -u +%Y-%m-%d)
ES_PASS=$(kubectl get secret -n "$NAMESPACE" elasticsearch-credentials \
  -o jsonpath='{.data.ELASTIC_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "Intangles@2026")

ES_RESULT=$(kubectl exec -n "$NAMESPACE" elasticsearch-master-0 -- \
  curl -sk -u "elastic:${ES_PASS}" \
  "https://localhost:9200/jaeger-span-${TODAY}/_search?q=traceID:${TRACE_ID}&size=3" \
  2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
hits = d.get('hits', {}).get('total', {})
count = hits.get('value', 0) if isinstance(hits, dict) else hits
print(count)
" 2>/dev/null || echo "0")

if [[ "$ES_RESULT" -ge 1 ]]; then
  check "Hop 4 — Span stored in Elasticsearch jaeger-span-${TODAY} (${ES_RESULT} docs)" "true"
else
  check "Hop 4 — Span NOT found in Elasticsearch jaeger-span-${TODAY}" "false"
  echo "    Manual check:"
  echo "    kubectl exec -n ${NAMESPACE} elasticsearch-master-0 -- \\"
  echo "      curl -sk -u elastic:${ES_PASS} \\"
  echo "      'https://localhost:9200/jaeger-span-${TODAY}/_search?q=traceID:${TRACE_ID}&pretty'"
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

# ─── Step 10: Elasticsearch indices overview ─────────────────────────────────
echo -e "\n${BLUE}━━━ Step 10: Elasticsearch — Jaeger indices overview ━━━━━━━━━━━━${NC}"
ES_PASS=$(kubectl get secret -n "$NAMESPACE" elasticsearch-credentials \
  -o jsonpath='{.data.ELASTIC_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "Intangles@2026")
kubectl exec -n "$NAMESPACE" elasticsearch-master-0 -- \
  curl -s -k -u "elastic:${ES_PASS}" \
  "https://localhost:9200/_cat/indices/jaeger-*?v&h=health,status,index,docs.count&s=index:desc" \
  2>/dev/null | head -10 \
  || echo "  (elasticsearch not reachable)"

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
echo -e "${BLUE}━━━ Pipeline validation summary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  [1] App  ──OTLP HTTP──▶  OTel Agent   (localhost:4318)            HTTP ${HTTP_STATUS}"
if [[ -n "$AGENT_POD" ]]; then
  AGENT_SPANS_FINAL=$(_counter "$AGENT_POD" "otelcol_receiver_accepted_spans_total")
  echo "  [2] Agent──loadbalance──▶  OTel Gateway   (by traceId)               counter=${AGENT_SPANS_FINAL}"
fi
if [[ -n "$GW_POD" ]]; then
  GW_EXPORTED_FINAL=$(_counter "$GW_POD" "otelcol_exporter_sent_spans_total")
  echo "  [3] Gateway──OTLP gRPC──▶  Jaeger Collector                          counter=${GW_EXPORTED_FINAL}"
fi
echo "  [4] Jaeger──────────────▶  Elasticsearch  jaeger-span-$(date -u +%Y-%m-%d)  hits=${ES_RESULT:-0}"
echo "  [5] Jaeger Query────────▶  /api/traces/:id                           spans=${JAEGER_RESULT:-0}"
echo ""
echo -e "${GREEN}Trace ID: ${TRACE_ID}${NC}"
echo "  Jaeger UI:          http://localhost:16686/trace/${TRACE_ID}"
echo "  Jaeger API:         http://localhost:16686/api/traces/${TRACE_ID}"
echo "  Kibana Discover:    http://localhost:5601  →  jaeger-span-*  →  traceID: ${TRACE_ID}"
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
echo "    user: elastic   password: ${ES_PASS:-Intangles@2026}"
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
echo "    curl -sk -u elastic:${ES_PASS:-Intangles@2026} \\"
echo "    'https://localhost:9200/jaeger-span-*/_search?pretty&size=3&q=traceID:${TRACE_ID}'"
echo ""
echo "  # Stream gateway logs (real-time)"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=otel-gateway -f --prefix"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop port-forwards${NC}"
echo ""

[[ ${#PF_PIDS[@]} -gt 0 ]] && wait "${PF_PIDS[0]}" || while true; do sleep 86400; done
