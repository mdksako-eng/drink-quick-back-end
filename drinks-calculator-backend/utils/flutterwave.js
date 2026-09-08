// backend/utils/flutterwave.js
// Thin wrapper around the Flutterwave API (card payments + subscriptions).
// Secrets live in env vars only — they are never exposed to the Flutter app.
const crypto = require('crypto');

const FLUTTERWAVE_BASE_URL =
  process.env.FLUTTERWAVE_BASE_URL || 'https://api.flutterwave.com/v3';

const SECRET_KEY = process.env.FLUTTERWAVE_SECRET_KEY || '';
const PUBLIC_KEY = process.env.FLUTTERWAVE_PUBLIC_KEY || '';
const WEBHOOK_SECRET = process.env.FLUTTERWAVE_WEBHOOK_SECRET || '';

function isConfigured() {
  return Boolean(SECRET_KEY);
}

/**
 * Create a one-time card payment (returns a hosted checkout link).
 * @param {object} params { txRef, amount, currency, email, name, phone, redirectUrl, plan, companyId }
 */
async function initiatePayment({
  txRef,
  amount,
  currency,
  email,
  name,
  phone,
  redirectUrl,
  plan,
  companyId,
}) {
  const response = await fetch(`${FLUTTERWAVE_BASE_URL}/payments`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${SECRET_KEY}`,
    },
    body: JSON.stringify({
      tx_ref: txRef,
      amount: String(amount),
      currency: currency || 'XAF',
      redirect_url: redirectUrl,
      payment_options: 'card',
      customer: {
        email: email || 'customer@drinkquick.app',
        phonenumber: phone || '',
        name: name || 'Customer',
      },
      meta: { companyId, plan },
      customizations: {
        title: 'Drink Quick Cal',
        description: `${plan || 'Subscription'} subscription`,
      },
    }),
  });

  const data = await response.json();
  if (!response.ok || data.status !== 'success') {
    throw new Error(
      data.message || `Flutterwave initiate failed (${response.status})`
    );
  }
  return data.data; // { link, ... }
}

/**
 * Verify a transaction with Flutterwave.
 * @returns {object|null} the verified transaction data, or null.
 */
async function verifyTransaction(transactionId) {
  const response = await fetch(
    `${FLUTTERWAVE_BASE_URL}/transactions/${encodeURIComponent(transactionId)}/verify`,
    {
      method: 'GET',
      headers: { Authorization: `Bearer ${SECRET_KEY}` },
    }
  );
  const data = await response.json();
  if (!response.ok || data.status !== 'success') {
    return null;
  }
  return data.data; // { status: 'successful'|..., tx_ref, amount, currency, ... }
}

/**
 * Verify a Flutterwave webhook signature (HMAC-SHA256 of the raw body).
 */
function verifyWebhookSignature(rawBody, signatureHeader) {
  if (!WEBHOOK_SECRET || !signatureHeader) return false;
  const expected = crypto
    .createHmac('sha256', WEBHOOK_SECRET)
    .update(rawBody)
    .digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(expected, 'utf8'),
    Buffer.from(String(signatureHeader), 'utf8')
  );
}

module.exports = {
  isConfigured,
  initiatePayment,
  verifyTransaction,
  verifyWebhookSignature,
  get publicKey() {
    return PUBLIC_KEY;
  },
};
