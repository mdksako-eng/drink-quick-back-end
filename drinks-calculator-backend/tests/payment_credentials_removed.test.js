/**
 * The per-provider payment credential columns are gone - no database required.
 *
 * MTN/Orange credentials used to live per company in plaintext columns. CamerPay
 * is the only rail now, so the columns are dropped
 * (sql/drop_dead_payment_columns.sql). This guard fails if a column name comes
 * back into the code: a SELECT of a dropped column would break
 * GET /payment/company-settings at runtime, and a write would put a provider
 * secret back into the database.
 *
 * Deliberately NOT flagged:
 *   - the SQL scripts, which name the columns in order to drop them;
 *   - subscriptions.js / utils/momo.js / utils/orange_money.js, where the same
 *     names are OBJECT KEYS built from PLATFORM_* env vars for the platform's own
 *     direct-operator fallback - not database columns.
 *
 * Run with: npm test
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

/** Every column the drop script removes. */
const DROPPED_COLUMNS = [
  'mtn_api_key', 'mtn_api_key_encrypted', 'mtn_secret_key', 'mtn_secret_key_encrypted',
  'mtn_merchant_id', 'mtn_merchant_phone', 'mtn_sandbox_mode',
  'orange_api_key', 'orange_api_key_encrypted', 'orange_secret_key',
  'orange_secret_key_encrypted', 'orange_merchant_id', 'orange_merchant_phone',
  'orange_sandbox_mode',
];

/** The same fields as the API/app spell them. */
const DROPPED_FIELDS = [
  'mtnApiKey', 'mtnSecretKey', 'mtnMerchantId', 'mtnMerchantPhone', 'mtnSandboxMode',
  'orangeApiKey', 'orangeSecretKey', 'orangeMerchantId', 'orangeMerchantPhone',
  'orangeSandboxMode',
];

/** Files that talk to the database directly. */
const DB_FILES = ['server.js', 'routes/payment.routes.js', 'routes/data.routes.js'];

/** Files that used to carry the plumbing. */
const APP_FILES = [
  '../lib/screens/storage_settings_screen.dart',
  '../lib/utils/payment_helper.dart',
];

describe('the dropped payment-credential columns are unreferenced', () => {
  test.each(DB_FILES)('%s names none of them', (file) => {
    const text = read(file);
    const found = DROPPED_COLUMNS.filter((col) => text.includes(col));
    expect(found).toEqual([]);
  });

  test('the app neither reads nor sends the credential fields', () => {
    const found = [];
    for (const rel of APP_FILES) {
      const text = fs.readFileSync(path.join(root, rel), 'utf8');
      for (const field of DROPPED_FIELDS) {
        if (text.includes(field)) found.push(`${rel}: ${field}`);
      }
    }
    expect(found).toEqual([]);
  });

  test('the four switches survive - they are the columns that are kept', () => {
    const text = read('routes/payment.routes.js');
    expect(text).toContain('mtn_enabled');
    expect(text).toContain('orange_enabled');
    expect(text).toContain('card_enabled');
    expect(text).toContain('business_payments_enabled');
  });

  test('the drop script still drops exactly these columns', () => {
    const sql = read('sql/drop_dead_payment_columns.sql');
    for (const col of DROPPED_COLUMNS) {
      expect(sql).toContain(`drop column if exists ${col}`);
    }
  });

  test('a company row cannot carry a CamerPay secret to the app', () => {
    // stripSecrets() must cover the columns that DO hold secrets now - one route
    // returns `SELECT *` for a company.
    const text = read('routes/data.routes.js');
    expect(text).toContain('campay_token_enc');
    expect(text).toContain('campay_webhook_secret_enc');
    expect(text).toContain('campay_webhook_token');
  });
});
