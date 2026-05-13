# Dashboard Testing & Validation Guide

This document describes how to validate that the Grafana dashboards and metrics are working correctly.

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Metric Validation](#metric-validation)
3. [Dashboard Validation](#dashboard-validation)
4. [Alert Testing](#alert-testing)
5. [Load Testing](#load-testing)
6. [Sanity Checks](#sanity-checks)

## Pre-Deployment Checklist

### ✅ Before Starting Services

```bash
# 1. Verify Docker is running
docker ps
# Output: Shows running containers

# 2. Check disk space
df -h .
# Output: At least 5GB free for volumes

# 3. Verify ports are available
lsof -i :3000  # Should be empty (Grafana port)
lsof -i :9090  # Should be empty (Prometheus port)
lsof -i :8000  # Should be empty (AI Gateway port)
```

### ✅ Service Startup

```bash
# Start services
docker-compose -f dashboards/docker-compose.yml up -d

# Wait 10 seconds for services to initialize
sleep 10

# Check service health
docker-compose ps
# Expected: 2 services, status=healthy or Up

# Validate endpoints
curl -s http://localhost:9090/-/healthy | head -1
# Expected: HTTP 200

curl -s http://localhost:3000/api/health | jq .
# Expected: {"status":"ok"}
```

## Metric Validation

### 1. Check Prometheus Targets

```bash
# Fetch active targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .job, state: .state, labels: .labels.instance}'

# Expected output:
# {
#   "job": "prometheus",
#   "state": "up",
#   "labels": {"instance": "localhost:9090"}
# }
# {
#   "job": "ai-gateway",
#   "state": "up",
#   "labels": {"instance": "localhost:8000"}
# }
```

**Troubleshooting target failures:**
```bash
# Check if AI Gateway is running
curl -s http://localhost:8000/health | jq .

# Check if Prometheus can reach it
docker logs prometheus | grep "ai-gateway" | head -5
```

### 2. Verify RAG Metrics Exist

```bash
# Get list of all rag metrics
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data[] | select(startswith("ai_gateway_rag_"))'

# Expected: At least 5 metrics
# - ai_gateway_rag_ingestion_runs_total
# - ai_gateway_rag_ingestion_duration_seconds
# - ai_gateway_rag_chunks_embedded_total
# - ai_gateway_rag_qdrant_upsert_total
# - ai_gateway_rag_retrieval_latency_seconds
```

### 3. Query Individual Metrics

**Test 1: Ingestion runs counter**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=ai_gateway_rag_ingestion_runs_total' | jq '.data.result[] | {metric: .metric, value: .value}'

# Expected: Non-empty results with status="success" or "failed"
```

**Test 2: Ingestion duration histogram**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=ai_gateway_rag_ingestion_duration_seconds_bucket' | jq '.data.result | length'

# Expected: > 0 (indicating histogram buckets exist)
```

**Test 3: Chunks embedded counter**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=ai_gateway_rag_chunks_embedded_total' | jq '.data.result[] | {kb: .metric.kb, value: .value}'

# Expected: Results grouped by KB
```

**Test 4: Vector store upserts**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=ai_gateway_rag_qdrant_upsert_total' | jq '.data.result[] | {kb: .metric.kb, status: .metric.status, value: .value}'

# Expected: Results with status="success" or "failed"
```

**Test 5: Retrieval latency histogram**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=ai_gateway_rag_retrieval_latency_seconds_bucket' | jq '.data.result | length'

# Expected: > 0 (indicating histogram buckets exist)
```

### 4. Test PromQL Calculations

```bash
# Test: Ingestion success rate (should be 100% if all successful)
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(ai_gateway_rag_ingestion_runs_total%7Bstatus=%22success%22%7D%5B5m%5D))%20/%20sum(rate(ai_gateway_rag_ingestion_runs_total%5B5m%5D))' | jq '.data.result[0].value'

# Expected: [timestamp, "0.99"] to [timestamp, "1.0"] or no data yet

# Test: Retrieval p95 latency in milliseconds
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,%20rate(ai_gateway_rag_retrieval_latency_seconds_bucket%5B5m%5D))%20*%201000' | jq '.data.result[0].value'

# Expected: Value in milliseconds (e.g., "50" for 50ms)

# Test: Upsert success rate
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(ai_gateway_rag_qdrant_upsert_total%7Bstatus=%22success%22%7D%5B5m%5D))%20/%20sum(rate(ai_gateway_rag_qdrant_upsert_total%5B5m%5D))' | jq '.data.result[0].value'

# Expected: 0.95 - 1.0 (95-100%)
```

## Dashboard Validation

### 1. Import Test

```bash
# Create test dashboard request
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @dashboards/rag-kb-overview.json

# Expected: HTTP 200 with dashboard ID
```

### 2. Dashboard Load Test

```bash
# Get list of all dashboards
curl -s http://localhost:3000/api/dashboards/search | jq '.[] | {title: .title, tags: .tags, folderTitle: .folderTitle}'

# Expected: At least 5 RAG dashboards listed
```

### 3. Individual Dashboard Validation

**For each dashboard file:**

```bash
# Validate JSON structure
jq empty dashboards/rag-*.json
# Expected: No output means valid JSON

# Check required fields
jq '.title, .panels | length, .refresh' dashboards/rag-kb-overview.json
# Expected:
# "RAG KB Overview"
# 9
# "30s"
```

### 4. Dashboard Panel Validation

```bash
# Check that all panels have valid queries
jq '.panels[] | {title: .title, query: .targets[0].expr | length}' dashboards/rag-kb-overview.json

# Expected: Each panel should have a query (length > 0)
```

### 5. Load Dashboard in UI

1. Open http://localhost:3000
2. Login: admin/admin
3. Navigate to dashboards:
   ```
   Dashboards → Browse → RAG
   ```
4. For each dashboard:
   - ✅ Title displays correctly
   - ✅ All panels load (no red errors)
   - ✅ Time range selector works
   - ✅ Refresh works (30s auto-refresh)
   - ✅ Links to other dashboards work

## Alert Testing

### 1. Alert Rules Validation

```bash
# Validate YAML syntax
yamllint dashboards/rag-alerts.yml
# Expected: No output (or no errors if yamllint not installed)

# Check alert count
grep "alert:" dashboards/rag-alerts.yml | wc -l
# Expected: 12 alerts
```

### 2. Prometheus Alert Status

```bash
# Get alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[0].rules[] | {name: .name, state: .state}'

# Expected: At least 1 group with 12+ rules, mostly "inactive" initially
```

### 3. Trigger Test Alert (Optional)

To test alerting, you can artificially trigger an alert:

```bash
# 1. Verify current ingestion rate
curl -s 'http://localhost:9090/api/v1/query?query=rate(ai_gateway_rag_ingestion_runs_total[5m])' | jq

# 2. Manual trigger (if AI Gateway supports test endpoint):
curl -X POST http://localhost:8000/test/ingestion/fail?rate=100

# 3. Wait 5 minutes, then check Prometheus
curl -s http://localhost:9090/api/v1/alerts | jq '.data[] | {alertname: .labels.alertname, state: .state}'

# Expected: Alert "IngestionSuccessRateLow" should be firing
```

## Load Testing

### 1. Generate Test Data

```bash
# Script to generate ingestion metrics
cat > /tmp/test_ingestion.sh << 'EOF'
#!/bin/bash
for i in {1..100}; do
  curl -X POST http://localhost:8000/v1/rag/ingest \
    -H "Content-Type: application/json" \
    -d '{
      "kb_id": "test_kb_'$((RANDOM % 5))'",
      "content": "Document '$i' with test data for ingestion"
    }' &
  
  # Rate limit: 10 requests/sec
  sleep 0.1
done
wait
EOF

chmod +x /tmp/test_ingestion.sh
/tmp/test_ingestion.sh
```

### 2. Monitor Metrics During Load

```bash
# Watch ingestion rate in real-time
watch -n 1 'curl -s "http://localhost:9090/api/v1/query?query=rate(ai_gateway_rag_ingestion_runs_total[1m])" | jq ".data.result[0].value"'

# Expected: Positive numbers increasing as requests are processed
```

### 3. Dashboard Performance

```bash
# Time dashboard load
time curl -s http://localhost:3000/api/dashboards/db/rag-kb-overview | jq > /dev/null

# Expected: < 1 second
```

## Sanity Checks

### Quick Validation Script

```bash
#!/bin/bash
set -e

echo "🔍 Running Grafana Dashboard Sanity Checks..."

# 1. Service health
echo "✓ Checking services..."
curl -s http://localhost:9090/-/healthy > /dev/null || { echo "❌ Prometheus not healthy"; exit 1; }
curl -s http://localhost:3000/api/health | jq '.status' | grep -q ok || { echo "❌ Grafana not healthy"; exit 1; }

# 2. Prometheus targets
echo "✓ Checking Prometheus targets..."
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.state=="down")' | jq -e . >/dev/null 2>&1 && { echo "❌ Down targets found"; exit 1; }

# 3. RAG metrics
echo "✓ Checking RAG metrics..."
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data | map(select(startswith("ai_gateway_rag_"))) | length' | grep -q -E "[5-9]|[0-9]{2,}" || { echo "❌ Missing RAG metrics"; exit 1; }

# 4. Dashboard files
echo "✓ Checking dashboard files..."
for dashboard in rag-kb-overview rag-ingestion-metrics rag-retrieval-metrics rag-vector-store rag-performance-slos; do
  jq empty "dashboards/${dashboard}.json" || { echo "❌ Invalid JSON in ${dashboard}.json"; exit 1; }
done

# 5. Alert rules
echo "✓ Checking alert rules..."
grep "alert:" dashboards/rag-alerts.yml | wc -l | grep -q 12 || { echo "❌ Alert count mismatch"; exit 1; }

# 6. Metrics returning data
echo "✓ Checking metric data..."
METRIC_COUNT=$(curl -s http://localhost:9090/api/v1/query?query=ai_gateway_rag_ingestion_runs_total | jq '.data.result | length')
[ "$METRIC_COUNT" -gt 0 ] || { echo "⚠️  No active metric data (expected for fresh start)"; }

echo ""
echo "✅ All sanity checks passed!"
echo ""
echo "Dashboard URLs:"
echo "  • Grafana: http://localhost:3000"
echo "  • Prometheus: http://localhost:9090"
echo ""
```

Save and run:
```bash
chmod +x test_dashboards.sh
./test_dashboards.sh
```

### Manual Verification Checklist

- [ ] Prometheus targets: All "up" state
- [ ] RAG metrics: At least 5 metrics visible
- [ ] Grafana: Accessible and healthy
- [ ] Dashboards: All 5 dashboards load without errors
- [ ] Panels: All panels show data (or "No data" for new installations)
- [ ] Queries: PromQL queries execute without errors
- [ ] Alerts: 12 alert rules present in Prometheus
- [ ] Time ranges: Dashboard time selectors work
- [ ] Refresh: Auto-refresh working (30s interval)

## Continuous Validation

### Daily Validation

```bash
# Daily check script
daily_check() {
  local errors=0
  
  # Check targets
  DOWN_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.state=="down") | .job' | wc -l)
  if [ $DOWN_TARGETS -gt 0 ]; then
    echo "⚠️  $DOWN_TARGETS down targets"
    ((errors++))
  fi
  
  # Check recent metrics
  RECENT_METRICS=$(curl -s 'http://localhost:9090/api/v1/query?query=ai_gateway_rag_ingestion_runs_total' | jq '.data.result | length')
  if [ $RECENT_METRICS -eq 0 ]; then
    echo "⚠️  No recent ingestion metrics"
    ((errors++))
  fi
  
  if [ $errors -eq 0 ]; then
    echo "✅ Daily validation passed"
  else
    echo "❌ $errors issues found"
  fi
}

daily_check
```

### Weekly Validation

- [ ] All alert thresholds still appropriate?
- [ ] Any dashboard not accessed in 7 days?
- [ ] Prometheus storage growth within expectations?
- [ ] Any metrics with unexpected cardinality?

### Before Production Deployment

1. ✅ Run full sanity check script
2. ✅ Load test with expected traffic
3. ✅ Verify all 5 dashboards render correctly
4. ✅ Test alert firing and routing
5. ✅ Backup Grafana dashboard database
6. ✅ Document any customizations made
7. ✅ Brief team on dashboard usage

## Troubleshooting Validation Issues

### Problem: "No data" in panels

```bash
# Check if metrics exist
curl -s http://localhost:9090/api/v1/query?query={__name__=~"ai_gateway_rag_.*"} | jq '.data.result | length'

# Check data age
curl -s 'http://localhost:9090/api/v1/query?query=time() - ai_gateway_rag_ingestion_runs_total' | jq '.data.result[0].value'
# Convert to seconds old (divide by 1000)

# If > 300 seconds old, metrics not being updated
```

### Problem: Dashboard loads slowly

```bash
# Check query execution time
curl -s 'http://localhost:9090/api/v1/query_range?query=ai_gateway_rag_ingestion_runs_total&start=1h&end=now&step=60s' -w '\nTime: %{time_total}s\n'

# Expected: < 1 second total
```

### Problem: Alert rules not showing

```bash
# Check if alert file loaded
curl -s http://localhost:9090/api/v1/config | jq '.data.ruleFiles'

# Check alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[0].interval'

# Manually reload
curl -s http://localhost:9090/-/reload -X POST
```

## Success Criteria

✅ **Fully validated when:**
1. All 5 dashboards load without errors
2. All metrics return recent data
3. All PromQL queries execute < 1 second
4. Prometheus healthy and scraping targets
5. Grafana accessible and functional
6. All 12 alert rules loaded in Prometheus
7. No high-cardinality metric warnings
8. Load testing shows acceptable performance

📊 **Metrics should show:**
- Ingestion success rate: 95-100%
- Retrieval p95 latency: 50-200ms
- Vector store success rate: 95-100%
- Query rate: Varies by workload (0-1000 QPS)
