# Claude Governance Central - Installation & Integration Guide

Complete guide for installing and integrating the central governance system with your Claude Code instances.

## Prerequisites

- Access to dev server: `91.99.237.14`
- Claude Code installed on your local machine
- SSH access configured (`server` alias)

## Part 1: Access the System

The system is **already deployed** on your dev server. You can access it immediately:

### Web Dashboard
**URL**: http://91.99.237.14:8301

Open in your browser to see:
- Compliance dashboard
- Evidence repository
- Knowledge base
- Hook configuration management

### API Endpoints
**Base URL**: http://91.99.237.14:8300

**Available endpoints**:
```bash
# Health check
curl http://91.99.237.14:8300/health

# Get hook configurations
curl http://91.99.237.14:8300/api/hooks/config

# Search evidence
curl http://91.99.237.14:8300/api/evidence/search?category=web

# Search knowledge base
curl http://91.99.237.14:8300/api/knowledge/search?q=puppeteer

# Get compliance metrics
curl http://91.99.237.14:8300/api/metrics/compliance
```

### Database Access (Advanced)
```bash
# Connect to PostgreSQL
ssh server
docker exec -it governance-db psql -U governance_app -d governance

# Run queries
governance=# SELECT * FROM hook_configurations;
governance=# SELECT count(*) FROM evidence_repository;
governance=# \q
```

---

## Part 2: Integrate with Claude Code

The local hooks need to be updated to report to the central system. **The deploy script does NOT do this automatically** - you must update your local hooks manually.

### Step 1: Locate Your Local Hooks

Your hooks are at:
```
~/.claude/hooks/pre-completion-check.sh
~/.claude/hooks/user-prompt-submit-hook
```

### Step 2: Add Evidence Reporting Function

Edit `~/.claude/hooks/pre-completion-check.sh` and add this function at the top (after the shebang):

```bash
#!/bin/bash
# Context-Aware Pre-Completion Verification Hook
# ...existing comments...

# ============================================================================
# CENTRAL SYSTEM INTEGRATION
# ============================================================================

CENTRAL_API="http://91.99.237.14:8300"
PROJECT_ID="${PWD##*/}"  # Use directory name as project ID
USER_ID="${USER}@$(hostname)"

# Report evidence to central system
report_evidence() {
    local task_category="$1"
    local evidence_type="$2"
    local result="$3"  # "passed" or "blocked"
    local exit_code="$4"
    local error_message="$5"

    # Build evidence data
    local evidence_data=$(cat <<EOF
{
  "result": "$result",
  "exit_code": $exit_code,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "error_message": "$error_message"
}
EOF
)

    # Submit to central system (async, don't block hook execution)
    curl -X POST "$CENTRAL_API/api/evidence" \
      -H "Content-Type: application/json" \
      -d "{
        \"task_category\": \"$task_category\",
        \"evidence_type\": \"$evidence_type\",
        \"evidence_data\": $evidence_data,
        \"user_id\": \"$USER_ID\",
        \"project_id\": \"$PROJECT_ID\"
      }" > /dev/null 2>&1 &
}

# Rest of your existing hook code...
```

### Step 3: Call Reporting Function

Add reporting calls at key points in your hook:

**When evidence is present (allowing through):**
```bash
# At the end of pre-completion-check.sh, before final `exit 0`

# All checks passed
report_evidence "$CATEGORY" "verification_passed" "passed" 0 ""
exit 0
```

**When blocking for missing evidence:**
```bash
# In PART 6: BLOCK IF EVIDENCE MISSING section, before final exit

if [ ${#CRITICAL_MISSING[@]} -gt 0 ] || [ ${#MISSING[@]} -gt 0 ]; then
    # ...existing error output...

    # Report to central system
    local missing_items=$(printf '%s,' "${CRITICAL_MISSING[@]}" "${MISSING[@]}")
    report_evidence "$CATEGORY" "verification_failed" "blocked" 13 "Missing: $missing_items"

    exit 13
fi
```

**When blocking for mock implementations:**
```bash
# In PART 3: CHECK FOR MOCK IMPLEMENTATIONS section

if echo "$LAST_MESSAGES" | grep -qiE "mock(ed)?..."; then
    # ...existing error output...

    report_evidence "all" "mock_detected" "blocked" 10 "Mock/placeholder implementation"
    exit 10
fi
```

**When blocking for forbidden phrases:**
```bash
# In PART 4: CHECK FOR FORBIDDEN PHRASES section

for phrase in "${FORBIDDEN_PHRASES[@]}"; do
    if echo "$LAST_MESSAGES" | grep -qiF "$phrase"; then
        # ...existing error output...

        report_evidence "all" "forbidden_phrase" "blocked" 11 "Phrase: $phrase"
        exit 11
    fi
done
```

### Step 4: Test Integration

After updating your hooks, test that reporting works:

```bash
# Trigger a verification (any Claude Code task that creates completion claim)
# Then check central system received it:

curl -s 'http://91.99.237.14:8300/api/evidence/search?user_id=YOUR_USERNAME' | python3 -m json.tool
```

You should see your evidence entries with your username and project.

---

## Part 3: Using the Dashboard

### Viewing Evidence

1. Open http://91.99.237.14:8301
2. Click "Evidence Repository" tab
3. See all verification evidence from your team
4. Filter by:
   - Task category (web, api, infrastructure)
   - Project ID
   - Date range

### Searching Knowledge Base

1. Click "Knowledge Base" tab
2. Use search box to find patterns and solutions
3. View categories:
   - `verification` - Verification best practices
   - `coding-standards` - Code quality standards
   - `troubleshooting` - Common issues and fixes

### Managing Hook Configuration

1. Click "Hook Configuration" tab
2. View all active hooks and their settings
3. See which hooks are enabled/disabled
4. Configuration includes:
   - `web_puppeteer_required` - Enforce Puppeteer
   - `api_response_data_required` - Require response data
   - `mock_zero_tolerance` - Block mocks
   - `forbidden_phrases` - Block "should" language

---

## Part 4: API Integration Examples

### Submit Evidence Programmatically

```bash
curl -X POST http://91.99.237.14:8300/api/evidence \
  -H "Content-Type: application/json" \
  -d '{
    "task_category": "web",
    "evidence_type": "puppeteer_test",
    "evidence_data": {
      "screenshot_path": "/tmp/screenshot.png",
      "rating": 8,
      "console_errors": 0,
      "test_duration_ms": 1234
    },
    "user_id": "dev@hcb.com",
    "project_id": "flowmaster"
  }'
```

### Search Evidence

```bash
# By category
curl 'http://91.99.237.14:8300/api/evidence/search?category=web'

# By project
curl 'http://91.99.237.14:8300/api/evidence/search?project_id=flowmaster'

# By date range
curl 'http://91.99.237.14:8300/api/evidence/search?from_date=2025-01-01&to_date=2025-01-31'

# Combined filters
curl 'http://91.99.237.14:8300/api/evidence/search?category=api&project_id=flowmaster&from_date=2025-01-01'
```

### Add Knowledge Entry

```bash
curl -X POST http://91.99.237.14:8300/api/knowledge \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Docker Container Health Check Best Practices",
    "content": "Always use wget or curl in health checks. Ensure the tool is installed in your Alpine images.",
    "category": "infrastructure",
    "tags": ["docker", "health-check", "alpine"],
    "author_id": "team@hcb.com"
  }'
```

### Get Compliance Metrics

```bash
# Overall metrics
curl http://91.99.237.14:8300/api/metrics/compliance

# Project-specific
curl 'http://91.99.237.14:8300/api/metrics/compliance?project_id=flowmaster'

# Date range
curl 'http://91.99.237.14:8300/api/metrics/compliance?from_date=2025-01-01&to_date=2025-01-31'
```

---

## Part 5: Team Rollout

### For Individual Developers

1. **Install local hooks** (from main repository):
   ```bash
   git clone https://github.com/HCB-Consulting-ME/claude-sdlc-governance.git
   cd claude-sdlc-governance
   ./install.sh
   ```

2. **Update hooks with central reporting** (follow Part 2 above)

3. **Access dashboard**: http://91.99.237.14:8301

4. **Start using**: Claude Code will now report evidence automatically

### For Team Leads

1. **Monitor compliance**: Check dashboard daily at http://91.99.237.14:8301

2. **Review evidence**: Search for blocked verifications to identify training needs

3. **Update knowledge**: Add team patterns to knowledge base via API

4. **Track metrics**: Use compliance metrics to measure improvement

---

## Part 6: Troubleshooting

### Hook Not Reporting Evidence

**Check 1: Network connectivity**
```bash
curl -v http://91.99.237.14:8300/health
```

**Check 2: Hook has reporting function**
```bash
grep -A 5 "report_evidence" ~/.claude/hooks/pre-completion-check.sh
```

**Check 3: View hook execution**
```bash
# Add debug logging to hook
echo "DEBUG: Reporting evidence for $CATEGORY" >&2
```

### Dashboard Not Loading

**Check 1: Service status**
```bash
curl http://91.99.237.14:8301/health
```

**Check 2: Container running**
```bash
ssh server "docker ps | grep governance-dashboard"
```

**Check 3: View logs**
```bash
ssh server "docker logs governance-dashboard"
```

### API Returning Errors

**Check 1: Database connection**
```bash
curl http://91.99.237.14:8300/health | jq '.database'
```

**Check 2: View API logs**
```bash
ssh server "docker logs governance-api"
```

**Check 3: Test database directly**
```bash
ssh server "docker exec governance-db pg_isready -U governance_app"
```

### Evidence Not Appearing in Dashboard

**Check 1: Verify evidence was submitted**
```bash
curl -s 'http://91.99.237.14:8300/api/evidence/search' | python3 -m json.tool | head -30
```

**Check 2: Check database**
```bash
ssh server "docker exec -it governance-db psql -U governance_app -d governance -c 'SELECT count(*) FROM evidence_repository;'"
```

**Check 3: Verify user_id matches**
```bash
echo "Your user_id: ${USER}@$(hostname)"
```

---

## Part 7: Maintenance

### Backup Database

```bash
ssh server
cd /srv/projects/claude-governance-central

# Create backup
docker exec governance-db pg_dump -U governance_app governance > backup_$(date +%Y%m%d).sql

# Restore backup
docker exec -i governance-db psql -U governance_app governance < backup_20250121.sql
```

### View Logs

```bash
# All services
ssh server "cd /srv/projects/claude-governance-central && docker compose logs -f"

# Specific service
ssh server "docker logs -f governance-api"

# Last 100 lines
ssh server "docker logs --tail=100 governance-db"
```

### Restart Services

```bash
# Restart all
ssh server "cd /srv/projects/claude-governance-central && docker compose restart"

# Restart specific service
ssh server "cd /srv/projects/claude-governance-central && docker compose restart governance-api"
```

### Update System

```bash
# Pull latest changes (when available)
cd ~/Development/claude-governance-central
git pull

# Redeploy
./deploy.sh
```

---

## Quick Reference Card

**Dashboard**: http://91.99.237.14:8301
**API**: http://91.99.237.14:8300
**Database Port**: 5433

**Key Endpoints**:
- Health: `/health`
- Evidence: `/api/evidence/search`
- Knowledge: `/api/knowledge/search`
- Hooks: `/api/hooks/config`
- Metrics: `/api/metrics/compliance`

**Logs**:
```bash
ssh server "docker logs -f governance-api"
```

**Database**:
```bash
ssh server "docker exec -it governance-db psql -U governance_app -d governance"
```

---

## Support

- **System Issues**: Check logs first
- **API Documentation**: See README.md
- **Hook Integration**: See Part 2 above
- **Team Questions**: [Your team chat]

## Security Note

Current deployment is **internal dev server only**. For production:
- [ ] Add authentication to API
- [ ] Enable HTTPS
- [ ] Change database password (in `.env` file)
- [ ] Configure firewall rules
- [ ] Set up regular backups
