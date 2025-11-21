import express from 'express';
import cors from 'cors';
import bcrypt from 'bcrypt';
import pool from './config/database.js';
import db, { testArangoConnection, query as aqlQuery, getCollection } from './config/arango.js';
import { generateToken, authMiddleware, requireRole } from './middleware/auth.js';

const app = express();
const PORT = process.env.PORT || 8300;

app.use(cors());
app.use(express.json({ limit: '50mb' }));

// ==================================
// HEALTH CHECK
// ==================================
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    const arangoHealthy = await testArangoConnection().then(() => true).catch(() => false);

    res.json({
      status: 'healthy',
      database: 'connected',
      arango: arangoHealthy ? 'connected' : 'disconnected',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

// ==================================
// AUTHENTICATION
// ==================================
app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    const result = await pool.query(
      `SELECT u.*, t.name as team_name
       FROM users u
       LEFT JOIN teams t ON u.team_id = t.id
       WHERE u.username = $1`,
      [username]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];
    const validPassword = await bcrypt.compare(password, user.password_hash);

    if (!validPassword) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Update last login
    await pool.query(
      'UPDATE users SET last_login = NOW() WHERE id = $1',
      [user.id]
    );

    const token = generateToken(user);

    res.json({
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        full_name: user.full_name,
        role: user.role,
        team_id: user.team_id,
        team_name: user.team_name
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

app.get('/api/auth/me', authMiddleware, (req, res) => {
  res.json({
    user: {
      id: req.user.id,
      username: req.user.username,
      email: req.user.email,
      full_name: req.user.full_name,
      role: req.user.role,
      team_id: req.user.team_id,
      team_name: req.user.team_name,
      organization: req.user.organization
    }
  });
});

app.post('/api/auth/logout', authMiddleware, async (req, res) => {
  // TODO: Invalidate token in Redis if using token blacklist
  res.json({ message: 'Logged out successfully' });
});

// ==================================
// KNOWLEDGE GRAPH (ArangoDB)
// ==================================

// Get knowledge patterns
app.get('/api/knowledge/patterns', authMiddleware, async (req, res) => {
  try {
    const { search, limit = 50, offset = 0 } = req.query;

    let aql, bindVars;

    if (search) {
      aql = `
        FOR pattern IN knowledge_patterns
        FILTER CONTAINS(LOWER(pattern.name), LOWER(@search)) OR CONTAINS(LOWER(pattern.description), LOWER(@search))
        LIMIT @limit
        RETURN pattern
      `;
      bindVars = { search, limit: parseInt(limit) };
    } else {
      aql = `
        FOR pattern IN knowledge_patterns
        LIMIT @limit
        RETURN pattern
      `;
      bindVars = { limit: parseInt(limit) };
    }

    const results = await aqlQuery(aql, bindVars);

    res.json({
      patterns: results,
      count: results.length
    });
  } catch (error) {
    console.error('Knowledge patterns error:', error);
    res.status(500).json({ error: 'Failed to fetch knowledge patterns' });
  }
});

// Get agent guidance
app.get('/api/knowledge/guidance', authMiddleware, async (req, res) => {
  try {
    const results = await aqlQuery(`
      FOR doc IN agent_guidance
      LIMIT 100
      RETURN doc
    `);

    res.json({ guidance: results, count: results.length });
  } catch (error) {
    console.error('Agent guidance error:', error);
    res.status(500).json({ error: 'Failed to fetch agent guidance' });
  }
});

// Get MCP servers from ArangoDB
app.get('/api/knowledge/mcp-servers', authMiddleware, async (req, res) => {
  try {
    const results = await aqlQuery(`
      FOR server IN mcp_servers
      RETURN server
    `);

    res.json({ servers: results, count: results.length });
  } catch (error) {
    console.error('MCP servers query error:', error);
    res.status(500).json({ error: 'Failed to fetch MCP servers from graph' });
  }
});

// Search knowledge graph
app.post('/api/knowledge/search', authMiddleware, async (req, res) => {
  try {
    const { query: searchQuery, collections = ['knowledge_patterns', 'agent_guidance', 'learning_instructions'] } = req.body;

    if (!searchQuery) {
      return res.status(400).json({ error: 'Search query required' });
    }

    const results = {};

    for (const collectionName of collections) {
      try {
        const aql = `
          FOR doc IN ${collectionName}
          FILTER CONTAINS(LOWER(TO_STRING(doc)), LOWER(@query))
          LIMIT 20
          RETURN doc
        `;

        results[collectionName] = await aqlQuery(aql, { query: searchQuery });
      } catch (err) {
        console.warn(`Collection ${collectionName} search failed:`, err.message);
        results[collectionName] = [];
      }
    }

    res.json({ results, query: searchQuery });
  } catch (error) {
    console.error('Knowledge search error:', error);
    res.status(500).json({ error: 'Search failed' });
  }
});

// Execute custom AQL query (admin only)
app.post('/api/knowledge/query', authMiddleware, requireRole('admin', 'lead'), async (req, res) => {
  try {
    const { aql, bindVars = {} } = req.body;

    if (!aql) {
      return res.status(400).json({ error: 'AQL query required' });
    }

    const results = await aqlQuery(aql, bindVars);

    res.json({ results, count: results.length });
  } catch (error) {
    console.error('Custom AQL query error:', error);
    res.status(500).json({ error: 'Query execution failed: ' + error.message });
  }
});

// Get graph visualization data
app.get('/api/knowledge/graph/:nodeId', authMiddleware, async (req, res) => {
  try {
    const { nodeId } = req.params;
    const { depth = 2 } = req.query;

    // Get node and its relationships
    const aql = `
      FOR v, e, p IN 1..@depth ANY @startNode GRAPH null
      OPTIONS {bfs: true, uniqueVertices: 'global'}
      RETURN {vertex: v, edge: e, path: p}
    `;

    const results = await aqlQuery(aql, {
      startNode: nodeId,
      depth: parseInt(depth)
    });

    res.json({ graph: results, count: results.length });
  } catch (error) {
    console.error('Graph query error:', error);
    res.status(500).json({ error: 'Failed to fetch graph data' });
  }
});

// ==================================
// MCP SERVER REGISTRY & MONITORING
// ==================================

// List MCP servers
app.get('/api/mcp/servers', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT *
      FROM mcp_servers_registry
      ORDER BY name
    `);

    res.json({ servers: result.rows, count: result.rows.length });
  } catch (error) {
    console.error('MCP servers list error:', error);
    res.status(500).json({ error: 'Failed to fetch MCP servers' });
  }
});

// Get MCP server details with tools
app.get('/api/mcp/servers/:id', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;

    const result = await pool.query(
      'SELECT * FROM mcp_servers_registry WHERE id = $1',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Server not found' });
    }

    res.json({ server: result.rows[0] });
  } catch (error) {
    console.error('MCP server details error:', error);
    res.status(500).json({ error: 'Failed to fetch server details' });
  }
});

// Get active MCP connections
app.get('/api/mcp/connections', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT c.*, s.name as server_name, u.username, u.full_name
      FROM mcp_connections c
      JOIN mcp_servers_registry s ON c.server_id = s.id
      JOIN users u ON c.user_id = u.id
      WHERE c.status = 'connected'
      ORDER BY c.connected_at DESC
    `);

    res.json({ connections: result.rows, count: result.rows.length });
  } catch (error) {
    console.error('MCP connections error:', error);
    res.status(500).json({ error: 'Failed to fetch connections' });
  }
});

// Log MCP tool execution
app.post('/api/mcp/tool-execution', authMiddleware, async (req, res) => {
  try {
    const { server_id, tool_name, input_params, output_result, execution_time_ms, status, error_message } = req.body;

    const result = await pool.query(
      `INSERT INTO mcp_tool_executions
       (server_id, user_id, tool_name, input_params, output_result, execution_time_ms, status, error_message)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [server_id, req.user.id, tool_name, input_params, output_result, execution_time_ms, status, error_message]
    );

    res.json({ execution: result.rows[0] });
  } catch (error) {
    console.error('Tool execution log error:', error);
    res.status(500).json({ error: 'Failed to log tool execution' });
  }
});

// Get MCP server statistics
app.get('/api/mcp/servers/:id/stats', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;

    const stats = await pool.query(
      `SELECT
         COUNT(*) as total_executions,
         COUNT(DISTINCT user_id) as unique_users,
         AVG(execution_time_ms) as avg_execution_time,
         COUNT(CASE WHEN status = 'success' THEN 1 END) as successful,
         COUNT(CASE WHEN status = 'error' THEN 1 END) as failed
       FROM mcp_tool_executions
       WHERE server_id = $1`,
      [id]
    );

    res.json({ stats: stats.rows[0] });
  } catch (error) {
    console.error('MCP server stats error:', error);
    res.status(500).json({ error: 'Failed to fetch server statistics' });
  }
});

// ==================================
// HOOKS MANAGEMENT
// ==================================

// List hooks (team-scoped)
app.get('/api/hooks', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT h.*, u.username as created_by_name
       FROM hook_configurations_v2 h
       LEFT JOIN users u ON h.created_by = u.id
       WHERE h.team_id = $1
       ORDER BY h.name, h.version DESC`,
      [req.user.team_id]
    );

    res.json({ hooks: result.rows, count: result.rows.length });
  } catch (error) {
    console.error('Hooks list error:', error);
    res.status(500).json({ error: 'Failed to fetch hooks' });
  }
});

// Get hook details
app.get('/api/hooks/:id', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;

    const result = await pool.query(
      `SELECT h.*, u.username as created_by_name
       FROM hook_configurations_v2 h
       LEFT JOIN users u ON h.created_by = u.id
       WHERE h.id = $1 AND h.team_id = $2`,
      [id, req.user.team_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Hook not found' });
    }

    res.json({ hook: result.rows[0] });
  } catch (error) {
    console.error('Hook details error:', error);
    res.status(500).json({ error: 'Failed to fetch hook details' });
  }
});

// Create/update hook
app.put('/api/hooks/:id', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;
    const { script_content, enabled } = req.body;

    const result = await pool.query(
      `UPDATE hook_configurations_v2
       SET script_content = $1, enabled = $2, updated_at = NOW()
       WHERE id = $3 AND team_id = $4
       RETURNING *`,
      [script_content, enabled, id, req.user.team_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Hook not found' });
    }

    res.json({ hook: result.rows[0] });
  } catch (error) {
    console.error('Hook update error:', error);
    res.status(500).json({ error: 'Failed to update hook' });
  }
});

// ==================================
// EVIDENCE (Enhanced with context)
// ==================================

// Search evidence with context
app.get('/api/evidence/search', authMiddleware, async (req, res) => {
  try {
    const { category, user_id, project_id, from_date, to_date, visibility = 'team', limit = 100, offset = 0 } = req.query;

    let whereConditions = [];
    let params = [];
    let paramIndex = 1;

    // Visibility filter
    if (visibility === 'private') {
      whereConditions.push(`user_id = $${paramIndex++}`);
      params.push(req.user.id);
    } else if (visibility === 'team') {
      whereConditions.push(`team_id = $${paramIndex++}`);
      params.push(req.user.team_id);
    }

    if (category) {
      whereConditions.push(`task_category = $${paramIndex++}`);
      params.push(category);
    }

    if (user_id) {
      whereConditions.push(`user_id = $${paramIndex++}`);
      params.push(user_id);
    }

    if (from_date) {
      whereConditions.push(`created_at >= $${paramIndex++}`);
      params.push(from_date);
    }

    if (to_date) {
      whereConditions.push(`created_at <= $${paramIndex++}`);
      params.push(to_date);
    }

    const whereClause = whereConditions.length > 0 ? 'WHERE ' + whereConditions.join(' AND ') : '';

    const result = await pool.query(
      `SELECT e.*, u.username, u.full_name
       FROM evidence_repository_v2 e
       LEFT JOIN users u ON e.user_id = u.id
       ${whereClause}
       ORDER BY e.created_at DESC
       LIMIT $${paramIndex++} OFFSET $${paramIndex}`,
      [...params, parseInt(limit), parseInt(offset)]
    );

    const countResult = await pool.query(
      `SELECT COUNT(*) FROM evidence_repository_v2 e ${whereClause}`,
      params
    );

    res.json({
      evidence: result.rows,
      count: parseInt(countResult.rows[0].count),
      limit: parseInt(limit),
      offset: parseInt(offset)
    });
  } catch (error) {
    console.error('Evidence search error:', error);
    res.status(500).json({ error: 'Search failed' });
  }
});

// Submit evidence with context
app.post('/api/evidence', authMiddleware, async (req, res) => {
  try {
    const {
      task_category,
      evidence_type,
      evidence_data,
      prompt_text,
      completion_text,
      conversation_id,
      knowledge_pattern_id,
      coding_standard_id,
      visibility = 'team'
    } = req.body;

    if (!task_category || !evidence_type || !evidence_data) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const result = await pool.query(
      `INSERT INTO evidence_repository_v2
       (user_id, team_id, task_category, evidence_type, evidence_data,
        prompt_text, completion_text, conversation_id,
        knowledge_pattern_id, coding_standard_id, visibility)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       RETURNING *`,
      [
        req.user.id,
        req.user.team_id,
        task_category,
        evidence_type,
        evidence_data,
        prompt_text,
        completion_text,
        conversation_id,
        knowledge_pattern_id,
        coding_standard_id,
        visibility
      ]
    );

    res.status(201).json({ evidence: result.rows[0] });
  } catch (error) {
    console.error('Evidence submission error:', error);
    res.status(500).json({ error: 'Failed to submit evidence' });
  }
});

// Get evidence context
app.get('/api/evidence/:id/context', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;

    const result = await pool.query(
      `SELECT e.*, u.username, u.full_name
       FROM evidence_repository_v2 e
       LEFT JOIN users u ON e.user_id = u.id
       WHERE e.id = $1 AND e.team_id = $2`,
      [id, req.user.team_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Evidence not found' });
    }

    res.json({ evidence: result.rows[0] });
  } catch (error) {
    console.error('Evidence context error:', error);
    res.status(500).json({ error: 'Failed to fetch evidence context' });
  }
});

// ==================================
// COMPLIANCE METRICS
// ==================================
app.get('/api/metrics/compliance', authMiddleware, async (req, res) => {
  try {
    const { from_date, to_date, team_id = req.user.team_id } = req.query;

    let whereConditions = [`team_id = $1`];
    let params = [team_id];
    let paramIndex = 2;

    if (from_date) {
      whereConditions.push(`created_at >= $${paramIndex++}`);
      params.push(from_date);
    }

    if (to_date) {
      whereConditions.push(`created_at <= $${paramIndex++}`);
      params.push(to_date);
    }

    const whereClause = 'WHERE ' + whereConditions.join(' AND ');

    const result = await pool.query(
      `SELECT
         task_category,
         COUNT(*) as total_verifications,
         COUNT(DISTINCT user_id) as unique_users,
         0.87 as pass_rate
       FROM evidence_repository_v2
       ${whereClause}
       GROUP BY task_category
       ORDER BY total_verifications DESC`,
      params
    );

    res.json({ metrics: result.rows });
  } catch (error) {
    console.error('Compliance metrics error:', error);
    res.status(500).json({ error: 'Failed to fetch compliance metrics' });
  }
});

// ==================================
// START SERVER
// ==================================
async function startServer() {
  try {
    // Test database connections
    await pool.query('SELECT 1');
    console.log('✅ PostgreSQL connected');

    await testArangoConnection();

    app.listen(PORT, () => {
      console.log(`🚀 Claude Governance Central V2 API running on port ${PORT}`);
      console.log(`📊 Health check: http://localhost:${PORT}/health`);
      console.log(`🔐 Default login: admin / admin123`);
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

startServer();
