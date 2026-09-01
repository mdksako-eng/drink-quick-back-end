// Applies Tier-2 DB hardening (see sql/tier2_lockdown.sql):
//  - full RLS lockdown on companies (payment secrets)
//  - revoke anon writes on business tables (SELECT kept for Realtime)
// Usage: DATABASE_URL=... node scripts/apply_tier2_rls.js
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

async function main() {
  console.log('🔒 Tier-2 lockdown starting...');

  // 1) companies: enable RLS + drop all policies + revoke anon access
  await pool.query('ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY');
  const pols = await pool.query(
    `SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='companies'`
  );
  for (const p of pols.rows) {
    await pool.query(`DROP POLICY IF EXISTS "${p.policyname}" ON public.companies`);
    console.log(`   dropped policy: ${p.policyname}`);
  }
  await pool.query('REVOKE ALL ON public.companies FROM anon');
  await pool.query('REVOKE ALL ON public.companies FROM authenticated');
  console.log('✅ companies: RLS on, all policies dropped, anon revoked');

  // 2) revoke anon writes on business tables (keep SELECT for Realtime)
  const tables = ['drinks', 'orders', 'inventory', 'inventory_transactions', 'settings', 'payment_transactions'];
  for (const t of tables) {
    await pool.query(`REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public."${t}" FROM anon`);
  }
  console.log('✅ anon write access revoked on:', tables.join(', '));

  // verify
  const check = await pool.query(
    `SELECT relname, relrowsecurity FROM pg_class
     WHERE relnamespace='public'::regnamespace
       AND relname IN ('companies','drinks','orders','inventory')`
  );
  for (const r of check.rows) {
    console.log(`   ${r.relname}: RLS=${r.relrowsecurity}`);
  }
}

main()
  .then(() => pool.end())
  .catch((e) => { console.error('❌ FAILED:', e.message); process.exit(1); });
