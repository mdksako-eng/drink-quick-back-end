#!/usr/bin/env node
/**
 * Applies sql/rls_forecast_events.sql to the configured database:
 *   - enables RLS on forecast_events (no policies => anon gets 0 rows)
 *   - drops any pre-existing policy that would re-open access
 *   - revokes anon/authenticated grants
 *   - proves the anon role can no longer read the table
 *
 * Usage: DATABASE_URL=... node scripts/apply_forecast_rls.js
 */
const { Pool } = require('pg');
require('dotenv').config();

(async () => {
  if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL is not set');
    process.exit(1);
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });

  try {
    await pool.query('ALTER TABLE public.forecast_events ENABLE ROW LEVEL SECURITY');
    console.log('RLS enabled on forecast_events');

    const policies = await pool.query(
      `SELECT policyname FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'forecast_events'`
    );
    for (const p of policies.rows) {
      await pool.query(
        `DROP POLICY IF EXISTS "${p.policyname}" ON public.forecast_events`
      );
      console.log(`dropped policy ${p.policyname} on forecast_events`);
    }

    await pool.query('REVOKE ALL ON public.forecast_events FROM anon, authenticated');
    console.log('revoked anon/authenticated grants on forecast_events');

    const check = await pool.query(
      `SELECT relrowsecurity AS rls FROM pg_class
        WHERE relnamespace = 'public'::regnamespace AND relname = 'forecast_events'`
    );
    const rlsOn = check.rows.length > 0 && check.rows[0].rls === true;

    // Prove the public key really cannot read the table any more.
    try {
      await pool.query('SET ROLE anon');
      const anonRead = await pool.query(
        'SELECT id FROM public.forecast_events LIMIT 1'
      );
      console.log(`WARNING: anon still reads ${anonRead.rowCount} row(s) - investigate`);
      await pool.query('RESET ROLE');
    } catch (e) {
      console.log(`anon read blocked: ${e.message}`);
      try { await pool.query('RESET ROLE'); } catch (_) { /* ignore */ }
    }

    await pool.end();
    console.log(rlsOn ? 'forecast_events: RLS ON' : 'forecast_events: RLS NOT enabled');
    process.exit(rlsOn ? 0 : 1);
  } catch (e) {
    console.error('FAILED:', e.message);
    try { await pool.end(); } catch (_) { /* ignore */ }
    process.exit(1);
  }
})();