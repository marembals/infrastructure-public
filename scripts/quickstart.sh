#!/bin/bash

# Grafana Dashboards Quick Start
# Automatically sets up Grafana and Prometheus with RAG dashboards

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DASHBOARDS_DIR="$SCRIPT_DIR"

echo "================== RAG Dashboards Quick Start =================="
echo ""

# Check if docker and docker-compose are installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "✅ Docker and Docker Compose found"
echo ""

# Copy dashboard files to provisioning directory
echo "📋 Setting up dashboard provisioning..."
mkdir -p "$DASHBOARDS_DIR/provisioning/dashboards"

cp "$DASHBOARDS_DIR/rag-kb-overview.json" "$DASHBOARDS_DIR/provisioning/dashboards/"
cp "$DASHBOARDS_DIR/rag-ingestion-metrics.json" "$DASHBOARDS_DIR/provisioning/dashboards/"
cp "$DASHBOARDS_DIR/rag-retrieval-metrics.json" "$DASHBOARDS_DIR/provisioning/dashboards/"
cp "$DASHBOARDS_DIR/rag-vector-store.json" "$DASHBOARDS_DIR/provisioning/dashboards/"
cp "$DASHBOARDS_DIR/rag-performance-slos.json" "$DASHBOARDS_DIR/provisioning/dashboards/"

echo "✅ Dashboards copied to provisioning directory"
echo ""

# Start services
echo "🚀 Starting Prometheus and Grafana services..."
docker-compose -f "$DASHBOARDS_DIR/docker-compose.yml" up -d

# Wait for Grafana to be ready
echo "⏳ Waiting for Grafana to start (max 60 seconds)..."
for i in {1..60}; do
    if curl -s http://localhost:3000/api/health > /dev/null; then
        echo "✅ Grafana is ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "❌ Grafana failed to start within 60 seconds"
        echo "Check logs with: docker-compose -f $DASHBOARDS_DIR/docker-compose.yml logs grafana"
        exit 1
    fi
    sleep 1
done

echo ""
echo "================== Setup Complete =================="
echo ""
echo "📊 Access Dashboards:"
echo "  • Grafana:     http://localhost:3000"
echo "  • Prometheus:  http://localhost:9090"
echo ""
echo "📝 Grafana Credentials:"
echo "  • Username: admin"
echo "  • Password: admin"
echo ""
echo "⚙️  Next Steps:"
echo "  1. Update prometheus.yml with your AI Gateway host:port"
echo "     (Default: localhost:8000)"
echo "  2. Restart Prometheus: docker-compose restart prometheus"
echo "  3. Navigate to the 'RAG' folder in Grafana to view dashboards"
echo ""
echo "📚 Available Dashboards:"
echo "  • RAG KB Overview          - Complete overview of all metrics"
echo "  • RAG Ingestion Metrics    - Document ingestion pipeline"
echo "  • RAG Retrieval Metrics    - Vector search performance"
echo "  • Vector Store Operations  - Qdrant operations tracking"
echo "  • RAG Performance SLOs     - SLO/SLI compliance tracking"
echo ""
echo "🛑 Stop services: docker-compose -f $DASHBOARDS_DIR/docker-compose.yml down"
echo "📋 View logs:     docker-compose -f $DASHBOARDS_DIR/docker-compose.yml logs -f"
echo ""
