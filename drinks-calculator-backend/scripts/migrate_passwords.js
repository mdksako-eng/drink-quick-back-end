#!/usr/bin/env node
/**
 * One-time migration: hash all plaintext passwords in the users table.
 *
 * Usage:
 *   cd drinks-calculator-backend
 *   npm run migrate:passwords
 *
 * (Requires DATABASE_URL to be set in .env or the environment.)
 * Already-hashed rows (starting with $2a$ / $2b$ / $2y$) are skipped.
 */
require('dotenv').config();
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');

const SALT_ROUNDS = 10;

(async () => {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('❌ DATABASE_URL is not set. Add it to .env or pass it in the environment.');
    process.exit(1);
  }

  const pool = new Pool({ connectionString: url, ssl: { rejectUnauthorized: false } });

  try {
    const { rows } = await pool.query('SELECT id, username, password FROM users');

    const toMigrate = rows.filter(
      (r) => !r.password || !r.password.startsWith('$2')
    );

    console.log(`👥 Total users:        ${rows.length}`);
    console.log(`🔒 Already hashed:     ${rows.length - toMigrate.length}`);
    console.log(`⚠️  Plaintext to hash:   ${toMigrate.length}`);

    if (toMigrate.length === 0) {
      console.log('✅ Nothing to do — all passwords are already bcrypt hashes.');
      return;
    }

    for (const user of toMigrate) {
      const hash = await bcrypt.hash(user.password, SALT_ROUNDS);
      await pool.query('UPDATE users SET password = $1 WHERE id = $2', [hash, user.id]);
      console.log(`   ✅ Hashed password for user #${user.id} (${user.username})`);
    }

    console.log(`\n🎉 Done — ${toMigrate.length} password(s) migrated to bcrypt.`);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();