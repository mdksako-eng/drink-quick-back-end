// backend/tests/public_url.test.js
// The callback URL handed to a payment provider must be one it can actually
// deliver to — CamerPay blocks localhost and private addresses.
const {
  publicBaseUrl,
  providerCallbackUrl,
  describeBaseUrlSource,
  isLocalOrPrivateUrl,
  isProviderReachable,
} = require('../utils/publicUrl');

describe('publicBaseUrl', () => {
  test('prefers APP_BASE_URL', () => {
    expect(publicBaseUrl({
      APP_BASE_URL: 'https://drink-quick-cal-kja1.onrender.com',
      RENDER_EXTERNAL_URL: 'https://other.onrender.com',
    })).toBe('https://drink-quick-cal-kja1.onrender.com');
  });

  test('falls back to RENDER_EXTERNAL_URL, which Render injects automatically', () => {
    expect(publicBaseUrl({ RENDER_EXTERNAL_URL: 'https://drink-quick-cal-kja1.onrender.com' }))
      .toBe('https://drink-quick-cal-kja1.onrender.com');
  });

  test('trims trailing slashes and whitespace', () => {
    expect(publicBaseUrl({ APP_BASE_URL: ' https://app.example.com// ' }))
      .toBe('https://app.example.com');
  });

  test('reports an empty string when nothing is configured', () => {
    expect(publicBaseUrl({})).toBe('');
    expect(publicBaseUrl({ APP_BASE_URL: '   ' })).toBe('');
    expect(publicBaseUrl()).toBe(publicBaseUrl(process.env));
  });
});

describe('providerCallbackUrl', () => {
  test('joins a path onto the base', () => {
    expect(providerCallbackUrl('/api/subscriptions/campay-webhook', {
      APP_BASE_URL: 'https://app.example.com',
    })).toBe('https://app.example.com/api/subscriptions/campay-webhook');
  });

  test('accepts a path without a leading slash', () => {
    expect(providerCallbackUrl('api/x', { RENDER_EXTERNAL_URL: 'https://a.example.com' }))
      .toBe('https://a.example.com/api/x');
  });

  test('returns EMPTY rather than a localhost guess when no base is known', () => {
    expect(providerCallbackUrl('/api/subscriptions/campay-webhook', {})).toBe('');
  });

  test('returns the bare base when no path is given', () => {
    expect(providerCallbackUrl('', { APP_BASE_URL: 'https://app.example.com' }))
      .toBe('https://app.example.com');
  });
});

describe('describeBaseUrlSource', () => {
  test('names where the URL came from', () => {
    expect(describeBaseUrlSource({ APP_BASE_URL: 'https://a' })).toBe('APP_BASE_URL');
    expect(describeBaseUrlSource({ RENDER_EXTERNAL_URL: 'https://a' })).toBe('RENDER_EXTERNAL_URL');
    expect(describeBaseUrlSource({})).toBe('unset');
  });
});

describe('reachability', () => {
  test('detects localhost and private ranges', () => {
    expect(isLocalOrPrivateUrl('http://localhost:3000')).toBe(true);
    expect(isLocalOrPrivateUrl('https://127.0.0.1/hook')).toBe(true);
    expect(isLocalOrPrivateUrl('http://192.168.1.20/hook')).toBe(true);
    expect(isLocalOrPrivateUrl('http://10.0.0.5/hook')).toBe(true);
    expect(isLocalOrPrivateUrl('http://172.16.4.4/hook')).toBe(true);
    expect(isLocalOrPrivateUrl('https://app.example.com/hook')).toBe(false);
    expect(isLocalOrPrivateUrl('not a url')).toBe(false);
  });

  test('a deploy with no base URL would point a provider at localhost', () => {
    expect(isProviderReachable('')).toMatchObject({ ok: false, reason: 'no_public_url' });
  });

  test('http is refused and https on a public host is accepted', () => {
    expect(isProviderReachable('http://app.example.com')).toMatchObject({
      ok: false, reason: 'not_https',
    });
    expect(isProviderReachable('http://192.168.1.5:3000')).toMatchObject({
      ok: false, reason: 'not_https',
    });
    expect(isProviderReachable('https://drink-quick-cal-kja1.onrender.com')).toMatchObject({
      ok: true, reason: 'ok',
    });
  });

  test('https on a private host is still refused (CamerPay blocks SSRF targets)', () => {
    expect(isProviderReachable('https://192.168.1.5')).toMatchObject({
      ok: false, reason: 'local_or_private',
    });
    expect(isProviderReachable('https://localhost:3000')).toMatchObject({
      ok: false, reason: 'local_or_private',
    });
  });

  test('a malformed value is refused', () => {
    expect(isProviderReachable('not-a-url')).toMatchObject({ ok: false, reason: 'malformed_url' });
  });
});
