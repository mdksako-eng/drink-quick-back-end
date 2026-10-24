// scripts/set_company_plan.js
//
// Sets a company's subscription plan from the terminal — the tool for comping an
// account (a partner, a school, a test company) without hand-typing SQL.
//
// Usage:
//   node scripts/set_company_plan.js "Banga school Gold" pro
//   node scripts/set_company_plan.js "Banga school Gold" pro --expires=2027-01-01
//   node scripts/set_company_plan.js "Banga school Gold" pro --dry-run
//
// Safety rails, on purpose:
//   • the name must match EXACTLY ONE company — "0 matches" or "3 matches" stops
//     the script instead of guessing;
//   • --dry-run prints the SQL and touches nothing;
//   • every real change is written to the audit log (`company.plan`).
//
// Credentials come from the backend `.env` (DATABASE_URL). Nothing is hardcoded.

require('dotenv').config();

const { Pool } = require('pg');
const auditLog = require('../utils/auditLog');

const VALID_PLANS = ['free', 'starter', 'pro'];

function parseArgs(argv) {
  const positional = argv.filter((a) => !a.startsWith('--'));
  const flags = argv.filter((a) => a.startsWith('--'));
  const name = positional[0];
  const plan = (positional[1] || '').toLowerCase();
  const dryRun = flags.includes('--dry-run');
  const expiresFlag = flags.find((f) => f.startsWith('--expires='));
  const expiresAt = expiresFlag ? expiresFlag.split('=')[1] : null;
  return { name, plan, dryRun, expiresAt };
}

function usage() {
  console.log('Usage: node scripts/set_company_plan.js "<company name>" <free|starter|pro> [--expires=YYYY-MM-DD] [--dry-run]');
}

(async () => {
  const { name, plan, dryRun, expiresAt } = parseArgs(process.argv.slice(2));

  if (!name || !plan) {
    usage();
    process.exit(1);
  }
  if (!VALID_PLANS.includes(plan)) {
    console.error(`❌ Unknown plan "${plan}". Valid: ${VALID_PLANS.join(', ')}`);
    process.exit(1);
  }
  if (expiresAt && Number.isNaN(Date.parse(expiresAt))) {
    console.error(`❌ --expires must be a date (YYYY-MM-DD), got "${expiresAt}"`);
    process.exit(1);
  }
  if (!process.env.DATABASE_URL) {
    console.error('❌ DATABASE_URL is not set. Run this from drinks-calculator-backend/ with its .env present.');
    process.exit(1);
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });

  try {
    // Exact, case-insensitive match — never a LIKE, so "Banga" cannot hit three rows.
    const found = await pool.query(
      'SELECT id, name, plan, subscription_status, plan_expires_at FROM companies WHERE LOWER(TRIM(name)) = LOWER(TRIM($1)) ORDER BY id',
      [name]
    );

    if (found.rows.length === 0) {
      console.error(`❌ No company named "${name}".`);
      const near = await pool.query(
        'SELECT id, name, plan FROM companies WHERE LOWER(name) LIKE LOWER($1) ORDER BY id LIMIT 10',
        [`%${name}%`]
      );
      if (near.rows.length) {
        console.log('   Did you mean one of these?');
        for (const r of near.rows) console.log(`   #${r.id}  ${r.name}  (plan: ${r.plan})`);
      }
      process.exit(1);
    }
    if (found.rows.length > 1) {
      console.error(`❌ "${name}" matches ${found.rows.length} companies. Use the full exact name:`);
      for (const r of found.rows) console.log(`   #${r.id}  ${r.name}  (plan: ${r.plan})`);
      process.exit(1);
    }

    const company = found.rows[0];
    const status = plan === 'free' ? 'expired' : 'active';
    const expiry = plan === 'free' ? null : (expiresAt || null);

    console.log(`Company #${company.id} "${company.name}"`);
    console.log(`   before: plan=${company.plan} status=${company.subscription_status} expires=${company.plan_expires_at || 'never'}`);
    console.log(`   after:  plan=${plan} status=${status} expires=${expiry || 'never'}`);

    if (dryRun) {
      console.log('\n🟡 --dry-run: nothing was written.');
      return;
    }

    await pool.query(
      `UPDATE companies
          SET plan = $1, subscription_status = $2, plan_expires_at = $3
        WHERE id = $4`,
      [plan, status, expiry, company.id]
    );

    await auditLog.record(pool, {
      companyId: company.id,
      actorId: null,
      actorName: 'scripts/set_company_plan.js',
      action: 'company.plan',
      target: `company:${company.id}`,
      detail: `${company.plan} -> ${plan} (status ${status}, expires ${expiry || 'never'})`,
    });

    console.log('\n✅ Done. The app picks the new plan up on the next plan refresh (login or opening the subscription screen).');
  } finally {
    await pool.end();
  }
})().catch((e) => {
  console.error('ERR', e.message);
  process.exit(1);
});
