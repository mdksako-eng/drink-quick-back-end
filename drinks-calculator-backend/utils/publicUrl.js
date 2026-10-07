// backend/utils/publicUrl.js
// One source of truth for the URL the outside world can reach us on.
//
// Why it matters: payment providers call us back. CamerPay's docs are explicit
// that it BLOCKS internal URLs ("URL interne (192.168.x.x, localhost) : nous
// bloquons les URLs internes pour éviter le SSRF") and requires HTTPS, so a
// callback built from a `http://localhost:3000` fallback can never be delivered —
// the customer pays and nothing ever activates the plan.
//
// Order of preference:
//   1. APP_BASE_URL        — explicit, and the only way to point at a tunnel (ngrok)
//   2. RENDER_EXTERNAL_URL — injected automatically by Render
//   3. ''                  — unknown, and callers must treat that as an error
const LOCAL_HOSTNAMES = ['localhost', '127.0.0.1', '0.0.0.0', '::1'];

/** Trim trailing slashes so callers can join paths without doubling them. */
function normalizeBase(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  return text.replace(/\/+$/, '');
}

/**
 * @param {object} [env] environment-like object (defaults to process.env)
 * @returns {string} public base URL without a trailing slash, or '' when unknown
 */
function publicBaseUrl(env = process.env) {
  const explicit = normalizeBase(env && env.APP_BASE_URL);
  if (explicit) return explicit;
  return normalizeBase(env && env.RENDER_EXTERNAL_URL);
}

/**
 * Absolute public URL for a path, or '' when no base URL is known.
 * Returning '' (instead of a localhost guess) is deliberate: a caller that cannot
 * build a reachable callback must refuse the payment rather than silently start
 * one the provider will drop.
 * @returns {string}
 */
function providerCallbackUrl(path, env = process.env) {
  const base = publicBaseUrl(env);
  if (!base) return '';
  const suffix = String(path || '');
  if (!suffix) return base;
  return `${base}${suffix.startsWith('/') ? suffix : `/${suffix}`}`;
}

/** Where the base URL came from — for /health and the startup banner. */
function describeBaseUrlSource(env = process.env) {
  if (normalizeBase(env && env.APP_BASE_URL)) return 'APP_BASE_URL';
  if (normalizeBase(env && env.RENDER_EXTERNAL_URL)) return 'RENDER_EXTERNAL_URL';
  return 'unset';
}

/** True for localhost, loopback and RFC1918 addresses — all unreachable by providers. */
function isLocalOrPrivateUrl(value) {
  let host;
  try {
    host = new URL(String(value)).hostname.toLowerCase();
  } catch (e) {
    return false;
  }
  if (LOCAL_HOSTNAMES.includes(host)) return true;
  if (/^10\./.test(host)) return true;
  if (/^192\.168\./.test(host)) return true;
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(host)) return true;
  return host.endsWith('.local');
}

/**
 * Is this base URL actually usable by a payment provider?
 * @returns {{ok: boolean, reason: string}}
 */
function isProviderReachable(value) {
  const base = normalizeBase(value);
  if (!base) return { ok: false, reason: 'no_public_url' };
  let parsed;
  try {
    parsed = new URL(base);
  } catch (e) {
    return { ok: false, reason: 'malformed_url' };
  }
  if (parsed.protocol !== 'https:') return { ok: false, reason: 'not_https' };
  if (isLocalOrPrivateUrl(base)) return { ok: false, reason: 'local_or_private' };
  return { ok: true, reason: 'ok' };
}

module.exports = {
  publicBaseUrl,
  providerCallbackUrl,
  describeBaseUrlSource,
  isLocalOrPrivateUrl,
  isProviderReachable,
};
