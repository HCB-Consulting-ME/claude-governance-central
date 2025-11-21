import pg from 'pg';

const pool = new pg.Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'governance',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD
});

export default pool;
