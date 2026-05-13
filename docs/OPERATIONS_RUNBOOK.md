# RAG Dashboards Operations Runbook

Emergency procedures and operational tasks for managing RAG dashboards and metrics.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Alert Response](#alert-response)
3. [Performance Optimization](#performance-optimization)
4. [Maintenance](#maintenance)
5. [Disaster Recovery](#disaster-recovery)

## Daily Operations

### Morning Checks (5 min)

```bash
# 1. Verify all services are running
docker-compose ps
# Status: prometheus (running), grafana (running)

# 2. Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, state}'
# Output: all targets should be "up"

# 3. Check latest metrics exist
curl -s http://localhost:8000/metrics | tail -20
# Output: should show recent rag_* metrics
```

### Dashboard Review Checklist

**Dashboard to Review**: Override by environment

| Dashboard | Purpose | Check | Threshold |
|-----------|---------|-------|-----------|
| **KB Overview** | Health check | Green stat panels | 0 failures in 1h |
| **Ingestion** | Pipeline health | Success rate | >99% | 
| **Retrieval** | Performance | p95 latency | <200ms |
| **Vector Store** | Database health | Upsert success | >99% |
| **SLOs** | Compliance | All green | SLI met |

### Metric Verification Commands

**Check ingestion health**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=rate(ai_gateway_rag_ingestion_runs_total[5m])' | jq
# Expected: positive numbers, no spikes
```

**Check retrieval performance**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,ai_gateway_rag_retrieval_latency_seconds_bucket)' | jq
# Expected: < 0.2 (200ms)
```

**Check vector store health**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=ai_gateway_rag_qdrant_upsert_total' | jq '.data.result | map(.value[1] | tonumber)'
# Expected: consistent upward trend
```

## Alert Response

### ✋ CRITICAL: IngestionSuccessRateCritical

**Trigger**: Success rate drops below 95% for 2 minutes

**Immediate Actions**
1. Open RAG Ingestion Metrics dashboard
2. Check "Run success/failure rate" panel
3. Identify failing KBs in the timeseries

**Investigation Steps**
```bash
# Get failing KB
curl -s 'http://localhost:9090/api/v1/query?query=rate(ai_gateway_rag_ingestion_runs_total{status="failed"}[5m])' | jq

# Check error logs
docker logs ai_gateway | grep -i "ingestion.*error" | tail -20

# Check KB size
docker logs ai_gateway | grep -i "chunks.*kb" | tail -10
```

**Resolution Options**
- Increase ingestion timeout: `INGESTION_TIMEOUT=300` (seconds)
- Reduce batch size: `INGESTION_BATCH_SIZE=100`
- Check vector store connectivity (Qdrant health)
- Restart AI Gateway: `docker-compose restart ai-gateway`

**Escalation**
- Slack: Post to #alerts channel with dashboard link
- PagerDuty: Create incident (if not auto-created)
- Timeline: Should close within 15 minutes

---

### ⚠️ WARNING: IngestionSuccessRateLow

**Trigger**: Success rate drops below 99% for 5 minutes

**Immediate Actions**
1. Monitor next 5 minutes for trend
2. Check if ongoing operations are normal

**Investigation**
```bash
# Check ingestion queue depth
curl http://localhost:8000/health | jq '.ingestion_queue_depth'

# Check resource limits
docker stats --no-stream | grep -E "ai_gateway|prometheus|grafana"
```

**Resolution**
- Monitor for 10 minutes before escalating
- If continues, follow CRITICAL procedure above
- Check for high load periods

---

### ✋ CRITICAL: RetrievalLatencyCritical

**Trigger**: p99 latency exceeds 500ms for 5 minutes

**Immediate Actions**
1. Check "Latency percentiles" in RAG Retrieval Metrics
2. Identify latency spike timeline
3. Check if query volume increased simultaneously

```bash
# Check query rate
curl -s 'http://localhost:9090/api/v1/query?query=rate(ai_gateway_rag_retrieval_latency_seconds_count[5m])' | jq

# Check p99 latency
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,rate(ai_gateway_rag_retrieval_latency_seconds_bucket[5m]))' | jq
```

**Resolution Options**
- Scale vector store: Add more Qdrant replicas
- Add query cache: Enable embedding cache
- Optimize queries: Review slow query logs
- Reduce KB size: Split large KBs

**Escalation**
- Page on-call engineer if not self-recovering

---

### ⚠️ WARNING: RetrievalLatencyHighP99

**Trigger**: p99 latency exceeds 200ms for 10 minutes

**Investigation**
```bash
# Check resource saturation
docker stats --no-stream

# Check network latency to Qdrant
docker exec prometheus ping qdrant
```

**Action Plan**
- Increase Qdrant resources if CPU/Memory high
- Consider query batching to reduce round trips
- Review slow query examples in logs

---

### ✋ CRITICAL: QdrantUpsertFailureRateCritical

**Trigger**: Upsert failure rate exceeds 5% for 2 minutes

**Immediate Actions**
1. Check Vector Store Operations dashboard
2. Note which KBs are failing
3. Check Qdrant health

```bash
# Check Qdrant status
curl -s http://qdrant:6333/health | jq

# Check connection errors
docker logs ai_gateway | grep -i "qdrant.*error" | tail -20
```

**Resolution**
- Check Qdrant disk space: `docker exec qdrant df -h`
- Restart Qdrant if needed: `docker-compose restart qdrant`
- Check network connectivity: `docker exec prometheus curl qdrant:6333/health`

---

### ⚠️ WARNING: QdrantUpsertFailureRateHigh

**Trigger**: Upsert failure rate exceeds 1% for 5 minutes

**Actions**
- Monitor for next 10 minutes
- Check if temporary network issue
- Review Qdrant logs for errors
- Consider reducing batch size if retries not helping

---

### ℹ️ NoIngestionActivity

**Trigger**: No ingestion for 30 minutes

**Assessment**
- Check if this is expected (test environment?)
- Verify AI Gateway is still running
- Check for stuck ingestion jobs

```bash
curl http://localhost:8000/health | jq '.ingestion_queue'
```

**Action**: Informational only, unless this is unexpected

---

## Performance Optimization

### Dashboard Responsiveness

**If dashboards feel slow:**

1. **Reduce time range**
   - Default: 6h
   - Change to: 1h or 2h for fast loading

2. **Increase refresh interval**
   - Default: 30s auto-refresh
   - For background dashboard: 1m or 5m

3. **Optimize queries in Prometheus**
   ```bash
   # Check slow queries
   curl http://localhost:9090/api/v1/query_log
   ```

### Prometheus Performance

**Monitor Prometheus health**
```bash
curl http://localhost:9090/api/v1/targets/metadata?match_target={} | jq '.data | length'

# Check storage usage
du -sh /var/lib/prometheus/metrics
```

**If Prometheus slow or high memory:**

1. **Reduce metric retention**
   ```yaml
   # prometheus.yml
   --storage.tsdb.retention.time=15d  # Default
   ```

2. **Increase scrape interval**
   ```yaml
   global:
     scrape_interval: 30s  # From 15s
   ```

3. **Drop high-cardinality metrics**
   ```yaml
   metric_relabel_configs:
     - source_labels: [__name__]
       regex: '.*_bucket'
       action: drop
   ```

### Grafana Performance

**Heavy resource usage**
```bash
# Check plugin load time
docker logs grafana | grep "plugin"

# Check dashboard load time
# Browser DevTools → Network tab → JSON requests
```

**Optimization**
- Disable unused plugins
- Archive old dashboards
- Set reasonable limits on legend size

## Maintenance

### Weekly Tasks

**Monday mornings:**

1. **Review alerts from past week**
   ```bash
   # Query Alertmanager
   for alert in $(curl -s http://localhost:9093/api/v1/alerts | jq -r '.data[].labels.alertname' | sort | uniq); do
     echo "- $alert"
   done
   ```

2. **Check dashboard freshness**
   - Are queries still returning data?
   - Are thresholds still appropriate?

3. **Review metric cardinality**
   ```bash
   curl http://localhost:9090/api/v1/label/__name__/values | jq 'group_by(.split("_")[3]) | map({label: .[0].split("_")[3], count: length})'
   ```

### Monthly Tasks

**First day of month:**

1. **Archive old alert firing**
   ```bash
   # Keep last 30 days in AlertManager
   ```

2. **Update alert thresholds based on trends**
   - Review p95/p99 latency trends
   - Update thresholds if new baseline established

3. **Cleanup old dashboards**
   ```bash
   # Grafana → Dashboards → Manage
   # Delete dashboards not accessed in 30 days
   ```

### Quarterly Tasks

1. **Audit dashboard usage**
   - Which dashboards are accessed most?
   - Remove unused dashboards

2. **Update alert runbooks**
   - Are procedures still accurate?
   - Add new KBs to monitoring?

3. **Plan capacity upgrades**
   - Prometheus disk growth: `du -sh /prometheus_data`
   - Grafana database: `du -sh /grafana_data`

## Disaster Recovery

### Lost Prometheus Data

**Symptom**: "No data points" across all dashboards

**Recovery:**
```bash
# Stop Prometheus
docker-compose stop prometheus

# Backup current data (if corrupted but present)
mv prometheus_data prometheus_data.backup

# Start fresh
docker-compose up -d prometheus

# Wait 5 minutes for new metrics to arrive
sleep 300

# Verify
curl http://localhost:9090/api/v1/query?query=up
```

**Note**: 5 minutes of historical data will be lost. Alerts from AlertManager should exist in logs.

### Lost Grafana Dashboards

**Symptom**: Dashboards show "Cannot find dashboard" after restart

**Recovery:**
```bash
# Restore from provisioning files
docker-compose restart grafana

# If provisioning files corrupted:
rm grafana_data/*
docker-compose restart grafana

# Re-import dashboards
cd dashboards/
./quickstart.sh
```

### Prometheus Out of Disk Space

**Symptom**: "Failed to write metadata" in prometheus logs

**Emergency Response:**
```bash
# 1. Check disk
df -h /prometheus_data

# 2. Reduce retention immediately
docker-compose stop prometheus

# 3. Reduce retention time
# Edit prometheus.yml:
# --storage.tsdb.retention.time=7d

docker-compose up -d prometheus

# 4. Check if recovered
docker logs prometheus | tail -20
```

### Qdrant Connection Lost

**Symptom**: BAD_GATEWAY errors in AI Gateway, upsert failures spike

**Recovery:**
```bash
# 1. Check Qdrant container
docker ps | grep qdrant

# 2. If not running, start
docker-compose up -d qdrant

# 3. Check health
curl http://localhost:6333/health

# 4. If unhealthy, restart
docker-compose restart qdrant

# 5. Monitor recovery
watch -n 1 'curl http://localhost:8000/metrics | grep qdrant'
```

### Full Stack Failure

**Recovery procedure:**
```bash
# 1. Stop everything
docker-compose down

# 2. Backup data volumes
tar -czf backup-$(date +%s).tar.gz prometheus_data grafana_data

# 3. Restart fresh
docker-compose up -d

# 4. Wait for health checks
sleep 30

# 5. Verify
docker-compose ps
curl http://localhost:9090/-/healthy
curl http://localhost:3000/api/health
```

## Runbook Review Procedure

Every incident should trigger:

1. **Document what happened**
   - Timestamp, alert name, affected component
   - Manual steps taken to resolve

2. **Update this runbook**
   - Add troubleshooting step if missing
   - Improve escalation path if unclear

3. **Update alerts if threshold wrong**
   - Reduce flakiness: Increase duration
   - Increase sensitivity: Lower threshold

4. **Knowledge base entry**
   - Share with team
   - Link to this runbook

## Contact Information

**Escalation Path**
1. On-call engineer (Slack)
2. Team lead (Page)
3. Incident commander (Declare SEV1)

**Important Links**
- Dashboards: http://localhost:3000
- Prometheus: http://localhost:9090
- Alert Manager: http://localhost:9093 (if configured)
- Chatroom: #oncall-alerts

## Common Commands Reference

```bash
# Health checks
docker-compose ps
curl http://localhost:9090/-/healthy
curl http://localhost:3000/api/health

# Restart services
docker-compose restart prometheus
docker-compose restart grafana
docker-compose restart qdrant

# View logs
docker logs prometheus | tail -50
docker logs grafana -f
docker logs ai_gateway | grep rag

# Query Prometheus directly
curl 'http://localhost:9090/api/v1/query?query=up'
curl 'http://localhost:9090/api/v1/query_range?query=rate(ai_gateway_rag_ingestion_runs_total[5m])&start=2024-01-01T00:00:00Z&end=2024-01-01T01:00:00Z&step=60s'

# Check disk usage
df -h /
du -sh prometheus_data/
du -sh grafana_data/

# Monitor in real-time
watch -n 5 'curl http://localhost:8000/metrics | grep rag_ | head -10'
```
