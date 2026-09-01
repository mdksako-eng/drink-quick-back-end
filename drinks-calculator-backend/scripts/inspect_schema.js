const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
(async () => {
  const r = await pool.query(`SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('companies','settings','payment_transactions','orders','inventory','inventory_transactions','drinks') ORDER BY table_name, ordinal_position`);
  let last = '';
  for (const row of r.rows) {
    if (row.table_name !== last) { console.log('== ' + row.table_name + ' =='); last = row.table_name; }
    console.log('  ' + row.column_name + ' (' + row.data_type + ')');
  }
  const grants = await pool.query(`SELECT table_name, grantee, privilege_type FROM information_schema.role_table_grants WHERE table_schema='public' AND grantee IN ('anon','authenticated','PUBLIC') AND table_name IN ('companies','settings','payment_transactions','orders','inventory','inventory_transactions','drinks') ORDER BY table_name, grantee`);
  console.log('== GRANTS ==');
  let gl = '';
  for (const g of grants.rows) { const k = g.table_name + '/' + g.grantee; if (k !== gl) { process.stdout.write('\\n' + k + ': '); gl = k; } process.stdout.write(g.privilege_type + ' '); }
  console.log();
  await pool.end();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
