#!/usr/bin/env node
/**
 * Rollback: disable RLS on the four backend-only tables.
 * Usage: npm run rls:revert   (DATABASE_URL required)
 */
require('dotenv').config();
const { Pool } = require('pg');

(async () => {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('❌ DATABASE_URL is not set.');
    process.exit(1);
  }
  const pool = new Pool({ connectionString: url, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 15000 });
  const tables = ['users', 'user_sessions', 'login_requests', 'approval_logs'];
  for (const t of tables) {
    await pool.query(`ALTER TABLE ${t} DISABLE ROW LEVEL SECURITY`);
    console.log(`   🔓 RLS disabled on ${t}`);
  }
  await pool.end();
  console.log('\n✅ Reverted — sensitive tables are no longer protected by RLS.');
})();