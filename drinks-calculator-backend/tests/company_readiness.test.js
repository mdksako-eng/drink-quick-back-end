/**
 * The platform owner's view of CamerPay readiness - no database required.
 *
 * Two things must stay true as this evolves:
 *   1. the "one next step" order is right (a server-side blocker is reported
 *      before a company-side one, so nobody is sent in a circle), and
 *   2. the admin list carries NO secret material: not the token, not the masked
 *      token, and not the webhook URL - whose path holds the company's opaque
 *      webhook token.
 *
 * Run with: npm test
 */
const fs = require('fs');
const path = require('path');

const readiness = require('../utils/companyReadiness');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

// A fully connected company, with values that must never come back out.
const CONNECTED = {
  id: 42,
  name: 'Banga School',
  plan: 'pro',
  subscription_status: 'active',
  campay_enabled: true,
  campay_token_enc: 'v1.iv.tag.TOKEN_CIPHERTEXT_SHOULD_NEVER_LEAK',
  campay_webhook_secret_enc: 'v1.iv.tag.SECRET_CIPHERTEXT_SHOULD_NEVER_LEAK',
  campay_connected_at: '2026-10-28T10:00:00.000Z',
  campay_webhook_token: 'opaqueWebhookToken123',
};

const NOT_CONNECTED = {
  id: 7,
  name: 'Shop Seven',
  plan: 'free',
  subscription_status: null,
};

describe('the one next step a company needs', () => {
  test('a missing server vault key comes before asking a company to connect', () => {
    const step = readiness.nextStepFor({ blockers: ['vault_key_missing', 'no_token'] });
    expect(step).toBe(readiness.STEPS.VAULT_KEY);
  });

  test('a token without a webhook secret is not "ready"', () => {
    expect(readiness.nextStepFor({ blockers: ['no_webhook_secret'] }))
      .toBe(readiness.STEPS.WEBHOOK_SECRET);
  });

  test('no blockers means ready', () => {
    expect(readiness.nextStepFor({ blockers: [] })).toBe(readiness.STEPS.READY);
    expect(readiness.nextStepFor({})).toBe(readiness.STEPS.READY);
  });
});

describe('one company, as the admin list shows it', () => {
  const savedKey = process.env.PAYMENT_CREDENTIALS_KEY;

  afterEach(() => {
    if (savedKey === undefined) delete process.env.PAYMENT_CREDENTIALS_KEY;
    else process.env.PAYMENT_CREDENTIALS_KEY = savedKey;
  });

  test('a connected company reports ready, with booleans only', () => {
    process.env.PAYMENT_CREDENTIALS_KEY = 'test-vault-key';
    const row = readiness.rowFor(CONNECTED, { accountDeclaredLive: true });

    expect(row.id).toBe(42);
    expect(row.name).toBe('Banga School');
    expect(row.connected).toBe(true);
    expect(row.canCollect).toBe(true);
    expect(row.canVerifyWebhooks).toBe(true);
    expect(row.webhookSecretSet).toBe(true);
    expect(row.accountDeclaredLive).toBe(true);
    expect(row.blockers).toEqual([]);
    expect(row.nextStep).toBe(readiness.STEPS.READY);
  });

  test('the row carries no secret material at all', () => {
    process.env.PAYMENT_CREDENTIALS_KEY = 'test-vault-key';
    const row = readiness.rowFor(CONNECTED, { baseUrl: 'https://api.example.com' });
    const serialized = JSON.stringify(row);

    expect(serialized).not.toContain('TOKEN_CIPHERTEXT_SHOULD_NEVER_LEAK');
    expect(serialized).not.toContain('SECRET_CIPHERTEXT_SHOULD_NEVER_LEAK');
    // The webhook path IS a credential: its opaque token stays out of a list.
    expect(serialized).not.toContain('opaqueWebhookToken123');
    expect(Object.keys(row)).not.toContain('tokenMasked');
    expect(Object.keys(row)).not.toContain('webhookUrl');
    expect(Object.keys(row)).not.toContain('webhookPath');
  });

  test('a company with nothing says so, and does not claim to collect', () => {
    process.env.PAYMENT_CREDENTIALS_KEY = 'test-vault-key';
    const row = readiness.rowFor(NOT_CONNECTED);

    expect(row.connected).toBe(false);
    expect(row.canCollect).toBe(false);
    expect(row.canVerifyWebhooks).toBe(false);
    expect(row.blockers).toContain('no_token');
    expect(row.blockers).toContain('no_webhook_secret');
    expect(row.nextStep).toBe(readiness.STEPS.TOKEN);
  });

  test('with no vault key on the server, every company points at the server fix', () => {
    delete process.env.PAYMENT_CREDENTIALS_KEY;
    const row = readiness.rowFor(CONNECTED);

    expect(row.blockers).toContain('vault_key_missing');
    expect(row.nextStep).toBe(readiness.STEPS.VAULT_KEY);
  });
});

describe('the summary line', () => {
  test('counts ready, blocked, and the steps behind the blockers', () => {
    const rows = [
      { nextStep: readiness.STEPS.READY },
      { nextStep: readiness.STEPS.TOKEN },
      { nextStep: readiness.STEPS.TOKEN },
      { nextStep: readiness.STEPS.WEBHOOK_SECRET },
    ];
    const summary = readiness.summarize(rows);

    expect(summary.total).toBe(4);
    expect(summary.ready).toBe(1);
    expect(summary.blocked).toBe(3);
    expect(summary.byStep[readiness.STEPS.TOKEN]).toBe(2);
    expect(readiness.summarize([]).total).toBe(0);
    expect(readiness.summarize(null).blocked).toBe(0);
  });
});

describe('the platform-wide facts', () => {
  const savedKey = process.env.PAYMENT_CREDENTIALS_KEY;

  afterEach(() => {
    if (savedKey === undefined) delete process.env.PAYMENT_CREDENTIALS_KEY;
    else process.env.PAYMENT_CREDENTIALS_KEY = savedKey;
  });

  test('the storage key is reported once, not per company', () => {
    process.env.PAYMENT_CREDENTIALS_KEY = 'test-vault-key';
    expect(readiness.platformState().vaultReady).toBe(true);

    delete process.env.PAYMENT_CREDENTIALS_KEY;
    expect(readiness.platformState().vaultReady).toBe(false);
  });
});

describe('the admin surface stays admin-only and secret-free', () => {
  test('the readiness route is behind the platform admin gate', () => {
    const server = read('server.js');
    expect(server).toContain("app.get('/api/admin/campay-readiness', verifyAdmin");
  });

  test('the query never reads the webhook token or a plaintext secret column', () => {
    // The opaque webhook token and the plaintext legacy columns: none may be read.
    expect(readiness.COLUMNS).not.toContain('campay_webhook_token');
    expect(readiness.COLUMNS).not.toContain('campay_token');
    expect(readiness.COLUMNS).not.toContain('campay_webhook_secret');
  });

  test('the ops script takes the password from the environment, never an argument', () => {
    const script = read('scripts/campay_readiness.js');
    expect(script).toContain('process.env.ADMIN_PASSWORD');
    expect(script).not.toMatch(/ADMIN_PASSWORD\s*[:=]\s*['"][^'"]+['"]/);
  });
});
