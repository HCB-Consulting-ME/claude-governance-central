-- Claude Governance Central V2 - Database Migrations
-- Adds user authentication, teams, and enhanced evidence tracking

-- Users table
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(255) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(255),
  team_id UUID,
  role VARCHAR(50) DEFAULT 'developer', -- 'admin', 'lead', 'developer'
  created_at TIMESTAMP DEFAULT NOW(),
  last_login TIMESTAMP
);

-- Teams table
CREATE TABLE IF NOT EXISTS teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  organization VARCHAR(255),
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW()
);

-- Add foreign key after teams table exists
ALTER TABLE users ADD CONSTRAINT fk_user_team
  FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL;

-- Enhanced evidence repository with context
CREATE TABLE IF NOT EXISTS evidence_repository_v2 (
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

  -- NEW: Graph references (ArangoDB _key values)
  knowledge_pattern_id VARCHAR(255),
  coding_standard_id VARCHAR(255),
  requirement_id VARCHAR(255),

  created_at TIMESTAMP DEFAULT NOW(),
  visibility VARCHAR(20) DEFAULT 'team', -- 'private', 'team', 'organization', 'public'

  CONSTRAINT fk_evidence_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_evidence_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL
);

CREATE INDEX idx_evidence_v2_user ON evidence_repository_v2(user_id);
CREATE INDEX idx_evidence_v2_team ON evidence_repository_v2(team_id);
CREATE INDEX idx_evidence_v2_category ON evidence_repository_v2(task_category);
CREATE INDEX idx_evidence_v2_conversation ON evidence_repository_v2(conversation_id);

-- MCP Server Registry
CREATE TABLE IF NOT EXISTS mcp_servers_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL UNIQUE,
  command VARCHAR(500),
  args JSONB,
  env JSONB,
  status VARCHAR(50) DEFAULT 'unknown', -- 'active', 'inactive', 'error', 'unknown'
  last_heartbeat TIMESTAMP,
  tools_discovered JSONB,
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- MCP Server Connections (active sessions)
CREATE TABLE IF NOT EXISTS mcp_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES mcp_servers_registry(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  connection_id VARCHAR(255),
  status VARCHAR(50) DEFAULT 'connected',
  connected_at TIMESTAMP DEFAULT NOW(),
  disconnected_at TIMESTAMP,
  metadata JSONB
);

CREATE INDEX idx_mcp_connections_server ON mcp_connections(server_id);
CREATE INDEX idx_mcp_connections_user ON mcp_connections(user_id);
CREATE INDEX idx_mcp_connections_status ON mcp_connections(status);

-- MCP Tool Executions (audit log)
CREATE TABLE IF NOT EXISTS mcp_tool_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES mcp_servers_registry(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  tool_name VARCHAR(255) NOT NULL,
  input_params JSONB,
  output_result JSONB,
  execution_time_ms INTEGER,
  status VARCHAR(50), -- 'success', 'error'
  error_message TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_tool_exec_server ON mcp_tool_executions(server_id);
CREATE INDEX idx_tool_exec_user ON mcp_tool_executions(user_id);
CREATE INDEX idx_tool_exec_created ON mcp_tool_executions(created_at);

-- Hook Configurations V2 (team-scoped, versioned)
CREATE TABLE IF NOT EXISTS hook_configurations_v2 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  category VARCHAR(50),
  hook_type VARCHAR(50) NOT NULL, -- 'pre-completion', 'user-prompt-submit', 'custom'
  script_content TEXT NOT NULL,
  enabled BOOLEAN DEFAULT true,
  team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
  version INTEGER DEFAULT 1,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(name, team_id, version)
);

CREATE INDEX idx_hook_v2_team ON hook_configurations_v2(team_id);
CREATE INDEX idx_hook_v2_type ON hook_configurations_v2(hook_type);

-- Hook Test Results
CREATE TABLE IF NOT EXISTS hook_test_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  hook_id UUID REFERENCES hook_configurations_v2(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  test_input JSONB,
  test_output JSONB,
  exit_code INTEGER,
  passed BOOLEAN,
  execution_time_ms INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Sessions for JWT tokens
CREATE TABLE IF NOT EXISTS user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(255) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  last_activity TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(token_hash);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at);

-- Seed default team and admin user (password: admin123 - change in production!)
INSERT INTO teams (id, name, organization)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default Team', 'HCB Consulting')
ON CONFLICT DO NOTHING;

-- Default admin user (username: admin, password: admin123)
INSERT INTO users (id, username, email, password_hash, full_name, team_id, role)
VALUES (
  '00000000-0000-0000-0000-000000000002',
  'admin',
  'admin@hcb.com',
  '$2b$10$rKzHvE9jXzX7vN5vZ5vZ5.7vZ5vZ5vZ5vZ5vZ5vZ5vZ5vZ5vZ5vZ5', -- admin123
  'System Administrator',
  '00000000-0000-0000-0000-000000000001',
  'admin'
)
ON CONFLICT DO NOTHING;

-- Migrate existing evidence to V2 (if old table exists)
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'evidence_repository') THEN
    INSERT INTO evidence_repository_v2 (
      task_id, task_category, evidence_type, evidence_data, created_at, user_id, team_id
    )
    SELECT
      task_id,
      task_category,
      evidence_type,
      evidence_data,
      created_at,
      '00000000-0000-0000-0000-000000000002', -- Assign to admin
      '00000000-0000-0000-0000-000000000001'  -- Assign to default team
    FROM evidence_repository
    WHERE NOT EXISTS (
      SELECT 1 FROM evidence_repository_v2 WHERE evidence_repository_v2.task_id = evidence_repository.task_id
    );
  END IF;
END $$;

-- Migrate existing hook configurations to V2
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'hook_configurations') THEN
    INSERT INTO hook_configurations_v2 (
      name, category, hook_type, script_content, enabled, team_id, created_by
    )
    SELECT
      name,
      category,
      'pre-completion', -- Default type
      description, -- Use description as placeholder content
      enabled,
      '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002'
    FROM hook_configurations
    WHERE NOT EXISTS (
      SELECT 1 FROM hook_configurations_v2
      WHERE hook_configurations_v2.name = hook_configurations.name
    );
  END IF;
END $$;

COMMENT ON TABLE users IS 'User accounts with authentication';
COMMENT ON TABLE teams IS 'Team workspaces for multi-tenant support';
COMMENT ON TABLE evidence_repository_v2 IS 'Enhanced evidence with context and graph linking';
COMMENT ON TABLE mcp_servers_registry IS 'Registry of all configured MCP servers';
COMMENT ON TABLE mcp_connections IS 'Active MCP server connections';
COMMENT ON TABLE mcp_tool_executions IS 'Audit log of MCP tool executions';
COMMENT ON TABLE hook_configurations_v2 IS 'Team-scoped, versioned hook configurations';
