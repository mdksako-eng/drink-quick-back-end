// backend/tests/company_payment_credentials.test.js
// Per-company CamerPay credentials: each bar's token is its own asset, and a
// webhook is only trustworthy when that bar's own secret verifies it.
const crypto = require('crypto');
const creds = require('../utils/companyPaymentCredentials');

const KEY = crypto.createHash('sha256').update('company-creds-test').digest('hex');
const ORIGINAL_KEY = process.env.PAYMENT_CREDENTIALS_KEY;

beforeEach(() => {
  process.env.PAYMENT_CREDENTIALS_KEY = KEY;
});

afterEach(() => {
  if (ORIGINAL_KEY === undefined) delete process.env.PAYMENT_CREDENTIALS_KEY;
  else process.env.PAYMENT_CREDENTIALS_KEY = ORIGINAL_KEY;
});

const TOKEN = '2|aB3xY9mK7pQ4nR1tS6uV8wZ0cD5eF2gH';
const SECRET = 'whsec_bar_one';

/** A company row as it comes back from the database. */
function connectedRow({ enabled = true, withSecret = true, companyId = 7 } = {}) {
  const { tokenEnc, webhookSecretEnc } = creds.encryptConnection({
    token: TOKEN,
    webhookSecret: withSecret ? SECRET : '',
  });
  return {
    id: companyId,
    [creds.COLUMNS.enabled]: enabled,
    [creds.COLUMNS.token]: tokenEnc,
    [creds.COLUMNS.webhookToken]: 'opaqueWebhookToken123',
    [creds.COLUMNS.webhookSecret]: webhookSecretEnc,
    [creds.COLUMNS.connectedAt]: '2026-10-07T00:00:00.000Z',
  };
}

describe('validateConnection', () => {
  test('accepts a plausible token', () => {
    expect(creds.validateConnection({ token: TOKEN }).ok).toBe(true);
  });

  test('requires a token', () => {
    expect(creds.validateConnection({}).reason).toBe('token_required');
    expect(creds.validateConnection({ token: '   ' }).reason).toBe('token_required');
  });

  test('rejects a token that is too short or contains whitespace', () => {
    expect(creds.validateConnection({ token: '2|abc' }).reason).toBe('token_too_short');
    expect(creds.validateConnection({ token: `${TOKEN} x` }).reason).toBe('token_has_whitespace');
  });

  test('a missing webhook secret is allowed, a truncated one is not', () => {
    expect(creds.validateConnection({ token: TOKEN }).ok).toBe(true);
    expect(creds.validateConnection({ token: TOKEN, webhookSecret: 'abc' }).reason)
      .toBe('webhook_secret_too_short');
    expect(creds.validateConnection({ token: TOKEN, webhookSecret: 'long-enough' }).ok).toBe(true);
  });
});

describe('webhook tokens', () => {
  test('are URL-safe and unique', () => {
    const a = creds.newWebhookToken();
    const b = creds.newWebhookToken();
    expect(a).not.toBe(b);
    expect(a).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(a.length).toBeGreaterThanOrEqual(30);
  });

  test('build a path that never exposes a company id', () => {
    const path = creds.webhookPath('abc123');
    expect(path).toBe('/api/payment/campay-webhook/abc123');
  });
});

describe('connectionFor', () => {
  test('decrypts the token and secret for a connected company', () => {
    const conn = creds.connectionFor(connectedRow());
    expect(conn).toMatchObject({
      token: TOKEN, webhookSecret: SECRET, webhookToken: 'opaqueWebhookToken123',
      enabled: true, companyId: 7,
    });
  });

  test('returns null when disabled, unset, or unreadable', () => {
    expect(creds.connectionFor(connectedRow({ enabled: false }))).toBeNull();
    expect(creds.connectionFor({ id: 1 })).toBeNull();
    expect(creds.connectionFor(null)).toBeNull();
    // A vault key mismatch must fail closed rather than collect with junk.
    const row = connectedRow();
    process.env.PAYMENT_CREDENTIALS_KEY = crypto.createHash('sha256').update('other').digest('hex');
    expect(creds.connectionFor(row)).toBeNull();
  });

  test('a company without a webhook secret can still collect', () => {
    const conn = creds.connectionFor(connectedRow({ withSecret: false }));
    expect(conn.token).toBe(TOKEN);
    expect(conn.webhookSecret).toBe('');
  });

  test('isConnected never decrypts', () => {
    expect(creds.isConnected(connectedRow())).toBe(true);
    expect(creds.isConnected({ id: 1 })).toBe(false);
    expect(creds.isConnected(connectedRow({ enabled: false }))).toBe(false);
  });

  test('legacy plaintext credentials still work (migration tolerance)', () => {
    const row = connectedRow();
    row[creds.COLUMNS.token] = 'plain-token-from-before';
    row[creds.COLUMNS.webhookSecret] = 'plain-secret';
    const conn = creds.connectionFor(row);
    expect(conn.token).toBe('plain-token-from-before');
    expect(conn.webhookSecret).toBe('plain-secret');
  });
});

describe('findByWebhookToken', () => {
  // The vault key is only set in beforeEach, but this fixture encrypts at
  // collection time, so set it here too.
  process.env.PAYMENT_CREDENTIALS_KEY = KEY;
  const rows = [
    connectedRow({ companyId: 7 }),
    {
      ...connectedRow({ companyId: 9 }),
      [creds.COLUMNS.webhookToken]: 'otherToken',
    },
  ];

  test('finds the owning company', () => {
    expect(creds.findByWebhookToken(rows, 'otherToken').id).toBe(9);
    expect(creds.findByWebhookToken(rows, 'opaqueWebhookToken123').id).toBe(7);
  });

  test('returns null for an unknown or empty token', () => {
    expect(creds.findByWebhookToken(rows, 'nope')).toBeNull();
    expect(creds.findByWebhookToken(rows, '')).toBeNull();
    expect(creds.findByWebhookToken(null, 'x')).toBeNull();
    expect(creds.findByWebhookToken([], 'x')).toBeNull();
  });

  test('tokensMatch is constant-time and length-safe', () => {
    expect(creds.tokensMatch('abc', 'abc')).toBe(true);
    expect(creds.tokensMatch('abc', 'abd')).toBe(false);
    expect(creds.tokensMatch('abc', 'abcd')).toBe(false);
    expect(creds.tokensMatch('', '')).toBe(false);
    expect(creds.tokensMatch(null, undefined)).toBe(false);
  });
});

describe('views', () => {
  test('maskedView never exposes a usable secret', () => {
    const view = creds.maskedView(connectedRow(), { baseUrl: 'https://app.example.com/' });
    expect(view.connected).toBe(true);
    expect(view.enabled).toBe(true);
    expect(view.tokenMasked).toBe('****');
    expect(view.webhookSecretSet).toBe(true);
    expect(view.webhookUrl)
      .toBe('https://app.example.com/api/payment/campay-webhook/opaqueWebhookToken123');
    const serialized = JSON.stringify(view);
    expect(serialized).not.toContain(TOKEN);
    expect(serialized).not.toContain(SECRET);
  });

  test('maskedView handles an unconnected company', () => {
    const view = creds.maskedView({ id: 3 }, { baseUrl: 'https://app.example.com' });
    expect(view).toMatchObject({
      connected: false, enabled: false, tokenMasked: '', webhookSecretSet: false,
      webhookPath: null, webhookUrl: null,
    });
  });

  test('healthFor lists the blockers without over-claiming', () => {
    const healthy = creds.healthFor(connectedRow(), { baseUrl: 'https://a.example.com' });
    expect(healthy.canCollect).toBe(true);
    expect(healthy.canVerifyWebhooks).toBe(true);
    expect(healthy.blockers).toEqual([]);
    expect(healthy.accountDeclaredLive).toBe(false);

    const partial = creds.healthFor(connectedRow({ withSecret: false }));
    expect(partial.canCollect).toBe(true);
    expect(partial.canVerifyWebhooks).toBe(false);
    expect(partial.blockers).toContain('no_webhook_secret');

    const none = creds.healthFor({ id: 4 });
    expect(none.canCollect).toBe(false);
    expect(none.blockers).toEqual(expect.arrayContaining(['no_token', 'no_webhook_secret']));
  });

  test('healthFor reports a missing vault key, because nothing could be stored', () => {
    const row = connectedRow();
    delete process.env.PAYMENT_CREDENTIALS_KEY;
    const health = creds.healthFor(row);
    expect(health.vaultReady).toBe(false);
    expect(health.blockers).toContain('vault_key_missing');
  });
});

