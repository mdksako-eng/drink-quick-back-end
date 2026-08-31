#!/usr/bin/env node
/**
 * Apply the Row-Level-Security SQL to Supabase, then verify it worked.
 *
 * Usage (from drinks-calculator-backend):
 *   DATABASE_URL="postgresql://postgres.xxxx:pass@host:6543/postgres" \
 *     OR put DATABASE_URL in .env
 *   npm run rls:apply
 *
 * It will automatically retry through alternate connection endpoints
 * (secondary pooler port / direct host) in case the primary one is
 * transaction-pooled and rejects DDL.
 */
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const SQL_FILE = path.join(__dirname, 'enable_rls.sql');

function toPool(url) {
  return new Pool({ connectionString: url, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 15000 });
}

function alternateUrls(original) {
  const urls = [original];
  try {
    const u = new URL(original);
    const port = u.port || '5432';
    // Prefer the direct DB endpoint if this looks like the pooler
    const dbHost = u.hostname.replace(/^[^.]*\.pooler\./, 'db.').replace(/\.pooler\.supabase\.com$/, '.supabase.co');
    for (const p of ['5432', '6543']) {
      if (p !== port) {
        const c = new URL(original); c.port = p; urls.push(c.toString());
      }
    }
    if (dbHost !== u.hostname) {
      const c = new URL(original); c.hostname = dbHost; urls.push(c.toString());
    }
  } catch (e) { /* keep original */ }
  return [...new Set(urls)];
}

(async () => {
  const given = process.env.DATABASE_URL;
  if (!given) {
    console.error('❌ DATABASE_URL is not set. Add it to .env or pass it as an env var.');
    process.exit(1);
  }

  const checkOnly = process.argv.includes('--check-only');

  // ---- Connect (with fallback endpoints) ----
  let pool = null;
  let lastErr = null;
  for (const url of alternateUrls(given)) {
    const p = toPool(url);
    try {
      await p.query('SELECT 1');
      console.log(`🔌 Connected via ${new URL(url).host} (port ${new URL(url).port || 5432})`);
      pool = p;
      break;
    } catch (e) {
      lastErr = e;
      await p.end();
    }
  }
  if (!pool) {
    console.error('❌ Could not connect with any endpoint. Last error:', lastErr.message);
    process.exit(1);
  }

  if (!checkOnly) {
    const sql = fs.readFileSync(SQL_FILE, 'utf8');
    const statements = sql
      .split(/;\s*(?:\r?\n|$)/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0 && !s.startsWith('--'));

    let applied = 0;
    const failed = [];
    for (const stmt of statements) {
      try {
        await pool.query(stmt);
        applied += 1;
        console.log(`   ✅ ${stmt.split('\n')[0].slice(0, 80)}...`);
      } catch (e) {
        failed.push({ stmt: stmt.split('\n')[0].slice(0, 80), error: e.message });
      }
    }
    console.log(`\n📊 Statements applied: ${applied}, failed: ${failed.length}`);
    failed.forEach((f) => console.log(`   ⚠️  SKIPPED "${f.stmt}" → ${f.error}`));
  } else {
    console.log('🔎 --check-only mode: only verifying current RLS state');
  }

  // ---- Verify RLS state ----
  const verify = await pool.query(
    `SELECT relname AS table_name, relrowsecurity AS rls_enabled
     FROM pg_class
     WHERE relname IN ('users','user_sessions','login_requests','approval_logs')
     ORDER BY relname`
  );
  verify.rows.forEach((r) => {
    console.log(`   - ${r.table_name}: RLS ${r.rls_enabled ? '✅ ENABLED' : '❌ NOT ENABLED'}`);
  });

  await pool.end();
  const ok = verify.rows.length === 4 && verify.rows.every((r) => r.rls_enabled);
  process.exit(ok ? 0 : 1);
})();