// utils/orderQuote.js
// A price the SERVER vouched for.
//
// The hole this closes: `/payment/campay-initiate` only checks `amount > 0`, so a
// buggy or modified till could ask the provider to collect 500 for a 5 000 XAF
// order and the books would believe the sale was paid. Instead of restructuring
// the till around pending orders (which would need an `orders.status` migration,
// stock changes and Z-report surgery), the till asks for a quote, and the quote is
// signed with a server secret: the payment route then refuses any amount that is
// not exactly the amount the server priced.
//
// Properties that matter:
//  - stateless (no table, no row to clean up, nothing to leak);
//  - short lived (`ttlMs`, 5 min by default) so a stale cart cannot be paid later;
//  - bound to the company, so company A's quote cannot price company B's sale;
//  - constant-time signature comparison.
const crypto = require('crypto');

const DEFAULT_TTL_MS = 5 * 60 * 1000;

/** The signing secret, or null when the feature is not configured. */
function quoteSecret(env = process.env) {
  const secret = (env.ORDER_QUOTE_SECRET || '').trim();
  return secret.length >= 16 ? secret : null;
}

/** Whether a payment MUST carry a quote (rollout switch, off by default). */
function quoteRequired(env = process.env) {
  return String(env.PAYMENT_QUOTE_REQUIRED || '').toLowerCase() === 'true';
}

function sign(body, secret) {
  return crypto.createHmac('sha256', secret).update(body).digest('base64url');
}

/**
 * Sign a priced cart.
 * @returns {{token: string, expiresAt: number}|null} null when no secret is set
 */
function signQuote(
  { companyId, total, unitCount = 0, ttlMs = DEFAULT_TTL_MS, now = Date.now() },
  secret
) {
  if (!secret) return null;
  const payload = {
    c: String(companyId),
    t: Number(total),
    u: Number(unitCount),
    e: now + ttlMs,
  };
  const body = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  return { token: `${body}.${sign(body, secret)}`, expiresAt: payload.e };
}

/**
 * Check a quote against the payment being started.
 * @returns {{ok: boolean, reason?: string}} never throws
 */
function verifyQuote(token, { companyId, amount, secret, now = Date.now() }) {
  if (!secret) return { ok: false, reason: 'not_configured' };
  if (typeof token !== 'string') return { ok: false, reason: 'missing' };
  const parts = token.split('.');
  if (parts.length !== 2 || !parts[0] || !parts[1]) return { ok: false, reason: 'malformed' };

  const [body, signature] = parts;
  const expected = sign(body, secret);
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { ok: false, reason: 'bad_signature' };
  }

  let payload;
  try {
    payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch {
    return { ok: false, reason: 'malformed' };
  }

  if (String(payload.c) !== String(companyId)) return { ok: false, reason: 'wrong_company' };
  if (!Number.isFinite(Number(payload.e)) || Number(payload.e) < now) {
    return { ok: false, reason: 'expired' };
  }
  if (Math.round(Number(payload.t)) !== Math.round(Number(amount))) {
    return { ok: false, reason: 'amount_mismatch' };
  }
  return { ok: true };
}

/**
 * Decide whether this payment may proceed.
 *
 * - no secret configured      → allowed (feature not enabled; old behaviour)
 * - token supplied            → must verify, whatever the rollout switch says
 * - no token, not required     → allowed (older app build in the field)
 * - no token, required         → refused
 *
 * @returns {{ok: boolean, code?: string}}
 */
function checkQuote({ token, companyId, amount, secret, required, now }) {
  if (!secret) return { ok: true };
  if (!token) return required ? { ok: false, code: 'quote_required' } : { ok: true };
  const verdict = verifyQuote(token, { companyId, amount, secret, now });
  if (verdict.ok) return { ok: true };
  return { ok: false, code: verdict.reason === 'amount_mismatch' ? 'amount_mismatch' : 'quote_invalid' };
}

module.exports = {
  signQuote,
  verifyQuote,
  checkQuote,
  quoteSecret,
  quoteRequired,
  DEFAULT_TTL_MS,
};
