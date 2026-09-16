/**
 * Notch Pay mode detection — no network or database required.
 * Guards the "live subscriptions / real B2C payments" configuration check.
 */
const notchpay = require('../utils/notchpay');

describe('Notch Pay live/test detection', () => {
  test('detects live keys', () => {
    expect(notchpay.keyMode('pk_live_abc123')).toBe('live');
    expect(notchpay.keyMode('sk_live_abc123')).toBe('live');
  });

  test('detects test and sandbox keys', () => {
    expect(notchpay.keyMode('pk_test_abc123')).toBe('test');
    expect(notchpay.keyMode('sk_test_abc123')).toBe('test');
    expect(notchpay.keyMode('pk_sandbox_abc123')).toBe('test');
  });

  test('handles missing and unrecognised keys without throwing', () => {
    expect(notchpay.keyMode('')).toBe('missing');
    expect(notchpay.keyMode(null)).toBe('missing');
    expect(notchpay.keyMode('some-other-key')).toBe('unknown');
  });

  test('status() exposes mode, secrets presence and base url', () => {
    const status = notchpay.status();
    expect(status).toHaveProperty('publicKeySet');
    expect(status).toHaveProperty('privateKeySet');
    expect(status).toHaveProperty('webhookSecretSet');
    expect(status).toHaveProperty('mode');
    expect(status.baseUrl).toContain('notchpay.co');
  });
});