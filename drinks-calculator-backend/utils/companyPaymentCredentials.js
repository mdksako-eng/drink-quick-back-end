// backend/utils/companyPaymentCredentials.js
// Everything a company needs to collect through CamerPay with its OWN account.
//
// The money-flow rule (see memory-bank/activeContext.md): a bar's customers pay
// the BAR, so credentials are per company and the funds never touch the platform
// account. That is why this module is separate from the platform's own
// CAMERPAY_TOKEN: one bar's token must never be able to charge another bar's
// customer, and a webhook must be verifiable with that bar's OWN secret.
//
// Secrets are write-only from the app's point of view: they are stored through
// utils/credentialVault.js (AES-256-GCM), come back masked, and are only ever
// decrypted to call CamerPay.
const crypto = require('crypto');
const vault = require('./credentialVault');

/**
 * Column names in one place, so the boot migration in server.js and every query
 * cannot drift apart. `*_enc` is deliberate — those values must go through the
 * vault, never into the column as plaintext.
 */
const COLUMNS = {
  enabled: 'campay_enabled',
  token: 'campay_token_enc',
  webhookToken: 'campay_webhook_token',
  webhookSecret: 'campay_webhook_secret_enc',
  connectedAt: 'campay_connected_at',
};

/** Shortest plausible CamerPay token: the docs show `2|` + a long random string. */
const MIN_TOKEN_LENGTH = 20;
const MIN_SECRET_LENGTH = 8;

/**
 * Validate what the owner typed before we store anything.
 * @returns {{ok: boolean, reason: string}}
 */
function validateConnection({ token, webhookSecret } = {}) {
  const value = String(token || '').trim();
  if (!value) return { ok: false, reason: 'token_required' };
  if (value.length < MIN_TOKEN_LENGTH) return { ok: false, reason: 'token_too_short' };
  if (/\s/.test(value)) return { ok: false, reason: 'token_has_whitespace' };
  const secret = String(webhookSecret || '').trim();
  if (secret && secret.length < MIN_SECRET_LENGTH) {
    return { ok: false, reason: 'webhook_secret_too_short' };
  }
  return { ok: true, reason: 'ok' };
}

/**
 * A random, URL-safe token identifying a company in its webhook path. Opaque on
 * purpose: the webhook must never carry a guessable company id.
 */
function newWebhookToken() {
  return crypto.randomBytes(24).toString('base64url');
}

/** Fresh values for the settings endpoint (token and secret encrypted). */
function encryptConnection({ token, webhookSecret }) {
  return {
    tokenEnc: vault.encryptSecret(String(token || '').trim()),
    webhookSecretEnc: webhookSecret ? vault.encryptSecret(String(webhookSecret).trim()) : '',
  };
}

/**
 * The usable client config for a company row, or null when it cannot collect.
 *
 * A row is usable only when it is enabled AND holds a token. A missing webhook
 * secret is tolerated — a bar may connect before creating the secret in its
 * CamerPay dashboard — but then no webhook may be treated as verified.
 *
 * @returns {{token: string, webhookSecret: string, webhookToken: string,
 *   enabled: boolean, companyId: number}|null}
 */
function connectionFor(row, { decrypt = true } = {}) {
  if (!row) return null;
  if (row[COLUMNS.enabled] === false) return null;
  const storedToken = row[COLUMNS.token];
  if (!storedToken) return null;

  let token;
  let webhookSecret = '';
  try {
    token = decrypt ? vault.readSecret(storedToken) : '';
    webhookSecret = row[COLUMNS.webhookSecret]
      ? (decrypt ? vault.readSecret(row[COLUMNS.webhookSecret]) : '')
      : '';
  } catch (error) {
    // A vault key mismatch or a corrupted value must fail closed: a company that
    // cannot be decrypted simply cannot collect, rather than collecting with junk.
    return null;
  }
  if (!token) return null;

  return {
    token,
    webhookSecret,
    webhookToken: row[COLUMNS.webhookToken] || '',
    enabled: true,
    companyId: row.id != null ? row.id : null,
  };
}

/**
 * True when the company is connected and allowed to collect. Deliberately does
 * NOT decrypt (and must not go through connectionFor with decrypt:false, which
 * withholds the token and would therefore always look disconnected).
 */
function isConnected(row) {
  if (!row) return false;
  if (row[COLUMNS.enabled] === false) return false;
  return Boolean(row[COLUMNS.token]);
}

/** Constant-time equality that never throws on a length mismatch. */
function tokensMatch(a, b) {
  const left = Buffer.from(String(a || ''), 'utf8');
  const right = Buffer.from(String(b || ''), 'utf8');
  if (left.length === 0 || left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

/**
 * Find the company a webhook path belongs to.
 * @param {Array<object>} rows candidate company rows
 * @param {string} token the value from the webhook path
 * @returns {object|null}
 */
function findByWebhookToken(rows, token) {
  if (!Array.isArray(rows) || !token) return null;
  const wanted = String(token);
  for (const row of rows) {
    const stored = row && row[COLUMNS.webhookToken];
    if (stored && tokensMatch(stored, wanted)) return row;
  }
  return null;
}

/** Where CamerPay should POST this company's notifications. */
function webhookPath(webhookToken) {
  return `/api/payment/campay-webhook/${webhookToken}`;
}

/**
 * What the app and a manager may see. Never a usable secret — only whether one
 * exists, masked hints, and the URL to paste into the CamerPay dashboard.
 */
function maskedView(row, { baseUrl = '' } = {}) {
  const path = row && row[COLUMNS.webhookToken] ? webhookPath(row[COLUMNS.webhookToken]) : '';
  const base = String(baseUrl || '').replace(/\/+$/, '');
  return {
    connected: isConnected(row),
    enabled: Boolean(row && row[COLUMNS.enabled] !== false && row[COLUMNS.token]),
    vaultReady: vault.isVaultConfigured(),
    tokenMasked: row && row[COLUMNS.token] ? '****' : '',
    webhookSecretSet: Boolean(row && row[COLUMNS.webhookSecret]),
    webhookPath: path || null,
    webhookUrl: path && base ? `${base}${path}` : null,
    connectedAt: (row && row[COLUMNS.connectedAt]) || null,
  };
}

/**
 * Readiness for one company, in the same spirit as GET /subscriptions/campay/health:
 * never claims more than it can prove.
 */
function healthFor(row, { baseUrl = '', accountDeclaredLive = false } = {}) {
  const view = maskedView(row, { baseUrl });
  const reasons = [];
  if (!vault.isVaultConfigured()) reasons.push('vault_key_missing');
  if (!view.enabled) reasons.push('no_token');
  if (!view.webhookSecretSet) reasons.push('no_webhook_secret');
  return {
    ...view,
    accountDeclaredLive: Boolean(accountDeclaredLive),
    // A company can take money only with a token, and its webhook can only be
    // trusted with a secret.
    canCollect: view.enabled,
    canVerifyWebhooks: view.enabled && view.webhookSecretSet,
    blockers: reasons,
  };
}

module.exports = {
  COLUMNS,
  MIN_TOKEN_LENGTH,
  MIN_SECRET_LENGTH,
  validateConnection,
  newWebhookToken,
  encryptConnection,
  connectionFor,
  isConnected,
  tokensMatch,
  findByWebhookToken,
  webhookPath,
  maskedView,
  healthFor,
};

