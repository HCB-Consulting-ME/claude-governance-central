# Claude Governance Central

Central governance management system for Claude SDLC framework with web-based dashboard.

## Overview

This system provides:
- **Central Hook Management**: Configure verification rules from web interface
- **Evidence Repository**: Store and search all verification evidence
- **Knowledge Base**: Centralized patterns, solutions, and documentation
- **Compliance Dashboard**: Real-time metrics and reporting
- **API**: RESTful API for hook integration

## Architecture

```
┌─────────────────────┐
│   Hook Clients      │ (Claude Code instances on dev machines)
│  ~/.claude/hooks/   │
└──────────┬──────────┘
           │ POST evidence, GET rules
           ↓
┌─────────────────────┐
│   Governance API    │ (Express.js on port 8300)
│   /api/hooks/       │
│   /api/evidence/    │
│   /api/knowledge/   │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│   PostgreSQL DB     │ (Port 5433)
│   - Hook configs    │
│   - Evidence repo   │
│   - Knowledge base  │
└─────────────────────┘

┌─────────────────────┐
│  Web Dashboard      │ (React on port 8301)
│  - Config UI        │
│  - Evidence search  │
│  - Metrics viz      │
└─────────────────────┘
```

## Quick Start

### Deploy to Dev Server

```bash
# Upload to server
scp -r claude-governance-central server:/srv/projects/

# SSH to server
ssh server

# Navigate to project
cd /srv/projects/claude-governance-central

# Start services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### Access Dashboard

- **Dashboard**: http://91.99.237.14:8301
- **API**: http://91.99.237.14:8300
- **Health Check**: http://91.99.237.14:8300/health

## API Endpoints

### Hook Configuration
- `GET /api/hooks/config` - List all hook configurations
- `PUT /api/hooks/config/:id` - Update hook configuration

### Evidence Repository
- `POST /api/evidence` - Submit verification evidence
- `GET /api/evidence/task/:taskId` - Get evidence for specific task
- `GET /api/evidence/search?category=web&from_date=2025-01-01` - Search evidence

### Verification Rules
- `GET /api/rules/:category` - Get rules for task category
- `PUT /api/rules/:id` - Update verification rule

### Knowledge Repository
- `POST /api/knowledge` - Store knowledge entry
- `GET /api/knowledge/search?q=puppeteer&category=verification` - Search knowledge

### Compliance Metrics
- `GET /api/metrics/compliance?project_id=X&from_date=2025-01-01` - Get compliance metrics

## Database Schema

### Key Tables

**hook_configurations**
- Centrally managed hook settings
- Enabled/disabled status
- JSON configuration per hook

**evidence_repository**
- All verification evidence
- Task category, type, data
- Searchable by project, date, category

**verification_rules**
- Category-specific rules
- Priority-based execution
- Enable/disable per rule

**knowledge_repository**
- Patterns, solutions, docs
- Full-text search
- Tagged and categorized

**compliance_metrics**
- Daily compliance tracking
- Per-project, per-category
- Historical trending

## Hook Integration

Update your local hooks to report to central system:

```bash
# In pre-completion-check.sh, add:
curl -X POST http://91.99.237.14:8300/api/evidence \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "'$TASK_ID'",
    "task_category": "'$CATEGORY'",
    "evidence_type": "verification_result",
    "evidence_data": {...},
    "user_id": "'$USER'",
    "project_id": "'$PROJECT'"
  }'
```

## Configuration

### Environment Variables

Create `.env` file:

```env
# Database
DB_PASSWORD=your_secure_password_here

# API
NODE_ENV=production
PORT=8300

# Frontend
VITE_API_URL=http://91.99.237.14:8300
```

### Port Configuration

- **8300**: Backend API
- **8301**: Frontend Dashboard
- **5433**: PostgreSQL (external access)

## Development

### Local Development

```bash
# Start database only
docker compose up governance-db -d

# Run backend locally
cd backend
npm install
npm run dev

# Run frontend locally
cd frontend
npm install
npm run dev
```

### Database Management

```bash
# Connect to database
docker exec -it governance-db psql -U governance_app -d governance

# Run migrations
docker exec -i governance-db psql -U governance_app -d governance < database/migrations/001_add_column.sql

# Backup database
docker exec governance-db pg_dump -U governance_app governance > backup.sql

# Restore database
docker exec -i governance-db psql -U governance_app governance < backup.sql
```

## Monitoring

### Health Checks

```bash
# API health
curl http://91.99.237.14:8300/health

# Database health
docker exec governance-db pg_isready -U governance_app

# Container status
docker compose ps
```

### Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f governance-api

# Last 100 lines
docker compose logs --tail=100 governance-db
```

## Security

### Production Checklist

- [ ] Change default database password
- [ ] Add authentication to API endpoints
- [ ] Enable HTTPS with nginx reverse proxy
- [ ] Configure CORS allowlist
- [ ] Set up database backups
- [ ] Enable audit logging
- [ ] Configure firewall rules

### Nginx Configuration

```nginx
server {
    listen 80;
    server_name governance.yourdomain.com;

    # Frontend
    location / {
        proxy_pass http://localhost:8301;
        proxy_set_header Host $host;
    }

    # API
    location /api/ {
        proxy_pass http://localhost:8300;
        proxy_set_header Host $host;
    }
}
```

## Future Enhancements

- [ ] User authentication and authorization
- [ ] Real-time dashboard updates (WebSockets)
- [ ] Advanced analytics and reporting
- [ ] Integration with Plane for requirements traceability
- [ ] Slack/Teams notifications for compliance violations
- [ ] AI-powered pattern recognition
- [ ] Automated evidence validation
- [ ] Multi-tenancy support

## Support

- **Issues**: GitHub Issues
- **Documentation**: See `/docs` directory
- **Team Chat**: [Your team chat]

## License

MIT License - See main repository
