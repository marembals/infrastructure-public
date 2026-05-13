# ⚠️ USAGE GUIDE - Which Files to Use with Your Existing Observability Stack

This file explains which dashboard files and scripts to use if you already have Prometheus + Grafana running.

## 📍 Your Setup

```
~/docker-compose.yml               ← Your main orchestration
~/observability/
├── docker-compose.yml             ← Local dev/testing only
├── prometheus/prometheus.yml       ← UPDATE THIS
├── grafana/                        ← No changes needed
└── rocm_exporter.py               ← Keep as-is
```

**Running Services:**
- Prometheus: port 9091 (internal 9090)
- Grafana: port 3001 (internal 3000)
- AI Gateway: port 8088
- Exporters: node, cadvisor, dcgm, rocm

## ✅ Files To Use (Dashboard Import)

### 1️⃣ All 5 Dashboard JSON Files
```
dashboards/
├── rag-kb-overview.json              ← USE THIS ✅
├── rag-ingestion-metrics.json        ← USE THIS ✅
├── rag-retrieval-metrics.json        ← USE THIS ✅
├── rag-vector-store.json             ← USE THIS ✅
└── rag-performance-slos.json         ← USE THIS ✅
```

These are **infrastructure-agnostic** and work with any Prometheus/Grafana setup.

**Action:** Import these into your existing Grafana at port 3001

### 2️⃣ The Integration Script
```
dashboards/integrate_with_existing.sh   ← USE THIS ✅
```

**Action:** 
```bash
cd ~/ai-gateway/dashboards
chmod +x integrate_with_existing.sh
./integrate_with_existing.sh
```

This script will:
- ✅ Update your Prometheus config
- ✅ Restart Prometheus
- ✅ Create RAG folder in your Grafana
- ✅ Import 5 dashboards automatically

### 3️⃣ Documentation Files
```
dashboards/
├── README.md                         ← General overview ✅
├── INTEGRATION_WITH_EXISTING_OBSERVABILITY.md  ← READ THIS FIRST ✅
├── OPERATIONS_RUNBOOK.md            ← Alert procedures ✅
├── TESTING.md                       ← Validation ✅
├── ARCHITECTURE.md                  ← Design details ✅
└── DELIVERY_SUMMARY.md              ← Complete checklist ✅
```

**Action:** Read INTEGRATION_WITH_EXISTING_OBSERVABILITY.md first

## ❌ Files NOT to Use (Avoid Duplication)

### ❌ Don't Use This docker-compose.yml
```
dashboards/docker-compose.yml        ← DO NOT USE ✗
```

**Why:** This creates a separate Prometheus/Grafana stack that conflicts with your existing one.

**Instead:** Use your existing `~/docker-compose.yml`

### ❌ Don't Use quickstart.sh (Unless Testing)
```
dashboards/quickstart.sh             ← ONLY for isolated testing ✗
```

**Why:** This starts a separate stack. Use `integrate_with_existing.sh` instead.

**When to use:** Only if you want isolated testing duplicate (not recommended for shared workstation)

### ❌ Don't Use provisioning/ Configs (Already Handled)
```
dashboards/provisioning/            ← Managed by integration script ✗
```

**Why:** Integration script handles provisioning automatically.

### ❌ Don't Use rag-alerts.yml (Optional)
```
dashboards/rag-alerts.yml           ← Optional, not required ✗
```

**Why:** This adds alert rules. Only use if you need them.

**When to use:** Read OPERATIONS_RUNBOOK.md to understand alerts first

## 📋 Integration Checklist

For your specific setup, here's what to do:

```bash
□ Step 1: Make integration script executable
  chmod +x ~/ai-gateway/dashboards/integrate_with_existing.sh

□ Step 2: Ensure your stack is running
  cd ~
  docker-compose up -d
  # Wait 10 seconds

□ Step 3: Run integration script
  cd ~/ai-gateway/dashboards
  ./integrate_with_existing.sh

□ Step 4: Verify integration
  curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.job=="ai-gateway")'
  # Output should show: state="up"

□ Step 5: Access Grafana
  http://localhost:3001
  Navigate to: Dashboards → RAG folder

□ Step 6: Verify dashboards load
  • RAG KB Overview loads without errors
  • Panels show "No data" initially (expected)
  • Time range selector works
  • Auto-refresh is on (30s)
```

## 🔍 Verification Commands

After running integration script:

```bash
# Check 1: Prometheus is scraping your AI Gateway
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | {job, state}'

# Check 2: RAG metrics exist
curl -s http://localhost:9091/api/v1/label/__name__/values | jq '.data[] | select(startswith("ai_gateway_rag_"))'

# Check 3: Dashboards are imported
curl -s http://localhost:3001/api/dashboards/search?query=RAG | jq '.[] | {title, tags}'

# Check 4: Grafana can query Prometheus
curl -s 'http://localhost:9091/api/v1/query?query=up{job="ai-gateway"}' | jq '.data.result[0].value'
# Expected: ["timestamp", "1"]
```

## 🚨 Troubleshooting

### Issue: "Integration script fails with permission error"
```bash
# Solution: Ensure file is writable
ls -la ~/observability/prometheus/prometheus.yml
chmod 644 ~/observability/prometheus/prometheus.yml
```

### Issue: "Prometheus won't restart"
```bash
# Solution: Check for syntax errors in prometheus.yml
cd ~
docker-compose logs prometheus | tail -20
```

### Issue: "Dashboards show 'No data'"
```bash
# Solution 1: Generate some metrics
curl -X POST http://localhost:8088/v1/rag/ingest \
  -H "Content-Type: application/json" \
  -d '{"kb_id": "test", "content": "test document"}'

# Solution 2: Wait 1-2 minutes for Prometheus scrape cycle
sleep 120

# Solution 3: Check if Prometheus is actually scraping
curl -s http://localhost:9091/api/v1/query?query=ai_gateway_rag_ingestion_runs_total | jq '.data'
```

### Issue: "Wrong port in documentation"
```bash
# Your Prometheus is on 9091, not 9090 (that's internal)
# Your Grafana is on 3001, not 3000 (that's internal)
# Your AI Gateway is on 8088

# Documentation shows internals, use these externally:
Grafana:     http://localhost:3001
Prometheus:  http://localhost:9091
AI Gateway:  http://localhost:8088
```

## 📊 What Gets Updated

**This gets updated** (safely):
- ✏️ `~/observability/prometheus/prometheus.yml` - adds ai-gateway job section

**This stays unchanged** (important!):
- ✅ `~/docker-compose.yml` - no changes
- ✅ `~/observability/grafana/` - no changes
- ✅ `~/observability/` - no other changes
- ✅ All exporters - no changes
- ✅ Jaeger - no changes

## 📚 Documentation Map for Your Setup

| Need | Document |
|------|----------|
| How to integrate? | **→ INTEGRATION_WITH_EXISTING_OBSERVABILITY.md** |
| Dashboard overview? | → README.md |
| How to respond to alerts? | → OPERATIONS_RUNBOOK.md |
| How to test/validate? | → TESTING.md |
| Why was it designed this way? | → ARCHITECTURE.md |
| Complete checklist? | → DELIVERY_SUMMARY.md |

## ✨ After Integration

You will have:

```
Your existing observability stack:
├── Prometheus (9091) ← Now scrapes ai-gateway:8088 for RAG metrics
├── Grafana (3001)
│   └── RAG folder ← Contains 5 new dashboards
│       ├── RAG KB Overview
│       ├── Ingestion Metrics
│       ├── Retrieval Metrics
│       ├── Vector Store Operations
│       └── Performance SLOs
├── All your existing exporters (unchanged)
└── Jaeger (unchanged)
```

Zero duplication. Clean integration.

## 🎯 Final Verification

```bash
# One-liner to verify everything
echo "Prometheus targets:" && \
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets | map(select(.job=="ai-gateway")) | length' && \
echo "RAG dashboards:" && \
curl -s http://localhost:3001/api/dashboards/search?query=RAG | jq '.[] | .title' && \
echo "✅ All set!"
```

## 📞 Questions?

- **"Will this break my existing setup?"** → No, only adds to prometheus.yml
- **"Can I run the other quickstart.sh?"** → Only if you want a separate isolated stack
- **"What if I don't have a Prometheus datasource?"** → Integration script will fail with helpful message
- **"Can I rerun integration script?"** → Yes, it's safe to run multiple times (idempotent)

---

**Next:** Run the integration script and see [INTEGRATION_WITH_EXISTING_OBSERVABILITY.md](INTEGRATION_WITH_EXISTING_OBSERVABILITY.md) for detailed steps!
