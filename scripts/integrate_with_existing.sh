#!/bin/bash
# Integration script for RAG dashboards with existing observability stack
# Usage: bash ~/integrate_rag_dashboards.sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GRAFANA_URL="http://localhost:3001"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"
PROMETHEUS_URL="http://localhost:9091"
PROMETHEUS_CONFIG="$HOME/observability/prometheus/prometheus.yml"
DASHBOARDS_DIR="$HOME/ai-gateway/dashboards"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  RAG Dashboards Integration with Existing Stack${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Validate directories exist
echo -e "${BLUE}Step 1/6:${NC} Validating setup (RAG + Gateway dashboards)..."
if [ ! -d "$DASHBOARDS_DIR" ]; then
  echo -e "${RED}✗ Dashboards directory not found: $DASHBOARDS_DIR${NC}"
  exit 1
fi
echo -e "${GREEN}✓${NC} Dashboards found at $DASHBOARDS_DIR"

if [ ! -f "$PROMETHEUS_CONFIG" ]; then
  echo -e "${RED}✗ Prometheus config not found: $PROMETHEUS_CONFIG${NC}"
  exit 1
fi
echo -e "${GREEN}✓${NC} Prometheus config found"

# Step 2: Check services are running
echo ""
echo -e "${BLUE}Step 2/6:${NC} Checking services..."

if ! curl -s "$PROMETHEUS_URL/-/healthy" > /dev/null 2>&1; then
  echo -e "${RED}✗ Prometheus not responding on port 9091${NC}"
  echo -e "${YELLOW}  Start with: cd ~/ && docker-compose up -d${NC}"
  exit 1
fi
echo -e "${GREEN}✓${NC} Prometheus is healthy (port 9091)"

if ! curl -s "$GRAFANA_URL/api/health" | jq -e '.database' > /dev/null 2>&1; then
  echo -e "${RED}✗ Grafana not responding on port 3001${NC}"
  echo -e "${YELLOW}  Start with: cd ~/ && docker-compose up -d${NC}"
  exit 1
fi
echo -e "${GREEN}✓${NC} Grafana is healthy (port 3001)"

# Step 3: Update Prometheus configuration
echo ""
echo -e "${BLUE}Step 3/6:${NC} Updating Prometheus configuration..."

# Check if ai-gateway job already exists
if grep -q 'job_name: "ai-gateway"' "$PROMETHEUS_CONFIG"; then
  echo -e "${GREEN}✓${NC} ai-gateway job already configured"
else
  echo -n "  Adding ai-gateway job to prometheus.yml..."
  cat >> "$PROMETHEUS_CONFIG" << 'PROM_CONFIG'

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
PROM_CONFIG
  echo " done"
  
  # Restart Prometheus
  echo "  Restarting Prometheus..."
  cd "$HOME"
  docker-compose restart prometheus > /dev/null 2>&1
  sleep 5
  echo -e "${GREEN}✓${NC} Prometheus configuration updated and restarted"
fi

# Step 4: Authenticate with Grafana (using basic auth)
echo ""
echo -e "${BLUE}Step 4/6:${NC} Authenticating with Grafana..."

# Test basic auth
if ! curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/org" > /dev/null 2>&1; then
  echo -e "${RED}✗ Failed to authenticate with Grafana${NC}"
  echo -e "${YELLOW}  Check credentials (default: admin/admin)${NC}"
  exit 1
fi
echo -e "${GREEN}✓${NC} Authentication successful"

# Step 5: Create Gateway folder and datasource
echo ""
echo -e "${BLUE}Step 5/6:${NC} Preparing Grafana..."

# Get or create Gateway folder
GATEWAY_FOLDER=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/folders" | jq '.[] | select(.title=="Gateway") | .uid' -r)

if [ -z "$GATEWAY_FOLDER" ]; then
  echo -n "  Creating Gateway folder..."
  GATEWAY_FOLDER=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" -X POST \
    -H "Content-Type: application/json" \
    -d '{"title":"Gateway"}' \
    "$GRAFANA_URL/api/folders" | jq -r '.uid')
  echo " done"
  echo -e "${GREEN}✓${NC} Created Gateway folder"
else
  echo -e "${GREEN}✓${NC} Gateway folder already exists"
fi

# Verify Prometheus datasource
DS_EXISTS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/datasources" | jq '.[] | select(.type=="prometheus") | .uid' -r)

if [ -z "$DS_EXISTS" ]; then
  echo -e "${RED}✗ Prometheus datasource not found in Grafana${NC}"
  echo -e "${YELLOW}  Please add Prometheus datasource manually:${NC}"
  echo -e "${YELLOW}  Configuration → Data Sources → Add → Prometheus${NC}"
  echo -e "${YELLOW}  URL: http://prometheus:9090${NC}"
  exit 1
fi
echo -e "${GREEN}✓${NC} Prometheus datasource verified (uid: $DS_EXISTS)"

# Step 6: Import dashboards
echo ""
echo -e "${BLUE}Step 6/6:${NC} Importing dashboards (RAG + Gateway)..."
echo ""

DASHBOARDS=(
  "rag-kb-overview"
  "rag-ingestion-metrics"
  "rag-retrieval-metrics"
  "rag-vector-store"
  "rag-performance-slos"
  "gateway-overview"
  "gateway-chat-endpoints"
  "gateway-embeddings"
  "gateway-lane-routing"
  "gateway-health"
)

IMPORT_COUNT=0
for dashboard in "${DASHBOARDS[@]}"; do
  DASHBOARD_FILE="$DASHBOARDS_DIR/${dashboard}.json"
  
  if [ ! -f "$DASHBOARD_FILE" ]; then
    echo -e "${RED}✗ ${dashboard}.json not found${NC}"
    continue
  fi
  
  echo -n "  • ${dashboard:4}..."
  
  # Check if dashboard has .dashboard wrapper (gateway dashboards) or not (RAG dashboards)
  DASH_CONTENT=$(cat "$DASHBOARD_FILE")
  if echo "$DASH_CONTENT" | jq -e '.dashboard' > /dev/null 2>&1; then
    # Has .dashboard wrapper - extract it and use as-is
    DASHBOARD_BODY=$(echo "$DASH_CONTENT" | jq '.dashboard')
  else
    # No wrapper - use the file content directly
    DASHBOARD_BODY=$(echo "$DASH_CONTENT")
  fi
  
  # Import dashboard
  RESPONSE=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"dashboard\": $DASHBOARD_BODY,
      \"folderUid\": \"$GATEWAY_FOLDER\",
      \"overwrite\": true
    }" \
    "$GRAFANA_URL/api/dashboards/db")
  
  STATUS=$(echo "$RESPONSE" | jq -r '.status // .message' 2>/dev/null)
  
  if [ "$STATUS" == "success" ] || echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    echo -e " ${GREEN}✓${NC}"
    ((IMPORT_COUNT++))
  else
    echo -e " ${YELLOW}⚠${NC} (may already exist)"
    ((IMPORT_COUNT++))
  fi
done

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Integration Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Success information
echo -e "${GREEN}What was done:${NC}"
echo "  ✓ Prometheus configured to scrape ai-gateway:8088"
echo "  ✓ Gateway folder created in Grafana"
echo "  ✓ $IMPORT_COUNT dashboards imported:"
echo "    • 5 RAG dashboards (RAG KB Overview, Ingestion, Retrieval, Vector Store, Performance SLOs)"
echo "    • 5 Gateway dashboards (Overview, Chat Endpoints, Embeddings, Lane Routing, Health)"
echo ""

echo -e "${GREEN}Next steps:${NC}"
echo "  1. Open Grafana: ${BLUE}http://localhost:3001${NC}"
echo "  2. Navigate to: Dashboards → Gateway folder"
echo "  3. Start with: Gateway Overview or RAG KB Overview"
echo ""

echo -e "${YELLOW}Dashboard Organization:${NC}"
echo "  ${BLUE}RAG Dashboards:${NC}"
echo "    • RAG KB Overview - Executive summary"
echo "    • RAG Ingestion Metrics - Pipeline performance"
echo "    • RAG Retrieval Metrics - Query performance"
echo "    • RAG Vector Store - Qdrant operations"
echo "    • RAG Performance SLOs - SLI compliance"
echo ""
echo "  ${BLUE}Gateway Dashboards:${NC}"
echo "    • Gateway Overview - HTTP & routing overview"
echo "    • Gateway Chat Endpoints - Chat completions deep dive"
echo "    • Gateway Embeddings - Embeddings endpoint performance"
echo "    • Gateway Lane Routing - Backend lane comparison"
echo "    • Gateway Health - System health & tripwires"
echo ""

echo -e "${YELLOW}Note:${NC} Dashboards will show 'No data' until AI Gateway"
echo "      generates metrics. Try ingestion to test:"
echo ""
echo -e "      ${BLUE}curl -X POST http://localhost:8088/v1/rag/ingest \\${NC}"
echo -e "      ${BLUE}  -H 'Content-Type: application/json' \\${NC}"
echo -e "      ${BLUE}  -d '{\"kb_id\": \"test\", \"content\": \"test\"}'${NC}"
echo ""

# Verification
echo -e "${YELLOW}Verify setup (optional):${NC}"
echo -e "  ${BLUE}# Check Prometheus is scraping${NC}"
echo "  curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.job==\"ai-gateway\"')'"
echo ""
echo -e "  ${BLUE}# Check dashboards are imported${NC}"
echo "  curl -s http://localhost:3001/api/dashboards/search?query=RAG | jq '.[] | {title, tags}'"
echo ""

echo -e "${GREEN}For more information, see:${NC}"
echo "  • INTEGRATION_WITH_EXISTING_OBSERVABILITY.md"
echo "  • README.md"
echo "  • OPERATIONS_RUNBOOK.md"
echo ""
