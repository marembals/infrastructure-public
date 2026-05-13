# Integration Guide: RAG Dashboards with Existing Observability Stack

This guide explains how to integrate the RAG metrics dashboards into your existing observability infrastructure without duplicating services.

## ✅ Your Current Setup

**Location**: `~/docker-compose.yml` and `~/observability/`

**Existing Services**:
- Prometheus v2.51.2 (exposed on port 9091)
- Grafana 11.4.0 (exposed on port 3001)
- Node Exporter, cAdvisor, DCGM Exporter, ROCm Exporter
- Jaeger tracing
- AI Gateway service (on port 8088)

**Network**: `observability` bridge network

## 📋 Integration Steps

### Step 1: Update Prometheus Configuration

**File**: `~/observability/prometheus/prometheus.yml`

Add RAG metrics scrape config. Find the `ai-gateway` job (if exists) or add this section:

```yaml
  - job_name: "ai-gateway"
    metrics_path: /metrics
    static_configs:
      - targets: ["ai-gateway:8088"]
    # Metric relabeling to optimize storage (optional but recommended)
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'ai_gateway_rag_.*|ai_gateway_http_.*|ai_gateway_app_info'
        action: keep
      - source_labels: [__name__]
        regex: '.*_bucket'
        action: drop
```

**Note**: If `ai-gateway:8088` already exists in your config, just verify it's correctly configured. No changes needed if already present.

**Apply Changes**:
```bash
cd ~/
docker-compose restart prometheus
# Wait 30 seconds for restart
sleep 30

# Verify Prometheus is up
curl -s http://localhost:9091/-/healthy
```

### Step 2: Verify Prometheus is Scraping RAG Metrics

```bash
# Check if target is up
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | {job, state, instance}'

# Should show "ai-gateway" with state "up"

# Verify RAG metrics exist
curl -s http://localhost:9091/api/v1/label/__name__/values | jq '.data[] | select(startswith("ai_gateway_rag_"))'

# Expected output (once AI Gateway generates metrics):
# "ai_gateway_rag_ingestion_runs_total"
# "ai_gateway_rag_ingestion_duration_seconds"
# "ai_gateway_rag_chunks_embedded_total"
# "ai_gateway_rag_qdrant_upsert_total"
# "ai_gateway_rag_retrieval_latency_seconds"
```

### Step 3: Import Dashboards into Grafana

**Via Web UI (Easiest)**:

1. Go to http://localhost:3001 (Grafana)
2. Login: admin/admin
3. Create folder "RAG":
   - Left sidebar → Dashboards
   - Click "New Folder" button
   - Name: `RAG`
   - Click "Create"

4. Import each dashboard:
   - Dashboards → New → Import
   - Upload JSON or paste content
   - Files to import:
     - `rag-kb-overview.json`
     - `rag-ingestion-metrics.json`
     - `rag-retrieval-metrics.json`
     - `rag-vector-store.json`
     - `rag-performance-slos.json`
   - Select Prometheus datasource
   - Click "Import"

**Via API (Automated)**:

```bash
#!/bin/bash
# Save as: import_rag_dashboards.sh

GRAFANA_URL="http://localhost:3001"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

# Get auth token
TOKEN=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{"user":"'$GRAFANA_USER'","password":"'$GRAFANA_PASS'"}' \
  $GRAFANA_URL/api/auth/login | jq -r '.token')

# Get Prometheus datasource ID
DS_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  $GRAFANA_URL/api/datasources | jq '.[] | select(.name=="Prometheus") | .id')

# Import dashboards
for dashboard in rag-kb-overview rag-ingestion-metrics rag-retrieval-metrics rag-vector-store rag-performance-slos; do
  echo "Importing $dashboard..."
  
  # Read dashboard JSON and update datasource reference
  cat "dashboards/${dashboard}.json" | jq --arg dsid "$DS_ID" '
    .dashboard.panels[].datasource.uid = "prometheus" |
    .dashboard.panels[].targets[].refId |= . // "A"
  ' > /tmp/dashboard.json
  
  # Import
  curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d @/tmp/dashboard.json \
    $GRAFANA_URL/api/dashboards/db
    
  echo "✓ $dashboard imported"
done
```

### Step 4: Verify Dashboards Work

1. Open Grafana: http://localhost:3001
2. Navigate to Dashboards → RAG folder
3. Open each dashboard:
   - ✅ Dashboard loads without errors
   - ✅ Panels display (may show "No data" if no metrics yet)
   - ✅ Time range selector works
   - ✅ Refresh works (30s)

## ⚠️ Important Notes

### Datasource UID

The dashboards reference a datasource with UID `prometheus`. 

**Check your datasource UID**:
```bash
curl -s http://localhost:3001/api/datasources | jq '.[] | {name, uid, url}'
```

**If UID is different**:
1. Go to Grafana → Configuration → Data Sources
2. Click on Prometheus
3. Note the URL slug (e.g., `/admin/datasources/edit/prometheus`)
4. Use that as the UID

Alternative: Edit dashboard JSON and replace `"uid": "prometheus"` with actual UID.

### Port Mappings

Your infrastructure uses different host-facing ports:
- Prometheus: 9091 (internal: 9090)
- Grafana: 3001 (internal: 3000)
- AI Gateway: 8088 (internal: 8088)

The dashboards use internal network names, so:
- Inside docker: `prometheus:9090`, `ai-gateway:8088` ✅
- Outside docker (for API calls): `localhost:9091`, `localhost:8088` ✅

## 🚀 Quick Integration Script

**One-command integration** (saves as `~/integrate_rag_dashboards.sh`):

```bash
#!/bin/bash
set -e

echo "🔄 Integrating RAG dashboards with existing observability stack..."

# 1. Check if Prometheus is running
echo "1. Checking Prometheus..."
if ! curl -s http://localhost:9091/-/healthy > /dev/null; then
  echo "❌ Prometheus not responding on port 9091"
  exit 1
fi
echo "✓ Prometheus is healthy"

# 2. Update prometheus.yml to include ai-gateway job
echo "2. Updating Prometheus configuration..."
if ! grep -q "ai-gateway" ~/observability/prometheus/prometheus.yml; then
  cat >> ~/observability/prometheus/prometheus.yml << 'EOF'

  - job_name: "ai-gateway"
    metrics_path: /metrics
    static_configs:
      - targets: ["ai-gateway:8088"]
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'ai_gateway_rag_.*|ai_gateway_http_.*|ai_gateway_app_info'
        action: keep
      - source_labels: [__name__]
        regex: '.*_bucket'
        action: drop
EOF
  echo "✓ Added ai-gateway job to prometheus.yml"
else
  echo "✓ ai-gateway job already exists"
fi

# 3. Restart Prometheus
echo "3. Restarting Prometheus..."
cd ~
docker-compose restart prometheus
sleep 10
echo "✓ Prometheus restarted"

# 4. Check if Grafana is running
echo "4. Checking Grafana..."
if ! curl -s http://localhost:3001/api/health | jq -e '.status == "ok"' > /dev/null; then
  echo "❌ Grafana not responding on port 3001"
  exit 1
fi
echo "✓ Grafana is healthy"

# 5. Get Grafana auth token
echo "5. Authenticating with Grafana..."
TOKEN=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","password":"admin"}' \
  http://localhost:3001/api/auth/login | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
  echo "❌ Failed to authenticate with Grafana"
  exit 1
fi
echo "✓ Authenticated"

# 6. Create RAG folder in Grafana
echo "6. Creating RAG folder..."
FOLDER_ID=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"RAG"}' \
  http://localhost:3001/api/folders | jq -r '.id // .message')

if [[ "$FOLDER_ID" == "null" ]] || [[ "$FOLDER_ID" == *"already"* ]]; then
  FOLDER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
    http://localhost:3001/api/folders | jq '.[] | select(.title=="RAG") | .id')
  echo "✓ RAG folder already exists (ID: $FOLDER_ID)"
else
  echo "✓ Created RAG folder (ID: $FOLDER_ID)"
fi

# 7. Import dashboards
echo "7. Importing RAG dashboards..."
cd ~/ai-gateway/dashboards

for dashboard in rag-kb-overview rag-ingestion-metrics rag-retrieval-metrics rag-vector-store rag-performance-slos; do
  echo -n "  • $dashboard..."
  
  curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"dashboard\": $(cat ${dashboard}.json | jq '.dashboard'),
      \"folderUid\": \"rag\",
      \"overwrite\": true
    }" \
    http://localhost:3001/api/dashboards/db > /dev/null
  
  echo " ✓"
done

echo ""
echo "✅ Integration complete!"
echo ""
echo "📊 Next steps:"
echo "1. Open Grafana: http://localhost:3001"
echo "2. Navigate to: Dashboards → RAG"
echo "3. View: RAG KB Overview dashboard"
echo ""
echo "📝 Notes:"
echo "• Dashboards will show 'No data' until AI Gateway generates metrics"
echo "• Metrics appear after running ingestion/retrieval operations"
echo "• To test, run: curl -X POST http://localhost:8088/v1/rag/ingest -d '{...}'"
echo ""
```

**Usage**:
```bash
chmod +x ~/integrate_rag_dashboards.sh
~/integrate_rag_dashboards.sh
```

## 🔍 Verification

After integration, verify everything works:

```bash
# 1. Check Prometheus is scraping
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.job=="ai-gateway")'
# Expected: state="up"

# 2. Check dashboards are imported
curl -s http://localhost:3001/api/dashboards/search?query=RAG | jq '.[] | {title, tags}'
# Expected: 5 RAG dashboards listed

# 3. Check metrics in Prometheus
curl -s 'http://localhost:9091/api/v1/query?query=up{job="ai-gateway"}' | jq '.data.result[0].value'
# Expected: ["timestamp", "1"] (metric exists)
```

## ⛔ DO NOT

- ❌ Don't use the `docker-compose.yml` in `dashboards/` - it duplicates your infrastructure
- ❌ Don't use the `quickstart.sh` in `dashboards/` - it's for isolated testing
- ❌ Don't run the separate Prometheus from that docker-compose
- ❌ Don't import dashboards multiple times (use `overwrite: true`)

## ✅ What to Use Instead

From the `dashboards/` folder:
- ✅ ALL 5 JSON dashboard files (these are infrastructure-agnostic)
- ✅ Documentation files (README.md, TESTING.md, OPERATIONS_RUNBOOK.md, ARCHITECTURE.md)
- ✅ rag-alerts.yml (add to your prometheus alerts if needed)

From your existing infrastructure:
- ✅ `~/docker-compose.yml` (keep as-is)
- ✅ `~/observability/` (keep as-is)
- ✅ Update `~/observability/prometheus/prometheus.yml` to include ai-gateway job

## 🚨 Troubleshooting

### Issue: Dashboards show "No data"

```bash
# 1. Check if metrics exist
curl -s http://localhost:9091/api/v1/query?query=ai_gateway_rag_ingestion_runs_total | jq '.data.result | length'
# Expected: > 0 (after operations)

# 2. Check if AI Gateway is running and exposing metrics
curl -s http://localhost:8088/metrics | grep ai_gateway_rag | head -5

# 3. Check Prometheus scrape job
docker logs -f prometheus | grep ai-gateway
```

### Issue: Datasource not found

```bash
# Find correct datasource UID
curl -s http://localhost:3001/api/datasources | jq '.[] | {name, uid}'

# Update dashboards if UID differs from "prometheus"
sed -i 's/"uid": "prometheus"/"uid": "YOUR_ACTUAL_UID"/g' dashboards/*.json
```

### Issue: Permission denied editing prometheus.yml

```bash
# Ensure file is writable
ls -la ~/observability/prometheus/prometheus.yml
# Should show: -rw-rw-r-- (or similar)

# If not, fix permissions
chmod 644 ~/observability/prometheus/prometheus.yml
```

## 📈 Next Steps

### 1. Generate Some Metrics

```bash
# Test ingestion
curl -X POST http://localhost:8088/v1/rag/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "kb_id": "test_kb",
    "content": "Test document for RAG metrics"
  }'

# Wait 1 minute for metrics to be scraped
sleep 60

# Check dashboards now show data
```

### 2. Set Up Alerts (Optional)

Add to `~/observability/prometheus/prometheus.yml`:

```yaml
rule_files:
  - '~/ai-gateway/dashboards/rag-alerts.yml'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']  # If using Alertmanager
```

### 3. Review Documentation

- [README.md](README.md) - General usage
- [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md) - Alert procedures
- [TESTING.md](TESTING.md) - Validation procedures

## 📝 Configuration Diff

**What changes**:
- ✏️ `~/observability/prometheus/prometheus.yml` - Add 1 job section

**What stays the same**:
- ✅ `~/docker-compose.yml` - No changes
- ✅ All Grafana services - No changes
- ✅ All exporter services - No changes
- ✅ Jaeger service - No changes
- ✅ AI Gateway service - No changes

## 🎯 Integration Complete!

You now have:
- ✅ 5 production RAG dashboards in Grafana
- ✅ RAG metrics scraped by your Prometheus
- ✅ No duplicate services
- ✅ All existing infrastructure preserved
- ✅ Clean integration into existing setup

Visit http://localhost:3001 and navigate to **Dashboards → RAG** to see your dashboards!
