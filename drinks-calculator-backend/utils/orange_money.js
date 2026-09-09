// backend/utils/orange_money.js
// Orange Money Web Payment (OMWP) wrapper.
//
// Credential mapping (stored per-company in the `companies` table, entered by
// the manager in Payment Settings):
//   orange_api_key      -> OAuth client_id (consumer key)
//   orange_secret_key   -> OAuth client_secret
//   orange_merchant_id  -> merchant key (from Orange Money)
//   orange_sandbox_mode -> true = sandbox, false = production
//
// Docs: https://developer.orange.com

const TOKEN_URL = process.env.ORANGE_TOKEN_URL || 'https://api.orange.com/oauth/v3/token';
const WEBPAY_BASE = process.env.ORANGE_WEBPAY_BASE || 'https://api.orange.com/orange-money-webpay/cm/v1';

function isConfigured(company) {
  return Boolean(
    company &&
    company.orange_merchant_id &&
    company.orange_api_key &&
    company.orange_secret_key
  );
}

async function getAccessToken({ clientId, clientSecret }) {
  const auth = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
  const resp = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Authorization: `Basic ${auth}`,
    },
    body: 'grant_type=client_credentials',
  });
  const data = await resp.json();
  if (!resp.ok || !data.access_token) {
    throw new Error(`Orange Money token failed (${resp.status})`);
  }
  return data.access_token;
}

/**
 * Initiate an Orange Money web payment.
 * Returns the parsed response containing `payment_url`.
 */
async function initiatePayment({
  accessToken,
  merchantKey,
  amount,
  currency,
  orderId,
  reference,
  returnUrl,
  cancelUrl,
  notifUrl,
}) {
  const resp = await fetch(`${WEBPAY_BASE}/webpayment`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      merchant_key: merchantKey,
      currency: currency || 'XAF',
      order_id: orderId,
      amount: Number(amount),
      return_url: returnUrl,
      cancel_url: cancelUrl,
      notif_url: notifUrl,
      lang: 'fr',
      reference: reference,
    }),
  });
  const data = await resp.json();
  if (!resp.ok || !data.payment_url) {
    throw new Error(`Orange Money webpayment failed (${resp.status})`);
  }
  return data; // { payment_url, notif_token, order_id, ... }
}

module.exports = { isConfigured, getAccessToken, initiatePayment };
