// backend/utils/notchpay.js
// Thin wrapper around the Notch Pay API (Mobile Money + card via one endpoint).
// Secrets live in env vars only — they are never exposed to the Flutter app.
//
// Docs: https://developer.notchpay.co
// Base: https://api.notchpay.co (same host for sandbox + live; switch via keys).
const crypto = require('crypto');

const NOTCHPAY_BASE_URL =
  process.env.NOTCHPAY_BASE_URL || 'https://api.notchpay.co';

// Public key (pk_...) → Authorization header. Private key (sk_...) → X-Grant
// header (optional; only needed for sensitive/transfer/management operations).
const PUBLIC_KEY = process.env.NOTCHPAY_PUBLIC_KEY || '';
const PRIVATE_KEY = process.env.NOTCHPAY_PRIVATE_KEY || '';
// Dashboard "Hash Key" used to verify webhook HMAC-SHA256 signatures.
const WEBHOOK_SECRET = process.env.NOTCHPAY_WEBHOOK_SECRET || '';

function isConfigured() {
  return Boolean(PUBLIC_KEY);
}

function status() {
  return {
    publicKeySet: Boolean(PUBLIC_KEY),
    privateKeySet: Boolean(PRIVATE_KEY),
    webhookSecretSet: Boolean(WEBHOOK_SECRET),
  };
}

/**
 * Initialize a payment. Notch Pay returns a hosted checkout URL; optionally
 * lock it to a single channel/country so the customer skips method selection.
 * @param {object} params { amount, currency, phone, email, reference, channel, country, description, callback }
 * @returns {object} { reference, transaction, authorizationUrl }
 */
async function initiatePayment({
  amount,
  currency,
  phone,
  email,
  reference,
  channel,
  country,
  description,
  callback,
  publicKey,
  privateKey,
  syncId,
}) {
  const body = {
    amount: Number(amount),
    currency: currency || 'XAF',
    reference,
  };
  if (phone) body.phone = String(phone);
  if (email) body.email = email;
  if (description) body.description = description;
  if (callback) body.callback = callback;
  if (channel) body.locked_channel = channel; // e.g. 'cm.mtn' | 'cm.orange'
  if (country) body.locked_country = country; // e.g. 'CM'

  const headers = {
    'Content-Type': 'application/json',
    Authorization: publicKey || PUBLIC_KEY,
  };
  if (privateKey || PRIVATE_KEY) headers['X-Grant'] = privateKey || PRIVATE_KEY;
  if (syncId) headers['X-Sync'] = syncId;

  const response = await fetch(`${NOTCHPAY_BASE_URL}/payments`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok || (data.code >= 400 && data.code <= 599)) {
    throw new Error(
      data.message || `Notch Pay initiate failed (${response.status})`
    );
  }

  return {
    reference,
    transaction: data.transaction || null,
    authorizationUrl: data.authorization_url || null,
  };
}

/**
 * Retrieve a payment by reference and return its normalized status, or null
 * if it cannot be determined (e.g. unexpected payload shape).
 * @returns {'completed'|'pending'|'failed'|'expired'|'cancelled'|null}
 */
async function getPaymentStatus(reference, { publicKey, syncId } = {}) {
  const headers = { Authorization: publicKey || PUBLIC_KEY };
  if (syncId) headers['X-Sync'] = syncId;
  const response = await fetch(
    `${NOTCHPAY_BASE_URL}/payments/${encodeURIComponent(reference)}`,
    {
      method: 'GET',
      headers,
    }
  );
  if (!response.ok) return null;
  const data = await response.json().catch(() => ({}));

  // The documented retrieve response wraps the transaction. It can be a UUID
  // string or an object carrying the real state, so be defensive about shape.
  const tx = data.transaction ?? data.data;
  if (tx && typeof tx === 'object') {
    const raw = tx.status ?? tx.state ?? tx.payment_status;
    if (raw != null) return normalizeStatus(raw);
  }
  if (typeof data.status === 'string') return normalizeStatus(data.status);
  return null;
}

/**
 * Map Notch Pay / provider status strings to our canonical statuses.
 */
function normalizeStatus(status) {
  const s = String(status || '').toLowerCase();
  if (['complete', 'completed', 'success', 'successful', 'succeeded', 'done'].includes(s)) {
    return 'completed';
  }
  if (['pending', 'pending_complete', 'processing', 'initiated', 'accepted'].includes(s)) {
    return 'pending';
  }
  if (['failed', 'fail', 'rejected', 'error', 'reversed', 'refunded'].includes(s)) {
    return 'failed';
  }
  if (['expired', 'timeout', 'timed_out'].includes(s)) {
    return 'expired';
  }
  if (['cancelled', 'canceled', 'cancel'].includes(s)) {
    return 'cancelled';
  }
  return 'pending';
}

/**
 * Verify a Notch Pay webhook signature (HMAC-SHA256 of the raw JSON body,
 * signed with the dashboard's webhook hash key; sent in `x-notch-signature`).
 */
function verifyWebhookSignature(rawBody, signatureHeader, hash) {
  const secret = hash || WEBHOOK_SECRET;
  if (!secret || !signatureHeader) return false;
  const expected = crypto
    .createHmac('sha256', secret)
    .update(rawBody)
    .digest('hex');
  try {
    return crypto.timingSafeEqual(
      Buffer.from(expected, 'utf8'),
      Buffer.from(String(signatureHeader), 'utf8')
    );
  } catch (e) {
    return false;
  }
}

module.exports = {
  isConfigured,
  status,
  initiatePayment,
  getPaymentStatus,
  normalizeStatus,
  verifyWebhookSignature,
};
