// tests/order_quote.test.js
// A payment must never collect less than the server priced. These tests pin the
// four things that make that true: the signature, the company binding, the expiry
// and the exact amount.
const {
  signQuote, verifyQuote, checkQuote, quoteSecret, quoteRequired, DEFAULT_TTL_MS,
} = require('../utils/orderQuote');

const SECRET = 'test-secret-at-least-16-chars';
const NOW = 1_800_000_000_000;

describe('signQuote / verifyQuote', () => {
  test('a signed total verifies for the same company and amount', () => {
    const { token, expiresAt } = signQuote(
      { companyId: 7, total: 5000, unitCount: 3, now: NOW }, SECRET
    );
    expect(expiresAt).toBe(NOW + DEFAULT_TTL_MS);
    expect(verifyQuote(token, { companyId: 7, amount: 5000, secret: SECRET, now: NOW }))
      .toEqual({ ok: true });
  });

  test('a different amount is refused (the whole point)', () => {
    const { token } = signQuote({ companyId: 7, total: 5000, now: NOW }, SECRET);
    expect(verifyQuote(token, { companyId: 7, amount: 500, secret: SECRET, now: NOW }))
      .toEqual({ ok: false, reason: 'amount_mismatch' });
  });

  test('another company cannot reuse the quote', () => {
    const { token } = signQuote({ companyId: 7, total: 5000, now: NOW }, SECRET);
    expect(verifyQuote(token, { companyId: 8, amount: 5000, secret: SECRET, now: NOW }))
      .toEqual({ ok: false, reason: 'wrong_company' });
  });

  test('a tampered payload is refused', () => {
    const { token } = signQuote({ companyId: 7, total: 5000, now: NOW }, SECRET);
    const [body, sig] = token.split('.');
    const forged = Buffer.from(
      JSON.stringify({ c: '7', t: 500, u: 3, e: NOW + 1000 }), 'utf8'
    ).toString('base64url');
    expect(verifyQuote(`${forged}.${sig}`, { companyId: 7, amount: 500, secret: SECRET, now: NOW }))
      .toEqual({ ok: false, reason: 'bad_signature' });
    expect(verifyQuote(`${body}.${sig}x`, { companyId: 7, amount: 5000, secret: SECRET, now: NOW }).ok)
      .toBe(false);
  });

  test('an expired quote is refused', () => {
    const { token } = signQuote({ companyId: 7, total: 5000, ttlMs: 1000, now: NOW }, SECRET);
    expect(verifyQuote(token, { companyId: 7, amount: 5000, secret: SECRET, now: NOW + 1001 }))
      .toEqual({ ok: false, reason: 'expired' });
  });

  test('the signature is bound to the secret', () => {
    const { token } = signQuote({ companyId: 7, total: 5000, now: NOW }, SECRET);
    expect(verifyQuote(token, {
      companyId: 7, amount: 5000, secret: 'another-secret-16-chars', now: NOW,
    }).ok).toBe(false);
  });

  test('rounding tolerance: 5000.4 quotes and pays as 5000', () => {
    const { token } = signQuote({ companyId: 7, total: 5000.4, now: NOW }, SECRET);
    expect(verifyQuote(token, { companyId: 7, amount: 5000, secret: SECRET, now: NOW }).ok).toBe(true);
  });

  test('no secret means no token (feature off, never silently open)', () => {
    expect(signQuote({ companyId: 7, total: 5000, now: NOW }, null)).toBeNull();
  });

  test('garbage tokens are refused without throwing', () => {
    expect(verifyQuote('', { companyId: 7, amount: 1, secret: SECRET }).ok).toBe(false);
    expect(verifyQuote('nope', { companyId: 7, amount: 1, secret: SECRET })).toEqual(
      { ok: false, reason: 'malformed' }
    );
    expect(verifyQuote('a.', { companyId: 7, amount: 1, secret: SECRET }).ok).toBe(false);
    expect(verifyQuote(42, { companyId: 7, amount: 1, secret: SECRET })).toEqual(
      { ok: false, reason: 'missing' }
    );
  });
});

describe('checkQuote (rollout gate)', () => {
  const base = { companyId: 7, amount: 5000, secret: SECRET, now: NOW };

  test('feature off: everything proceeds', () => {
    expect(checkQuote({ ...base, token: null, secret: null, required: false }).ok).toBe(true);
    // No secret configured = feature off, even if the switch says required.
    expect(checkQuote({ ...base, secret: null, token: null, required: true }).ok).toBe(true);
  });

  test('token supplied is verified even when not required', () => {
    const { token } = signQuote({ companyId: 7, total: 5000, now: NOW }, SECRET);
    expect(checkQuote({ ...base, token, required: false }).ok).toBe(true);
    expect(checkQuote({ ...base, amount: 500, token, required: false }))
      .toEqual({ ok: false, code: 'amount_mismatch' });
  });

  test('required without a token is refused with a stable code', () => {
    expect(checkQuote({ ...base, token: '', required: true }))
      .toEqual({ ok: false, code: 'quote_required' });
  });

  test('an invalid token is reported as quote_invalid', () => {
    expect(checkQuote({ ...base, token: 'abc.def', required: false }))
      .toEqual({ ok: false, code: 'quote_invalid' });
  });
});

describe('environment switches', () => {
  test('a short secret is ignored rather than trusted', () => {
    expect(quoteSecret({ ORDER_QUOTE_SECRET: 'short' })).toBeNull();
    expect(quoteSecret({ ORDER_QUOTE_SECRET: SECRET })).toBe(SECRET);
    expect(quoteSecret({})).toBeNull();
  });

  test('PAYMENT_QUOTE_REQUIRED is off unless explicitly "true"', () => {
    expect(quoteRequired({})).toBe(false);
    expect(quoteRequired({ PAYMENT_QUOTE_REQUIRED: '1' })).toBe(false);
    expect(quoteRequired({ PAYMENT_QUOTE_REQUIRED: 'TRUE' })).toBe(true);
  });
});
