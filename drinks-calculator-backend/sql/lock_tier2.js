// Applies the Tier-2 lockdown: enables RLS (no policies) + revokes client
// grants on the business-data tables. Backend (postgres role) bypasses RLS.
const { Pool } = require('pg');
require('dotenv').config();

const TABLES = ['companies', 'drinks', 'orders', 'inventory',
  'inventory_transactions', 'settings', 'payment_transactions'];

(async () => {
  if (!process.env.DATABASE_URL) {
    console.error('❌ DATABASE_URL is not set');
    process.exit(1);
  }
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });

  for (const t of TABLES) {
    await pool.query(`ALTER TABLE public.${t} ENABLE ROW LEVEL SECURITY`);
    console.log(`🔒 RLS enabled on ${t}`);
  }

  const policies = await pool.query(
    `SELECT tablename, policyname FROM pg_policies
     WHERE schemaname = 'public' AND tablename = ANY($1)`,
    [TABLES]
  );
  for (const p of policies.rows) {
    await pool.query(`DROP POLICY IF EXISTS "${p.policyname}" ON public.${p.tablename}`);
    console.log(`🗑️  Dropped policy ${p.policyname} on ${p.tablename}`);
  }

  await pool.query(`REVOKE ALL ON public.${TABLES.join(', public.')} FROM anon, authenticated`);
  console.log('🚫 Revoked anon/authenticated grants');

  const check = await pool.query(
    `SELECT tablename, rowsecurity FROM pg_tables
     WHERE schemaname = 'public' AND tablename = ANY($1) ORDER BY tablename`,
    [TABLES]
  );
  let allOk = true;
  for (const r of check.rows) {
    console.log(`${r.rowsecurity ? '✅' : '❌'} ${r.tablename}: RLS ${r.rowsecurity ? 'ON' : 'OFF'}`);
    if (!r.rowsecurity) allOk = false;
  }
  await pool.end();
  console.log(allOk ? '🎉 Tier-2 lockdown applied successfully' : '⚠️ Some tables are not locked — investigate');
  process.exit(allOk ? 0 : 1);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
