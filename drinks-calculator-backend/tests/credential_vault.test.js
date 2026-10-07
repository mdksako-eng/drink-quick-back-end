// backend/tests/credential_vault.test.js
// Per-company payment credentials must never sit in the database as plaintext.
const crypto = require('crypto');
const vault = require('../utils/credentialVault');

const KEY_HEX = crypto.createHash('sha256').update('unit-test-key').digest('hex');
const ORIGINAL_KEY = process.env.PAYMENT_CREDENTIALS_KEY;

beforeEach(() => {
  process.env.PAYMENT_CREDENTIALS_KEY = KEY_HEX;
});

afterEach(() => {
  if (ORIGINAL_KEY === undefined) delete process.env.PAYMENT_CREDENTIALS_KEY;
  else process.env.PAYMENT_CREDENTIALS_KEY = ORIGINAL_KEY;
});

describe('round trip', () => {
  test('a CamerPay token survives encrypt → decrypt', () => {
    const token = '2|aB3xY9mK7pQ4nR1tS6uV8wZ0cD5eF2gH3jI4kL5mN6oP7qR8sT9uV0wX1y';
    const stored = vault.encryptSecret(token);
    expect(stored).not.toContain(token);
    expect(vault.decryptSecret(stored)).toBe(token);
  });

  test('the stored value carries the version prefix and four parts', () => {
    const stored = vault.encryptSecret('secret');
    expect(stored.startsWith('v1.')).toBe(true);
    expect(stored.split('.')).toHaveLength(4);
  });

  test('the same secret encrypts differently every time (fresh IV)', () => {
    const a = vault.encryptSecret('same-secret');
    const b = vault.encryptSecret('same-secret');
    expect(a).not.toBe(b);
    expect(vault.decryptSecret(a)).toBe('same-secret');
    expect(vault.decryptSecret(b)).toBe('same-secret');
  });

  test('empty and null stay empty — clearing a credential is not encryption', () => {
    expect(vault.encryptSecret('')).toBe('');
    expect(vault.encryptSecret(null)).toBe('');
    expect(vault.decryptSecret('')).toBe('');
  });

  test('handles a secret with unicode and padding characters', () => {
    const secret = 'clé-pour-Orange: 1.5 % ✓ ==';
    expect(vault.decryptSecret(vault.encryptSecret(secret))).toBe(secret);
  });
});

describe('fails closed', () => {
  test('a tampered ciphertext throws instead of returning a wrong token', () => {
    const stored = vault.encryptSecret('sk_live_original');
    const parts = stored.split('.');
    const flipped = parts[3].slice(0, -2) + (parts[3].slice(-2) === 'AA' ? 'BB' : 'AA');
    const tampered = [parts[0], parts[1], parts[2], flipped].join('.');
    expect(() => vault.decryptSecret(tampered)).toThrow();
  });

  test('a wrong key throws', () => {
    const stored = vault.encryptSecret('sk_live_original');
    const otherKey = crypto.createHash('sha256').update('another-key').digest('hex');
    expect(() => vault.decryptSecret(stored, otherKey)).toThrow();
  });

  test('encrypting without a key configured throws', () => {
    delete process.env.PAYMENT_CREDENTIALS_KEY;
    expect(vault.isVaultConfigured()).toBe(false);
    expect(() => vault.encryptSecret('sk_live_x')).toThrow(/PAYMENT_CREDENTIALS_KEY/);
  });

  test('a legacy plaintext value is refused, not treated as ciphertext', () => {
    expect(() => vault.decryptSecret('sk_live_legacy_plain')).toThrow(/Not a vault ciphertext/);
  });

  test('a malformed ciphertext throws', () => {
    expect(() => vault.decryptSecret('v1.onlyonepart')).toThrow(/Malformed/);
  });
});

describe('migration helpers', () => {
  test('readSecret decrypts ciphertext', () => {
    expect(vault.readSecret(vault.encryptSecret('abc123'))).toBe('abc123');
  });

  test('readSecret returns a legacy plaintext untouched', () => {
    expect(vault.readSecret('legacy-plaintext-token')).toBe('legacy-plaintext-token');
    expect(vault.readSecret('')).toBe('');
  });

  test('isEncrypted only accepts vault output', () => {
    expect(vault.isEncrypted(vault.encryptSecret('x'))).toBe(true);
    expect(vault.isEncrypted('v2.abc')).toBe(false);
    expect(vault.isEncrypted('plain')).toBe(false);
    expect(vault.isEncrypted(null)).toBe(false);
  });
});

describe('display helpers', () => {
  test('maskSecret never reveals the secret', () => {
    expect(vault.maskSecret('2|aB3xY9mK7pQ4nR1')).toBe('****4nR1');
    expect(vault.maskSecret('1234')).toBe('****');
    expect(vault.maskSecret('')).toBe('');
    expect(vault.maskSecret(null)).toBe('');
    expect(vault.maskSecret('supersecrettoken')).not.toContain('supersecret');
  });

  test('fingerprint is short, stable and non-reversible', () => {
    const fp = vault.fingerprint('sk_live_abcdef');
    expect(fp).toHaveLength(12);
    expect(fp).toBe(vault.fingerprint('sk_live_abcdef'));
    expect(fp).not.toBe(vault.fingerprint('sk_live_abcdeg'));
    expect(fp).not.toContain('sk_live');
    expect(vault.fingerprint('')).toBe('');
  });
});

describe('key material', () => {
  test('accepts a base64 32-byte key', () => {
    const b64 = crypto.randomBytes(32).toString('base64');
    const stored = vault.encryptSecret('token', b64);
    expect(vault.decryptSecret(stored, b64)).toBe('token');
  });

  test('accepts a passphrase by deriving 32 bytes', () => {
    const stored = vault.encryptSecret('token', 'a-human-passphrase');
    expect(vault.decryptSecret(stored, 'a-human-passphrase')).toBe('token');
    expect(() => vault.decryptSecret(stored, 'another-passphrase')).toThrow();
  });
});
