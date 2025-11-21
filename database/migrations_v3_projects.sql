-- V3 Migration: Project-Aware Multi-Environment Architecture
-- Description: Adds project and environment tracking for multi-repo, multi-environment governance

-- ============================================================
-- PROJECTS & REPOSITORIES
-- ============================================================

CREATE TABLE IF NOT EXISTS projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  repo_url VARCHAR(500),
  repo_provider VARCHAR(50), -- 'github', 'gitlab', 'bitbucket', 'other'
  team_id UUID REFERENCES teams(id),
  default_branch VARCHAR(100) DEFAULT 'main',
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repo_url, team_id)
);

CREATE INDEX idx_projects_team ON projects(team_id);
CREATE INDEX idx_projects_repo_url ON projects(repo_url);

-- ============================================================
-- ENVIRONMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS environments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL, -- 'local', 'dev', 'staging', 'prod', custom names
  type VARCHAR(50) NOT NULL, -- 'local', 'shared', 'production'
  hostname VARCHAR(255), -- e.g., 'alice-macbook', 'dev-server-01'
  user_id UUID REFERENCES users(id), -- Owner for 'local' type environments
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(project_id, name, user_id) -- Prevent duplicate env names per project/user
);

CREATE INDEX idx_environments_project ON environments(project_id);
CREATE INDEX idx_environments_user ON environments(user_id);
CREATE INDEX idx_environments_hostname ON environments(hostname);

-- ============================================================
-- ENHANCE EVIDENCE WITH PROJECT CONTEXT
-- ============================================================

ALTER TABLE evidence_repository_v2
ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id),
ADD COLUMN IF NOT EXISTS environment_id UUID REFERENCES environments(id),
ADD COLUMN IF NOT EXISTS repo_branch VARCHAR(255),
ADD COLUMN IF NOT EXISTS commit_sha VARCHAR(40),
ADD COLUMN IF NOT EXISTS git_remote VARCHAR(500);

CREATE INDEX IF NOT EXISTS idx_evidence_project ON evidence_repository_v2(project_id);
CREATE INDEX IF NOT EXISTS idx_evidence_environment ON evidence_repository_v2(environment_id);
CREATE INDEX IF NOT EXISTS idx_evidence_commit ON evidence_repository_v2(commit_sha);
CREATE INDEX IF NOT EXISTS idx_evidence_branch ON evidence_repository_v2(repo_branch);

-- ============================================================
-- PROJECT-SPECIFIC KNOWLEDGE LINKS (BRIDGE TO ARANGODB)
-- ============================================================

CREATE TABLE IF NOT EXISTS project_knowledge_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  knowledge_type VARCHAR(50) NOT NULL, -- 'standard', 'requirement', 'pattern', 'architecture'
  knowledge_id VARCHAR(255) NOT NULL, -- ArangoDB _key
  scope VARCHAR(50) DEFAULT 'project', -- 'global', 'project', 'environment'
  created_at TIMESTAMP DEFAULT NOW(),
  created_by UUID REFERENCES users(id),
  UNIQUE(project_id, knowledge_type, knowledge_id)
);

CREATE INDEX idx_knowledge_links_project ON project_knowledge_links(project_id);
CREATE INDEX idx_knowledge_links_type ON project_knowledge_links(knowledge_type);

-- ============================================================
-- PROJECT-SCOPED HOOKS
-- ============================================================

ALTER TABLE hook_configurations_v2
ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id),
ADD COLUMN IF NOT EXISTS scope VARCHAR(50) DEFAULT 'team'; -- 'global', 'team', 'project'

CREATE INDEX IF NOT EXISTS idx_hooks_project ON hook_configurations_v2(project_id);
CREATE INDEX IF NOT EXISTS idx_hooks_scope ON hook_configurations_v2(scope);

-- ============================================================
-- MCP TOOL EXECUTIONS (PROJECT CONTEXT)
-- ============================================================

CREATE TABLE IF NOT EXISTS mcp_tool_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES mcp_servers_registry(id),
  user_id UUID REFERENCES users(id),
  project_id UUID REFERENCES projects(id), -- NEW
  environment_id UUID REFERENCES environments(id), -- NEW
  tool_name VARCHAR(255) NOT NULL,
  input_params JSONB,
  output_result JSONB,
  execution_time_ms INT,
  status VARCHAR(50), -- 'success', 'error', 'timeout'
  error_message TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_tool_executions_server ON mcp_tool_executions(server_id);
CREATE INDEX idx_tool_executions_user ON mcp_tool_executions(user_id);
CREATE INDEX idx_tool_executions_project ON mcp_tool_executions(project_id);
CREATE INDEX idx_tool_executions_status ON mcp_tool_executions(status);

-- ============================================================
-- DEFAULT DATA: LEGACY PROJECT
-- ============================================================

-- Create default "Legacy Project" for existing evidence
INSERT INTO projects (id, name, description, team_id)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Legacy Project',
  'Default project for evidence created before V3',
  (SELECT id FROM teams LIMIT 1)
)
ON CONFLICT DO NOTHING;

-- Create default "production" environment
INSERT INTO environments (id, project_id, name, type, hostname)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'production',
  'production',
  'governance-server'
)
ON CONFLICT DO NOTHING;

-- Link existing evidence to legacy project (only if null)
UPDATE evidence_repository_v2 SET
  project_id = '00000000-0000-0000-0000-000000000001',
  environment_id = '00000000-0000-0000-0000-000000000001'
WHERE project_id IS NULL;

-- ============================================================
-- HELPER VIEWS
-- ============================================================

-- View: Project summary with counts
CREATE OR REPLACE VIEW project_summary AS
SELECT
  p.id,
  p.name,
  p.repo_url,
  p.team_id,
  t.name as team_name,
  COUNT(DISTINCT e.id) as evidence_count,
  COUNT(DISTINCT env.id) as environment_count,
  COUNT(DISTINCT pkls.id) as knowledge_link_count,
  MAX(e.created_at) as last_evidence_at,
  p.created_at,
  p.updated_at
FROM projects p
LEFT JOIN teams t ON p.team_id = t.id
LEFT JOIN evidence_repository_v2 e ON p.id = e.project_id
LEFT JOIN environments env ON p.id = env.project_id
LEFT JOIN project_knowledge_links pkls ON p.id = pkls.project_id
GROUP BY p.id, p.name, p.repo_url, p.team_id, t.name, p.created_at, p.updated_at;

-- View: Environment summary with evidence counts
CREATE OR REPLACE VIEW environment_summary AS
SELECT
  env.id,
  env.name,
  env.type,
  env.hostname,
  env.project_id,
  p.name as project_name,
  env.user_id,
  u.username,
  COUNT(DISTINCT e.id) as evidence_count,
  MAX(e.created_at) as last_evidence_at,
  env.created_at
FROM environments env
LEFT JOIN projects p ON env.project_id = p.id
LEFT JOIN users u ON env.user_id = u.id
LEFT JOIN evidence_repository_v2 e ON env.id = e.environment_id
GROUP BY env.id, env.name, env.type, env.hostname, env.project_id, p.name, env.user_id, u.username, env.created_at;

-- View: Evidence with full project context
CREATE OR REPLACE VIEW evidence_with_context AS
SELECT
  e.id,
  e.task_category,
  e.evidence_type,
  e.created_at,
  e.user_id,
  u.username,
  e.team_id,
  t.name as team_name,
  e.project_id,
  p.name as project_name,
  p.repo_url,
  e.environment_id,
  env.name as environment_name,
  env.type as environment_type,
  e.repo_branch,
  e.commit_sha,
  e.prompt_text,
  e.completion_text,
  e.knowledge_pattern_id,
  e.coding_standard_id,
  e.visibility
FROM evidence_repository_v2 e
LEFT JOIN users u ON e.user_id = u.id
LEFT JOIN teams t ON e.team_id = t.id
LEFT JOIN projects p ON e.project_id = p.id
LEFT JOIN environments env ON e.environment_id = env.id;

-- ============================================================
-- MIGRATION COMPLETE
-- ============================================================
