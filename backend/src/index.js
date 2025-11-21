import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import pg from 'pg';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 8300;

// Database connection
const pool = new pg.Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'governance',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD
});

// Test database connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('❌ Database connection failed:', err.message);
    throw new Error('Database connection required. Cannot start without database.');
  }
  console.log('✅ Database connected:', res.rows[0].now);
});

// Middleware
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'claude-governance-api',
    timestamp: new Date().toISOString(),
    database: 'connected'
  });
});

// ============================================================================
// HOOK CONFIGURATION API
// ============================================================================

// Get all hook configurations
app.get('/api/hooks/config', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT id, name, category, enabled, config, updated_at
      FROM hook_configurations
      ORDER BY category, name
    `);
    res.json({ hooks: result.rows });
  } catch (error) {
    console.error('Error fetching hook configs:', error);
    res.status(500).json({ error: 'Database query failed' });
  }
});

// Update hook configuration
app.put('/api/hooks/config/:id', async (req, res) => {
  const { id } = req.params;
  const { enabled, config } = req.body;

  if (typeof enabled !== 'boolean' || !config) {
    return res.status(400).json({ error: 'Missing required fields: enabled, config' });
  }

  try {
    const result = await pool.query(`
      UPDATE hook_configurations
      SET enabled = $1, config = $2, updated_at = NOW()
      WHERE id = $3
      RETURNING *
    `, [enabled, config, id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Hook configuration not found' });
    }

    res.json({ hook: result.rows[0] });
  } catch (error) {
    console.error('Error updating hook config:', error);
    res.status(500).json({ error: 'Database update failed' });
  }
});

// ============================================================================
// EVIDENCE REPOSITORY API
// ============================================================================

// Submit evidence
app.post('/api/evidence', async (req, res) => {
  const {
    task_id,
    task_category,
    evidence_type,
    evidence_data,
    user_id,
    project_id
  } = req.body;

  if (!task_category || !evidence_type || !evidence_data) {
    return res.status(400).json({
      error: 'Missing required fields: task_category, evidence_type, evidence_data'
    });
  }

  try {
    const result = await pool.query(`
      INSERT INTO evidence_repository
        (task_id, task_category, evidence_type, evidence_data, user_id, project_id, created_at)
      VALUES ($1, $2, $3, $4, $5, $6, NOW())
      RETURNING *
    `, [task_id, task_category, evidence_type, evidence_data, user_id, project_id]);

    res.status(201).json({ evidence: result.rows[0] });
  } catch (error) {
    console.error('Error storing evidence:', error);
    res.status(500).json({ error: 'Failed to store evidence' });
  }
});

// Get evidence by task
app.get('/api/evidence/task/:taskId', async (req, res) => {
  const { taskId } = req.params;

  try {
    const result = await pool.query(`
      SELECT * FROM evidence_repository
      WHERE task_id = $1
      ORDER BY created_at DESC
    `, [taskId]);

    res.json({ evidence: result.rows });
  } catch (error) {
    console.error('Error fetching evidence:', error);
    res.status(500).json({ error: 'Database query failed' });
  }
});

// Search evidence
app.get('/api/evidence/search', async (req, res) => {
  const { category, type, project_id, from_date, to_date } = req.query;

  let query = 'SELECT * FROM evidence_repository WHERE 1=1';
  const params = [];
  let paramCount = 1;

  if (category) {
    query += ` AND task_category = $${paramCount++}`;
    params.push(category);
  }

  if (type) {
    query += ` AND evidence_type = $${paramCount++}`;
    params.push(type);
  }

  if (project_id) {
    query += ` AND project_id = $${paramCount++}`;
    params.push(project_id);
  }

  if (from_date) {
    query += ` AND created_at >= $${paramCount++}`;
    params.push(from_date);
  }

  if (to_date) {
    query += ` AND created_at <= $${paramCount++}`;
    params.push(to_date);
  }

  query += ' ORDER BY created_at DESC LIMIT 100';

  try {
    const result = await pool.query(query, params);
    res.json({ evidence: result.rows, count: result.rows.length });
  } catch (error) {
    console.error('Error searching evidence:', error);
    res.status(500).json({ error: 'Database query failed' });
  }
});

// ============================================================================
// VERIFICATION RULES API
// ============================================================================

// Get verification rules by category
app.get('/api/rules/:category', async (req, res) => {
  const { category } = req.params;

  try {
    const result = await pool.query(`
      SELECT * FROM verification_rules
      WHERE category = $1 AND enabled = true
      ORDER BY priority DESC
    `, [category]);

    res.json({ rules: result.rows });
  } catch (error) {
    console.error('Error fetching rules:', error);
    res.status(500).json({ error: 'Database query failed' });
  }
});

// Update verification rule
app.put('/api/rules/:id', async (req, res) => {
  const { id } = req.params;
  const { enabled, rule_config } = req.body;

  try {
    const result = await pool.query(`
      UPDATE verification_rules
      SET enabled = $1, rule_config = $2, updated_at = NOW()
      WHERE id = $3
      RETURNING *
    `, [enabled, rule_config, id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Rule not found' });
    }

    res.json({ rule: result.rows[0] });
  } catch (error) {
    console.error('Error updating rule:', error);
    res.status(500).json({ error: 'Database update failed' });
  }
});

// ============================================================================
// KNOWLEDGE REPOSITORY API
// ============================================================================

// Store knowledge entry
app.post('/api/knowledge', async (req, res) => {
  const { title, content, category, tags, author_id } = req.body;

  if (!title || !content || !category) {
    return res.status(400).json({
      error: 'Missing required fields: title, content, category'
    });
  }

  try {
    const result = await pool.query(`
      INSERT INTO knowledge_repository
        (title, content, category, tags, author_id, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
      RETURNING *
    `, [title, content, category, tags, author_id]);

    res.status(201).json({ knowledge: result.rows[0] });
  } catch (error) {
    console.error('Error storing knowledge:', error);
    res.status(500).json({ error: 'Failed to store knowledge' });
  }
});

// Search knowledge repository
app.get('/api/knowledge/search', async (req, res) => {
  const { q, category, tags } = req.query;

  let query = 'SELECT * FROM knowledge_repository WHERE 1=1';
  const params = [];
  let paramCount = 1;

  if (q) {
    query += ` AND (title ILIKE $${paramCount} OR content ILIKE $${paramCount})`;
    params.push(`%${q}%`);
    paramCount++;
  }

  if (category) {
    query += ` AND category = $${paramCount++}`;
    params.push(category);
  }

  if (tags) {
    query += ` AND tags @> $${paramCount++}`;
    params.push(JSON.parse(tags));
  }

  query += ' ORDER BY updated_at DESC LIMIT 50';

  try {
    const result = await pool.query(query, params);
    res.json({ knowledge: result.rows, count: result.rows.length });
  } catch (error) {
    console.error('Error searching knowledge:', error);
    res.status(500).json({ error: 'Database query failed' });
  }
});

// ============================================================================
// COMPLIANCE METRICS API
// ============================================================================

// Get compliance dashboard
app.get('/api/metrics/compliance', async (req, res) => {
  const { project_id, from_date, to_date } = req.query;

  try {
    // Get verification stats by category
    let query = `
      SELECT
        task_category,
        COUNT(*) as total_verifications,
        COUNT(DISTINCT user_id) as unique_users,
        AVG(CASE WHEN evidence_type = 'passed' THEN 1 ELSE 0 END) as pass_rate
      FROM evidence_repository
      WHERE 1=1
    `;
    const params = [];
    let paramCount = 1;

    if (project_id) {
      query += ` AND project_id = $${paramCount++}`;
      params.push(project_id);
    }

    if (from_date) {
      query += ` AND created_at >= $${paramCount++}`;
      params.push(from_date);
    }

    if (to_date) {
      query += ` AND created_at <= $${paramCount++}`;
      params.push(to_date);
    }

    query += ' GROUP BY task_category ORDER BY total_verifications DESC';

    const result = await pool.query(query, params);
    res.json({ metrics: result.rows });
  } catch (error) {
    console.error('Error fetching metrics:', error);
    res.status(500).json({ error: 'Database query failed' });
  }
});

// ============================================================================
// ERROR HANDLING
// ============================================================================

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Claude Governance API listening on port ${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`📚 API endpoints:`);
  console.log(`   - GET  /api/hooks/config`);
  console.log(`   - POST /api/evidence`);
  console.log(`   - GET  /api/evidence/search`);
  console.log(`   - GET  /api/knowledge/search`);
  console.log(`   - GET  /api/metrics/compliance`);
});
