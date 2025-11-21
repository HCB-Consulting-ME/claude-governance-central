-- Claude Governance Central Database Schema
-- ZERO TRUST verification and knowledge management system

-- Create database (run as postgres user)
CREATE DATABASE governance;

\c governance;

-- ============================================================================
-- HOOK CONFIGURATIONS TABLE
-- Centrally managed hook configurations
-- ============================================================================

CREATE TABLE hook_configurations (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  category VARCHAR(100) NOT NULL,
  description TEXT,
  enabled BOOLEAN DEFAULT true,
  config JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_hook_category ON hook_configurations(category);
CREATE INDEX idx_hook_enabled ON hook_configurations(enabled);

-- Seed data
INSERT INTO hook_configurations (name, category, description, enabled, config) VALUES
('web_puppeteer_required', 'web', 'Require Puppeteer for web UI verification', true, '{
  "evidence_required": ["puppeteer_execution", "screenshot", "rating", "console_check"],
  "forbidden_alternatives": ["curl", "wget", "http_request"],
  "min_quality_rating": 7
}'::jsonb),

('api_response_data_required', 'api', 'Require actual API response data', true, '{
  "evidence_required": ["request_execution", "status_code", "response_data", "logs"],
  "status_code_only_insufficient": true
}'::jsonb),

('mock_zero_tolerance', 'all', 'Zero tolerance for mock implementations', true, '{
  "blocked_patterns": ["mockData", "mockUser", "placeholderText", "fallbackLogic", "stubMethod", "fakeAPI", "sampleData"],
  "exit_code": 10,
  "block_immediately": true
}'::jsonb),

('forbidden_phrases', 'all', 'Block speculative language', true, '{
  "phrases": ["should work", "should be working", "should now", "should display", "it should"],
  "exit_code": 11,
  "block_immediately": true
}'::jsonb);

-- ============================================================================
-- EVIDENCE REPOSITORY TABLE
-- Stores all verification evidence
-- ============================================================================

CREATE TABLE evidence_repository (
  id SERIAL PRIMARY KEY,
  task_id VARCHAR(255),
  task_category VARCHAR(100) NOT NULL,
  evidence_type VARCHAR(100) NOT NULL,
  evidence_data JSONB NOT NULL,
  user_id VARCHAR(255),
  project_id VARCHAR(255),
  created_at TIMESTAMP DEFAULT NOW(),
  metadata JSONB
);

CREATE INDEX idx_evidence_task ON evidence_repository(task_id);
CREATE INDEX idx_evidence_category ON evidence_repository(task_category);
CREATE INDEX idx_evidence_type ON evidence_repository(evidence_type);
CREATE INDEX idx_evidence_project ON evidence_repository(project_id);
CREATE INDEX idx_evidence_created ON evidence_repository(created_at);
CREATE INDEX idx_evidence_data ON evidence_repository USING GIN (evidence_data);

-- ============================================================================
-- VERIFICATION RULES TABLE
-- Configurable verification rules per task category
-- ============================================================================

CREATE TABLE verification_rules (
  id SERIAL PRIMARY KEY,
  category VARCHAR(100) NOT NULL,
  rule_name VARCHAR(255) NOT NULL,
  rule_type VARCHAR(100) NOT NULL,
  priority INTEGER DEFAULT 100,
  enabled BOOLEAN DEFAULT true,
  rule_config JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_rules_category ON verification_rules(category);
CREATE INDEX idx_rules_enabled ON verification_rules(enabled);
CREATE INDEX idx_rules_priority ON verification_rules(priority);

-- Seed data
INSERT INTO verification_rules (category, rule_name, rule_type, priority, enabled, rule_config) VALUES
('web', 'Puppeteer Mandatory', 'tool_requirement', 100, true, '{
  "required_tool": "puppeteer",
  "error_message": "Web UI must be tested with Puppeteer, not curl/HTTP"
}'::jsonb),

('web', 'Screenshot Required', 'evidence_requirement', 90, true, '{
  "evidence_type": "screenshot",
  "file_extension": ".png",
  "must_show_path": true
}'::jsonb),

('web', 'Quality Rating', 'evidence_requirement', 80, true, '{
  "evidence_type": "rating",
  "format": "X/10",
  "min_rating": 1,
  "max_rating": 10
}'::jsonb),

('api', 'Response Data Required', 'evidence_requirement', 100, true, '{
  "evidence_type": "response_data",
  "not_just_status": true,
  "must_show_json": true
}'::jsonb),

('infrastructure', 'Service Status Required', 'evidence_requirement', 100, true, '{
  "evidence_type": "service_status",
  "acceptable_commands": ["docker ps", "systemctl status", "kubectl get"]
}'::jsonb);

-- ============================================================================
-- KNOWLEDGE REPOSITORY TABLE
-- Central knowledge base for patterns, solutions, documentation
-- ============================================================================

CREATE TABLE knowledge_repository (
  id SERIAL PRIMARY KEY,
  title VARCHAR(500) NOT NULL,
  content TEXT NOT NULL,
  category VARCHAR(100) NOT NULL,
  tags JSONB,
  author_id VARCHAR(255),
  views INTEGER DEFAULT 0,
  helpful_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  search_vector tsvector
);

CREATE INDEX idx_knowledge_category ON knowledge_repository(category);
CREATE INDEX idx_knowledge_tags ON knowledge_repository USING GIN (tags);
CREATE INDEX idx_knowledge_search ON knowledge_repository USING GIN (search_vector);
CREATE INDEX idx_knowledge_updated ON knowledge_repository(updated_at);

-- Auto-update search vector
CREATE OR REPLACE FUNCTION knowledge_search_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.content, '')), 'B');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER knowledge_search_trigger
  BEFORE INSERT OR UPDATE ON knowledge_repository
  FOR EACH ROW EXECUTE FUNCTION knowledge_search_update();

-- Seed knowledge data
INSERT INTO knowledge_repository (title, content, category, tags, author_id) VALUES
('Web UI Verification Best Practices', 'Always use Puppeteer or Playwright for web UI verification. curl/HTTP requests only verify server response, not actual UI functionality.', 'verification', '["web", "puppeteer", "best-practice"]'::jsonb, 'system'),

('Mock Implementation Detection', 'Common mock patterns to avoid: mockData, placeholderText, fallbackLogic. Always implement real functionality or throw explicit errors.', 'coding-standards', '["mocks", "anti-pattern"]'::jsonb, 'system'),

('API Verification Requirements', 'API testing requires: 1) Actual request execution, 2) Status code, 3) Response data (not just status), 4) Application logs', 'verification', '["api", "backend", "testing"]'::jsonb, 'system');

-- ============================================================================
-- COMPLIANCE METRICS TABLE
-- Track verification compliance over time
-- ============================================================================

CREATE TABLE compliance_metrics (
  id SERIAL PRIMARY KEY,
  project_id VARCHAR(255),
  user_id VARCHAR(255),
  category VARCHAR(100),
  total_tasks INTEGER DEFAULT 0,
  verified_tasks INTEGER DEFAULT 0,
  blocked_tasks INTEGER DEFAULT 0,
  compliance_rate DECIMAL(5,2),
  date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_metrics_project ON compliance_metrics(project_id);
CREATE INDEX idx_metrics_date ON compliance_metrics(date);
CREATE INDEX idx_metrics_category ON compliance_metrics(category);

-- ============================================================================
-- HOOK EXECUTION LOG TABLE
-- Audit trail of hook executions
-- ============================================================================

CREATE TABLE hook_execution_log (
  id SERIAL PRIMARY KEY,
  hook_name VARCHAR(255) NOT NULL,
  user_id VARCHAR(255),
  project_id VARCHAR(255),
  execution_result VARCHAR(50) NOT NULL,
  exit_code INTEGER,
  error_message TEXT,
  evidence_provided JSONB,
  execution_time_ms INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_hook_log_hook ON hook_execution_log(hook_name);
CREATE INDEX idx_hook_log_result ON hook_execution_log(execution_result);
CREATE INDEX idx_hook_log_project ON hook_execution_log(project_id);
CREATE INDEX idx_hook_log_created ON hook_execution_log(created_at);

-- ============================================================================
-- VIEWS FOR REPORTING
-- ============================================================================

-- Compliance dashboard view
CREATE VIEW compliance_dashboard AS
SELECT
  DATE_TRUNC('day', created_at) as date,
  task_category,
  COUNT(*) as total_verifications,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT project_id) as unique_projects,
  COUNT(*) FILTER (WHERE evidence_type = 'passed') as passed,
  COUNT(*) FILTER (WHERE evidence_type = 'blocked') as blocked,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE evidence_type = 'passed') / NULLIF(COUNT(*), 0),
    2
  ) as pass_rate
FROM evidence_repository
GROUP BY DATE_TRUNC('day', created_at), task_category
ORDER BY date DESC, task_category;

-- Hook effectiveness view
CREATE VIEW hook_effectiveness AS
SELECT
  hook_name,
  execution_result,
  COUNT(*) as execution_count,
  AVG(execution_time_ms) as avg_execution_time,
  COUNT(DISTINCT user_id) as unique_users
FROM hook_execution_log
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY hook_name, execution_result
ORDER BY execution_count DESC;

-- Knowledge popularity view
CREATE VIEW knowledge_popular AS
SELECT
  id,
  title,
  category,
  tags,
  views,
  helpful_count,
  ROUND(helpful_count::DECIMAL / NULLIF(views, 0), 2) as helpfulness_ratio,
  updated_at
FROM knowledge_repository
WHERE views > 0
ORDER BY helpful_count DESC, views DESC
LIMIT 50;

-- ============================================================================
-- GRANTS (adjust based on your user)
-- ============================================================================

-- Grant permissions to application user
-- CREATE USER governance_app WITH PASSWORD 'your_secure_password';
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO governance_app;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO governance_app;
-- GRANT ALL PRIVILEGES ON DATABASE governance TO governance_app;
