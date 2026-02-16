#!/bin/bash
# Test OpenTelemetry → Jaeger → Elasticsearch workflow

set -e

echo "=== Testing Distributed Tracing Pipeline ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Check all services are healthy
echo -e "${YELLOW}Step 1: Checking service health...${NC}"
kubectl get pods -n telemetry
echo ""

# 2. Port forward Jaeger UI
echo -e "${YELLOW}Step 2: Port-forwarding Jaeger UI to localhost:16686${NC}"
kubectl port-forward -n telemetry svc/jaeger-query 16686:16686 &
PF_PID=$!
sleep 3

# 3. Port forward OTel Collector for sending test traces
echo -e "${YELLOW}Step 3: Port-forwarding OTel Collector OTLP HTTP to localhost:4318${NC}"
kubectl port-forward -n telemetry svc/otel-collector 4318:4318 &
PF_PID2=$!
sleep 3

# 4. Send test traces
echo -e "${YELLOW}Step 4: Sending test trace to OTel Collector...${NC}"
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"stringValue": "test-service"}
        }]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "5B8EFFF798038103D269B633813FC60C",
          "spanId": "EEE19B7EC3C1B174",
          "name": "test-operation",
          "kind": 1,
          "startTimeUnixNano": "1544712660000000000",
          "endTimeUnixNano": "1544712661000000000",
          "attributes": [{
            "key": "http.method",
            "value": {"stringValue": "GET"}
          }, {
            "key": "http.url",
            "value": {"stringValue": "http://example.com/test"}
          }]
        }]
      }]
    }]
  }'

echo ""
echo -e "${GREEN}✓ Test trace sent successfully!${NC}"
echo ""

# 5. Check Elasticsearch indices
echo -e "${YELLOW}Step 5: Checking Elasticsearch indices...${NC}"
kubectl exec -n telemetry elasticsearch-master-0 -- curl -s http://localhost:9200/_cat/indices?v 2>/dev/null | grep -E "health|jaeger" || echo "Waiting for indices to be created..."
echo ""

# 6. Instructions
echo -e "${GREEN}=== Test Complete! ===${NC}"
echo ""
echo "📊 Jaeger UI: http://localhost:16686"
echo "   - Service: test-service"
echo "   - Operation: test-operation"
echo ""
echo "🔍 To check Elasticsearch directly:"
echo "   kubectl exec -n telemetry elasticsearch-master-0 -- curl -s 'http://localhost:9200/jaeger-span-*/_search?pretty&size=5'"
echo ""
echo "📈 OTel Collector metrics:"
echo "   curl http://localhost:8888/metrics"
echo ""
echo "🛑 To stop port-forwarding:"
echo "   kill $PF_PID $PF_PID2"
echo ""
echo "Press Ctrl+C when done testing..."

# Keep script running
wait $PF_PID
