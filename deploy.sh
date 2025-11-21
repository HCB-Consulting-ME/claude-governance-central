#!/bin/bash
# Deploy Claude Governance Central to dev server

set -e

SERVER="server"
PROJECT_DIR="/srv/projects/claude-governance-central"

echo "════════════════════════════════════════════════════════"
echo "  Deploying Claude Governance Central"
echo "  Target: $SERVER:$PROJECT_DIR"
echo "════════════════════════════════════════════════════════"
echo ""

# Step 1: Create project directory on server
echo "📁 Creating project directory on server..."
ssh $SERVER "mkdir -p $PROJECT_DIR"

# Step 2: Upload files
echo "📤 Uploading files to server..."
rsync -avz --exclude 'node_modules' --exclude '.git' \
  ./ $SERVER:$PROJECT_DIR/

# Step 3: Deploy with Docker Compose
echo "🐳 Starting Docker containers..."
ssh $SERVER "cd $PROJECT_DIR && docker compose up -d"

# Step 4: Wait for services to be healthy
echo "⏳ Waiting for services to become healthy..."
sleep 10

# Step 5: Check service status
echo "📊 Checking service status..."
ssh $SERVER "cd $PROJECT_DIR && docker compose ps"

# Step 6: Verify API health
echo "🏥 Verifying API health..."
sleep 5
API_HEALTH=$(ssh $SERVER "curl -s http://localhost:8300/health | jq -r '.status'")

if [ "$API_HEALTH" = "healthy" ]; then
    echo "✅ API is healthy"
else
    echo "❌ API health check failed"
    ssh $SERVER "cd $PROJECT_DIR && docker compose logs governance-api"
    exit 1
fi

# Step 7: Show access information
echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅ Deployment Complete!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Access URLs:"
echo "  🌐 Dashboard: http://91.99.237.14:8301"
echo "  📡 API: http://91.99.237.14:8300"
echo "  🏥 Health Check: http://91.99.237.14:8300/health"
echo ""
echo "Useful commands:"
echo "  View logs: ssh $SERVER 'cd $PROJECT_DIR && docker compose logs -f'"
echo "  Restart: ssh $SERVER 'cd $PROJECT_DIR && docker compose restart'"
echo "  Stop: ssh $SERVER 'cd $PROJECT_DIR && docker compose down'"
echo ""
