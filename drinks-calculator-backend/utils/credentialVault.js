// backend/utils/credentialVault.js
// Encrypt-at-rest for per-company payment credentials — a bar's CamerPay token
// and webhook secret, and the legacy MoMo keys when they are migrated.
//
// Why it exists: companies.* payment secrets have been plain TEXT columns. A
// database dump, a leaked backup or one careless SELECT then hands out a token
// that can move that bar's money. Option B (each bar connects its own account)
// makes every bar's credential a distinct asset worth protecting.
//
// AES-256-GCM is authenticated: a tampered ciphertext fails to decrypt instead of
// quietly returning a wrong token. Stored format, base64url:
//     v1.<iv>.<authTag>.<ciphertext>
//
// Fails CLOSED. No key → encryption throws, and a value that was never encrypted
// is never silently treated as ciphertext (use readSecret() for legacy columns).
const crypto = require('crypto');

const PREFIX = 'v1';
const KEY_ENV = 'PAYMENT_CREDENTIALS_KEY';
const IV_BYTES = 12;
const TAG_BYTES = 16;

/** True when a vault key is configured, so writers know they can store secrets. */
function isVaultConfigured() {
  return Boolean(String((process.env && process.env[KEY_ENV]) || '').trim());
}

/**
 * Resolve the 32-byte key. Accepted forms, in order:
 *   - 64 hex characters
 *   - base64 that decodes to exactly 32 bytes
 *   - any other string, hashed with SHA-256 (so a passphrase still works)
 * @returns {Buffer} 32 bytes
 */
function loadKey(keyOverride) {
  const raw = String(keyOverride || (process.env && process.env[KEY_ENV]) || '').trim();
  if (!raw) {
    throw new Error(`${KEY_ENV} is not set — refusing to handle payment credentials`);
  }
  if (/^[0-9a-fA-F]{64}$/.test(raw)) return Buffer.from(raw, 'hex');
  const b64 = Buffer.from(raw, 'base64');
  if (b64.length === 32 && raw.replace(/[^A-Za-z0-9+/=_-]/g, '').length === raw.length) {
    return b64;
  }
  return crypto.createHash('sha256').update(raw, 'utf8').digest();
}

function toBase64Url(buffer) {
  return Buffer.from(buffer).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64Url(value) {
  const padded = String(value).replace(/-/g, '+').replace(/_/g, '/');
  return Buffer.from(padded, 'base64');
}

/** Is this stored value a vault ciphertext (as opposed to a legacy plaintext)? */
function isEncrypted(value) {
  return typeof value === 'string' && value.startsWith(`${PREFIX}.`);
}

/**
 * Encrypt a secret for storage. An empty secret stays empty, so clearing a
 * credential in settings does not encrypt a placeholder.
 * @returns {string} `v1.<iv>.<tag>.<ct>` or ''
 */
function encryptSecret(plain, keyOverride) {
  if (plain == null || plain === '') return '';
  const key = loadKey(keyOverride);
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(String(plain), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [PREFIX, toBase64Url(iv), toBase64Url(tag), toBase64Url(ciphertext)].join('.');
}

/**
 * Decrypt a stored secret. STRICT: a value without the `v1.` prefix is refused,
 * because treating a legacy plaintext as ciphertext would hide a migration bug.
 * @throws {Error} when the value is not vault ciphertext, tampered, or the key is wrong
 */
function decryptSecret(stored, keyOverride) {
  if (stored == null || stored === '') return '';
  if (!isEncrypted(stored)) {
    throw new Error('Not a vault ciphertext (expected a v1.<iv>.<tag>.<ct> value)');
  }
  const [, ivPart, tagPart, ctPart] = String(stored).split('.');
  if (!ivPart || !tagPart || !ctPart) throw new Error('Malformed vault ciphertext');
  const key = loadKey(keyOverride);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, fromBase64Url(ivPart));
  decipher.setAuthTag(fromBase64Url(tagPart));
  return Buffer.concat([
    decipher.update(fromBase64Url(ctPart)),
    decipher.final(),
  ]).toString('utf8');
}

/**
 * Tolerant read for a column that may still hold a legacy plaintext value.
 * Ciphertext is decrypted; anything else is returned untouched.
 */
function readSecret(stored, keyOverride) {
  if (stored == null || stored === '') return '';
  return isEncrypted(stored) ? decryptSecret(stored, keyOverride) : String(stored);
}

/**
 * Display form for the app: never returns a usable secret, only a hint that one
 * exists. Mirrors the masked-credentials pattern already used by
 * GET /payment/settings, so no code path can leak a token to the client.
 */
function maskSecret(value) {
  if (value == null || value === '') return '';
  const text = String(value);
  const tail = text.slice(-4);
  return text.length <= 4 ? '****' : `****${tail}`;
}

/**
 * Short, non-reversible fingerprint of a secret — enough to answer "did this
 * credential change?" in an audit trail without storing or logging the secret.
 */
function fingerprint(plain) {
  if (plain == null || plain === '') return '';
  return crypto.createHash('sha256').update(String(plain), 'utf8').digest('hex').slice(0, 12);
}

module.exports = {
  PREFIX,
  KEY_ENV,
  isVaultConfigured,
  loadKey,
  isEncrypted,
  encryptSecret,
  decryptSecret,
  readSecret,
  maskSecret,
  fingerprint,
};
