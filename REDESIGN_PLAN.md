# Claude Governance Central - V2 Redesign Plan

## Executive Summary

Transform the basic governance dashboard into a comprehensive multi-agent SDLC governance platform with knowledge graph integration, MCP server monitoring, and team collaboration features.

## Current State Analysis

### What Exists
1. **ArangoDB Knowledge Graph** (localhost:8529, flowmaster DB)
   - 90+ collections including:
     - `knowledge_patterns` - Patterns and solutions
     - `mcp_servers` - MCP server registry
     - `agent_guidance` - Agent instructions and guidance
     - `learning_instructions` - Learning patterns
     - Multiple edge collections for graph relationships

2. **Basic Governance System** (91.99.237.14:8300/8301)
   - PostgreSQL for evidence storage
   - Static HTML dashboard
   - Evidence submission API
   - Hook configuration storage

3. **Hooks System**
   - `pre-completion-check.sh` - Evidence validation
   - `user-prompt-submit-hook` - ZERO TRUST requirements display

### What's Missing
1. **Hook Management** - No UI to edit/view/test hooks
2. **MCP Integration** - No monitoring of MCP servers, tools, connections
3. **Knowledge Graph Access** - Existing graph not accessible via governance UI
4. **Contextual Evidence** - Evidence not linked to prompts/tasks
5. **Multi-Agent Support** - No user isolation or team workspaces
6. **Standards Repository** - No coding standards, requirements, architecture patterns
7. **MCP Tool Testing** - No way to query MCP tools via UI
8. **Import/Export** - No graph data import/export functionality

## V2 Architecture Design

### Technology Stack

```yaml
Backend:
  - Node.js/Express API (existing)
  - PostgreSQL (evidence, users, sessions)
  - ArangoDB (knowledge graph, patterns, standards)
  - Redis (MCP connection tracking, sessions)

Frontend:
  - React + TypeScript (replace static HTML)
  - TanStack Query (data fetching)
  - Cytoscape.js (graph visualization)
  - Monaco Editor (hook editing)
  - Shadcn/ui (component library)

Integration:
  - MCP Inspector API (tool discovery, testing)
  - Puppeteer (hook testing, verification)
  - ArangoDB HTTP API (graph queries)
```

### Database Schema Evolution

#### PostgreSQL Extensions

```sql
-- Users and Authentication
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(255) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  full_name VARCHAR(255),
  team_id UUID REFERENCES teams(id),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  organization VARCHAR(255),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Enhanced Evidence with Context
CREATE TABLE evidence_repository_v2 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID,
  user_id UUID REFERENCES users(id),
  team_id UUID REFERENCES teams(id),
  task_category VARCHAR(50),
  evidence_type VARCHAR(100),
  evidence_data JSONB,

  -- NEW: Contextual linking
  prompt_text TEXT,
  completion_text TEXT,
  conversation_id UUID,

  -- NEW: Graph references
  knowledge_pattern_id VARCHAR(255), -- Link to ArangoDB
  coding_standard_id VARCHAR(255),   -- Link to ArangoDB

  created_at TIMESTAMP DEFAULT NOW(),
  visibility VARCHAR(20) DEFAULT 'team' -- 'private', 'team', 'organization', 'public'
);

-- MCP Server Registry
CREATE TABLE mcp_servers_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  command VARCHAR(500),
  args JSONB,
  status VARCHAR(50), -- 'active', 'inactive', 'error'
  last_heartbeat TIMESTAMP,
  tools_discovered JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- MCP Connections
CREATE TABLE mcp_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES mcp_servers_registry(id),
  user_id UUID REFERENCES users(id),
  status VARCHAR(50),
  connected_at TIMESTAMP,
  disconnected_at TIMESTAMP
);

-- Hook Configurations (enhanced)
CREATE TABLE hook_configurations_v2 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  category VARCHAR(50),
  hook_type VARCHAR(50), -- 'pre-completion', 'user-prompt-submit', 'custom'
  script_content TEXT,
  enabled BOOLEAN DEFAULT true,
  team_id UUID REFERENCES teams(id),
  version INT DEFAULT 1,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

#### ArangoDB Collections (New)

```javascript
// Coding Standards
{
  collection: "coding_standards",
  type: "document",
  schema: {
    _key: "standard_id",
    name: "string",
    category: "string", // "naming", "architecture", "security", "performance"
    content: "markdown",
    examples: ["code_example"],
    severity: "critical|high|medium|low",
    tags: ["string"],
    team_id: "uuid"
  }
}

// Requirements
{
  collection: "requirements",
  type: "document",
  schema: {
    _key: "requirement_id",
    title: "string",
    description: "markdown",
    category: "functional|non-functional|technical",
    priority: "number",
    status: "draft|approved|implemented|validated",
    acceptance_criteria: ["string"],
    related_evidence: ["uuid"], // Links to PostgreSQL evidence
    team_id: "uuid"
  }
}

// Architecture Patterns
{
  collection: "architecture_patterns",
  type: "document",
  schema: {
    _key: "pattern_id",
    name: "string",
    pattern_type: "string", // "microservices", "event-driven", "layered"
    description: "markdown",
    diagram: "url|svg",
    components: ["component_spec"],
    best_practices: ["string"],
    anti_patterns: ["string"],
    team_id: "uuid"
  }
}

// MCP Tool Executions
{
  collection: "mcp_tool_executions",
  type: "document",
  schema: {
    _key: "execution_id",
    server_name: "string",
    tool_name: "string",
    input_params: "object",
    output_result: "object",
    user_id: "uuid",
    execution_time_ms: "number",
    status: "success|error",
    error_message: "string",
    timestamp: "datetime"
  }
}

// Edge: Evidence Links to Standards
{
  collection: "evidence_validates_standard",
  type: "edge",
  schema: {
    _from: "evidence_repository/{evidence_id}",
    _to: "coding_standards/{standard_id}",
    validation_status: "passed|failed",
    notes: "string"
  }
}
```

### API Endpoints (New)

```yaml
Authentication:
  POST /api/auth/login: "User login"
  POST /api/auth/logout: "User logout"
  GET /api/auth/me: "Current user info"

Users & Teams:
  GET /api/users: "List users (team-scoped)"
  GET /api/teams/:id: "Get team details"
  POST /api/teams: "Create team"

Knowledge Graph:
  GET /api/knowledge/patterns: "List knowledge patterns from ArangoDB"
  POST /api/knowledge/patterns: "Create new pattern"
  GET /api/knowledge/standards: "List coding standards"
  POST /api/knowledge/standards: "Create coding standard"
  GET /api/knowledge/requirements: "List requirements"
  POST /api/knowledge/requirements: "Create requirement"
  GET /api/knowledge/architecture: "List architecture patterns"
  POST /api/knowledge/export: "Export knowledge graph"
  POST /api/knowledge/import: "Import knowledge graph"

MCP Management:
  GET /api/mcp/servers: "List MCP servers"
  GET /api/mcp/servers/:id/tools: "List tools for server"
  POST /api/mcp/servers/:id/test-tool: "Test MCP tool execution"
  GET /api/mcp/connections: "Active MCP connections"
  GET /api/mcp/servers/:id/stats: "Server usage statistics"

Hooks Management:
  GET /api/hooks: "List hooks (team-scoped)"
  GET /api/hooks/:id: "Get hook details"
  PUT /api/hooks/:id: "Update hook script"
  POST /api/hooks/:id/test: "Test hook with sample data"
  POST /api/hooks/:id/deploy: "Deploy hook to team members"

Evidence (Enhanced):
  GET /api/evidence/search: "Search evidence with filters + context"
  POST /api/evidence: "Submit evidence with context"
  GET /api/evidence/:id/context: "Get full prompt/completion context"
  GET /api/evidence/:id/graph: "Get related graph knowledge"

Graph Queries:
  POST /api/graph/query: "Execute AQL query"
  POST /api/graph/visualize: "Get graph visualization data"
  GET /api/graph/related/:nodeId: "Get related nodes"
```

### Frontend Features

#### 1. Dashboard (Enhanced)
- **User-Specific Stats**: Show only current user's evidence by default
- **Team View**: Toggle to see team-wide statistics
- **Real-Time Updates**: WebSocket for live MCP connection status
- **Quick Actions**: Test hook, query MCP tool, search knowledge

#### 2. Hook Manager
- **List View**: All hooks with status, last modified, team
- **Editor**: Monaco editor with syntax highlighting
- **Test Runner**: Execute hook with sample data, view output
- **Version Control**: Track hook changes, rollback capability
- **Deploy**: Push hook updates to team members

#### 3. Knowledge Graph Explorer
- **Graph Visualization**: Cytoscape.js interactive graph
- **Search**: Full-text search across patterns, standards, requirements
- **Filters**: By category, team, tags, date
- **Editor**: Create/edit standards, patterns, requirements
- **Import/Export**: JSON/GraphML format support

#### 4. MCP Server Monitor
- **Server List**: All configured MCP servers with status
- **Tool Inspector**: Browse available tools per server
- **Connection Tracker**: Who's using which server
- **Tool Tester**: Input form for each tool, execute and see results
- **Usage Analytics**: Most used tools, error rates, performance

#### 5. Evidence Repository
- **Smart Search**: Filter by user, team, category, date, context
- **Context View**: See full prompt + completion for each evidence
- **Graph Links**: Visual links to related standards/patterns
- **Validation**: Check if evidence validates coding standards
- **Export**: CSV/JSON export with filters

#### 6. Standards Library
- **Coding Standards**: Browse, search, create standards
- **Requirements**: Track requirements with acceptance criteria
- **Architecture**: Document and visualize architecture patterns
- **Validation**: See which evidence validates each standard

## Implementation Phases

### Phase 1: Foundation (Week 1)
1. Set up React + TypeScript frontend
2. Add user authentication (JWT)
3. Create team/user database schema
4. Implement user-scoped evidence queries

### Phase 2: MCP Integration (Week 1-2)
1. MCP server registry and monitoring
2. Tool discovery API
3. Connection tracking (Redis)
4. Tool testing interface

### Phase 3: Hook Management (Week 2)
1. Hook CRUD API
2. Monaco editor integration
3. Hook testing with Puppeteer
4. Version control

### Phase 4: Knowledge Graph (Week 2-3)
1. ArangoDB integration
2. Standards/requirements/patterns API
3. Graph visualization (Cytoscape.js)
4. Import/export functionality

### Phase 5: Enhanced Evidence (Week 3)
1. Link evidence to prompts/completions
2. Graph knowledge linking
3. Validation against standards
4. Context-aware search

### Phase 6: Polish & Deploy (Week 3-4)
1. Real-time updates (WebSockets)
2. Analytics dashboard
3. Mobile responsive design
4. Production deployment

## Migration Strategy

### Data Migration
1. **Keep PostgreSQL Evidence**: Existing evidence stays intact
2. **Sync ArangoDB**: Connect to existing flowmaster DB
3. **Create Bridge Tables**: Link PostgreSQL UUIDs to ArangoDB _keys
4. **User Migration**: Import existing users from evidence repository

### Deployment Strategy
1. **Parallel Running**: V1 and V2 run simultaneously
2. **Feature Flags**: Gradual rollout of new features
3. **Backward Compatibility**: Existing hook integration still works
4. **Zero Downtime**: Blue-green deployment

## Success Metrics

1. **Adoption**: % of team using hook manager
2. **Knowledge Growth**: # of standards/patterns added
3. **MCP Usage**: # of tool executions via UI
4. **Evidence Quality**: % of evidence linked to standards
5. **Team Collaboration**: # of cross-team knowledge shares

## Next Steps

1. Review and approve this redesign plan
2. Set up React project structure
3. Create detailed API specifications
4. Design UI mockups (Figma)
5. Sprint planning for Phase 1
