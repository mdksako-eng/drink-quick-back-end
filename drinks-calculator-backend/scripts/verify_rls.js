#!/usr/bin/env node
/**
 * Diagnose why the anon key can still read `users` even though RLS is enabled.
 * Usage: DATABASE_URL=... node scripts/verify_rls.js
 */
require('dotenv').config();
const { Pool } = require('pg');

(async () => {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });

  // 1) RLS state per table (from pg_class)
  const t = await pool.query(
    `SELECT n.nspname AS schemaname, c.relname, c.relrowsecurity AS rls, c.relforcerowsecurity AS force
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname IN ('public','auth') AND c.relname IN ('users','user_sessions','login_requests','approval_logs')
      ORDER BY 2, 1`
  );
  console.log('— tables RLS state —');
  t.rows.forEach((r) => console.log(`  ${r.schemaname}.${r.relname}: rls=${r.rls} force=${r.force}`));

  // 2) Row-level security policies
  const pol = await pool.query(
    `SELECT tablename, policyname, roles::text AS roles, cmd
       FROM pg_policies
      WHERE schemaname = 'public' AND tablename IN ('users','user_sessions','login_requests','approval_logs')`
  );
  console.log('— policies on the 4 tables —');
  if (pol.rowCount === 0) console.log('  (none)');
  pol.rows.forEach((r) => console.log(`  ${r.tablename} / ${r.policyname} roles=${r.roles} cmd=${r.cmd}`));

  // 3) Do anon / authenticated roles bypass RLS?
  const roles = await pool.query(
    `SELECT rolname, rolsuper, rolbypassrls FROM pg_roles WHERE rolname IN ('anon','authenticated','authenticator','service_role','postgres')`
  );
  console.log('— roles (superuser / bypassrls) —');
  roles.rows.forEach((r) => console.log(`  ${r.rolname}: super=${r.rolsuper} bypassrls=${r.rolbypassrls}`));

  // 4) Simulate PostgREST: SET ROLE anon then SELECT
  for (const rol of ['anon', 'authenticated']) {
    try {
      await pool.query('SET ROLE ' + rol);
      const q = await pool.query('SELECT id, username, password FROM users LIMIT 3');
      console.log(`— as ${rol}: SELECT users → ${q.rowCount} rows`);
      await pool.query('RESET ROLE');
    } catch (e) {
      console.log(`— as ${rol}: ERROR ${e.message}`);
      try { await pool.query('RESET ROLE'); } catch (_) {}
    }
  }

  await pool.end();
})().catch((e) => { console.error(e.message); process.exit(1); });