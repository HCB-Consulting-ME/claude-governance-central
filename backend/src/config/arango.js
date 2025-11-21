import { Database } from 'arangojs';

// Connect to existing ArangoDB instance (flowmaster database)
const arangoConfig = {
  url: process.env.ARANGO_URL || 'http://localhost:8529',
  databaseName: process.env.ARANGO_DATABASE || 'flowmaster',
  auth: {
    username: process.env.ARANGO_USER || 'root',
    password: process.env.ARANGO_PASSWORD || 'flowmaster25!'
  }
};

const db = new Database({
  url: arangoConfig.url,
  databaseName: arangoConfig.databaseName,
  auth: arangoConfig.auth
});

// Test connection
export async function testArangoConnection() {
  try {
    const info = await db.get();
    console.log(`✅ Connected to ArangoDB: ${info.name} (${info.version})`);
    return true;
  } catch (error) {
    console.error('❌ ArangoDB connection failed:', error.message);
    throw error;
  }
}

// Helper: Get collection
export function getCollection(name) {
  return db.collection(name);
}

// Helper: Execute AQL query
export async function query(aql, bindVars = {}) {
  const cursor = await db.query(aql, bindVars);
  return await cursor.all();
}

// Helper: Get graph
export function getGraph(name) {
  return db.graph(name);
}

export default db;
