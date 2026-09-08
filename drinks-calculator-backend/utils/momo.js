// backend/utils/momo.js
// MTN Mobile Money (MoMo) Collection API wrapper.
//
// Credential mapping (stored per-company in the `companies` table, entered by
// the manager in Payment Settings):
//   mtn_merchant_id  -> X-Reference-Id (API User UUID)
//   mtn_api_key      -> API Key (the user's key UUID)
//   mtn_secret_key   -> Ocp-Apim-Subscription-Key (primary subscription key)
//   mtn_sandbox_mode -> true = sandbox, false = production
//
// Official docs: https://momodeveloper.mtn.com

const SANDBOX_BASE = process.env.MTN_MOMO_SANDBOX_URL || 'https://sandbox.momodeveloper.mtn.com';
const PROD_BASE = process.env.MTN_MOMO_BASE_URL || 'https://ericssonbasicapi2.remotemtn.com';

function baseUrlFor(sandbox) {
  return sandbox ? SANDBOX_BASE : PROD_BASE;
}

function isConfigured(company) {
  return Boolean(
    company &&
    company.mtn_merchant_id &&
    company.mtn_api_key &&
    company.mtn_secret_key
  );
}

async function getAccessToken({ apiUser, apiKey, subscriptionKey, sandbox }) {
  const baseUrl = baseUrlFor(sandbox);
  const auth = Buffer.from(`${apiUser}:${apiKey}`).toString('base64');
  const resp = await fetch(`${baseUrl}/collection/token/`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Ocp-Apim-Subscription-Key': subscriptionKey,
    },
  });
  if (!resp.ok) {
    throw new Error(`MTN MoMo token request failed (${resp.status})`);
  }
  const data = await resp.json();
  return data.access_token;
}

/**
 * Send a payment request to the customer's phone.
 * Returns the MTN reference id (the externalId we supply).
 */
async function requestToPay({
  apiUser,
  apiKey,
  subscriptionKey,
  sandbox,
  amount,
  currency,
  phone,
  externalId,
  message,
}) {
  const baseUrl = baseUrlFor(sandbox);
  const token = await getAccessToken({
    apiUser,
    apiKey,
    subscriptionKey,
    sandbox,
  });
  const targetEnv = sandbox ? 'sandbox' : 'production';

  const resp = await fetch(`${baseUrl}/collection/v1_0/requesttopay`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'X-Reference-Id': externalId,
      'X-Target-Environment': targetEnv,
      'Ocp-Apim-Subscription-Key': subscriptionKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount: String(amount),
      currency: currency || 'XAF',
      externalId,
      payer: { partyIdType: 'MSISDN', partyId: phone },
      payerMessage: message || 'Drink Quick Cal subscription',
      payeeNote: 'Subscription payment',
    }),
  });

  if (resp.status !== 202) {
    const text = await resp.text().catch(() => '');
    throw new Error(`MTN MoMo requestToPay failed (${resp.status}) ${text}`);
  }
  return externalId;
}

/**
 * Poll the status of a collection request.
 * Returns the raw status object, e.g. { status: 'PENDING'|'SUCCESSFUL'|'FAILED' }.
 */
async function getTransactionStatus({
  apiUser,
  apiKey,
  subscriptionKey,
  sandbox,
  referenceId,
}) {
  const baseUrl = baseUrlFor(sandbox);
  const token = await getAccessToken({
    apiUser,
    apiKey,
    subscriptionKey,
    sandbox,
  });
  const targetEnv = sandbox ? 'sandbox' : 'production';

  const resp = await fetch(
    `${baseUrl}/collection/v1_0/requesttopay/${encodeURIComponent(referenceId)}`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
        'X-Target-Environment': targetEnv,
        'Ocp-Apim-Subscription-Key': subscriptionKey,
      },
    }
  );
  const data = await resp.json();
  return data;
}

module.exports = {
  baseUrlFor,
  isConfigured,
  getAccessToken,
  requestToPay,
  getTransactionStatus,
};
