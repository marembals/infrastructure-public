# 🚀 QUICK START - Your Setup (With Existing Stack)

**TL;DR:** 3 commands to integrate RAG dashboards into your existing Prometheus + Grafana

## One-Minute Setup

```bash
# 1. Make the script executable
chmod +x ~/ai-gateway/dashboards/integrate_with_existing.sh

# 2. Run it
~/ai-gateway/dashboards/integrate_with_existing.sh

# 3. Open Grafana
open http://localhost:3001  # macOS
# OR xdg-open http://localhost:3001  # Linux  
# OR just go to http://localhost:3001 in your browser
```

## What Happens

```
✅ Prometheus configuration updated (adds ai-gateway job)
✅ Prometheus container restarted (30 second downtime)
✅ RAG folder created in Grafana
✅ 5 dashboards imported
✅ Everything else - untouched
```

## Verify It Works

1. Open http://localhost:3001 (Grafana)
2. Go to: **Dashboards → RAG** folder
3. Click: **RAG KB Overview**
4. You should see panels loading

**Note:** Panels show "No data" until you generate some metrics

## Generate Test Metrics

```bash
# Make a test ingestion request
curl -X POST http://localhost:8088/v1/rag/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "kb_id": "test_kb",
    "content": "This is a test document for RAG metrics"
  }'

# Wait 1-2 minutes, then refresh the dashboard
# (Prometheus needs time to scrape and display)
```

## File Reference

| What | File | Action |
|------|------|--------|
| **Integration** | `integrate_with_existing.sh` | ✅ RUN THIS |
| **Instructions** | `INTEGRATION_WITH_EXISTING_OBSERVABILITY.md` | 📖 READ FIRST |
| **Validation** | `ALIGNMENT_VALIDATION.md` | 🔐 REVIEWED & SAFE |
| **Decision Help** | `WHICH_FILES_TO_USE.md` | 📊 IF CONFUSED |
| **Dashboards** | `rag-*.json` (5 files) | 📈 AUTO-IMPORTED |
| **Operations** | `OPERATIONS_RUNBOOK.md` | 📋 FOR LATER |

## Ports

```
Grafana:    http://localhost:3001  (was 3000, mapped to 3001)
Prometheus: http://localhost:9091  (was 9090, mapped to 9091)
AI Gateway: http://localhost:8088  (unchanged)
```

## Environment Check

```bash
# Before running integration, verify all services are running:

docker-compose ps
# Should show: prometheus, grafana, ai-gateway, exporters - all "Up"

# If anything is down:
cd ~
docker-compose up -d
```

## After Integration

```
~/observability/prometheus/prometheus.yml
└── Added section for ai-gateway job (safe, additive only)

Grafana (port 3001)
└── RAG folder (new)
    ├── RAG KB Overview
    ├── Ingestion Metrics
    ├── Retrieval Metrics
    ├── Vector Store
    └── Performance SLOs

Prometheus (port 9091)
└── Now scrapes ai-gateway:8088/metrics (new)
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Script fails: "permission denied" | `chmod +x ~/ai-gateway/dashboards/integrate_with_existing.sh` |
| "Prometheus not responding" | `cd ~ && docker-compose up -d && sleep 10` |
| "Grafana not responding" | Check: `curl http://localhost:3001/api/health` |
| Dashboards show "No data" | Generate metrics (see above), wait 1-2 min, refresh |
| Wrong port in error | Remember: 3001 is Grafana, 9091 is Prometheus (not 3000/9090) |

## Success Indicators

After 2-3 minutes:

```bash
✅ Grafana loads at http://localhost:3001
✅ Dashboards appear in RAG folder  
✅ Prometheus shows ai-gateway target as "UP"
✅ No errors in docker-compose logs
```

## Files NOT to Use

```
❌ docker-compose.yml (in dashboards/) - creates duplicate stack
❌ quickstart.sh - for isolated testing only
❌ prometheus.yml (in dashboards/) - use integration script instead
```

## Questions?

| Need | File |
|------|------|
| How to integrate? | → `INTEGRATION_WITH_EXISTING_OBSERVABILITY.md` |
| Will this break things? | → `ALIGNMENT_VALIDATION.md` |
| Which files should I use? | → `WHICH_FILES_TO_USE.md` |
| Dashboard explanations? | → `README.md` |
| Alert procedures? | → `OPERATIONS_RUNBOOK.md` |

## Next Steps

```bash
# Step-by-step:

# 1. Read the integration guide (2 min)
cat ~/ai-gateway/dashboards/INTEGRATION_WITH_EXISTING_OBSERVABILITY.md | head -100

# 2. Run integration (1 min)
chmod +x ~/ai-gateway/dashboards/integrate_with_existing.sh
~/ai-gateway/dashboards/integrate_with_existing.sh

# 3. Check Grafana (1 min)
open http://localhost:3001
# Navigate to Dashboards → RAG

# 4. Generate test metrics (1 min)
curl -X POST http://localhost:8088/v1/rag/ingest \
  -H "Content-Type: application/json" \
  -d '{"kb_id": "test", "content": "test"}'

# 5. View dashboards (1 min)
# Refresh dashboard in Grafana

# Total time: ~6 minutes
```

---

**Ready?** → Run: `chmod +x ~/ai-gateway/dashboards/integrate_with_existing.sh && ~/ai-gateway/dashboards/integrate_with_existing.sh`

Then visit: → http://localhost:3001
