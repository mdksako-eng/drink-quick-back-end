// backend/utils/campay.js
// Thin wrapper around the CamerPay API (Mobile Money, cards via Stripe, PayPal).
//
// Docs: https://camerpay.biz/docs  ·  Base: https://camerpay.biz/api
// One merchant account = one Bearer token, generated in that merchant's own
// dashboard (/client/api). Calling code passes the token per request, so the
// same functions serve the platform account (subscriptions) and a company
// account (that bar's own customers) without leaking one into the other.
//
// IMPORTANT — test vs live cannot be read from the token. CamerPay's own docs:
// "Le même token fonctionne dans les deux modes — c'est le compte qui détermine
// le comportement." A sandbox account simulates every call. The only trustworthy
// signal is `is_sandbox` on GET /payment/{uuid}/status, which is why plan
// activation goes through isVerifiablePaidTransaction() and never through a
// webhook body alone.
//
// Secrets live in env vars / the per-company vault only — never in the app.
const crypto = require('crypto');
const { providerAmountLimits } = require('./paymentFees');

const CAMPAY_BASE_URL =
  process.env.CAMERPAY_BASE_URL || 'https://camerpay.biz/api';

// Platform (our own) subscription account. Per-company tokens come from the
// companies table through utils/credentialVault.js.
const PLATFORM_TOKEN = process.env.CAMERPAY_TOKEN || '';
const PLATFORM_WEBHOOK_SECRET = process.env.CAMERPAY_WEBHOOK_SECRET || '';
const SOURCE_TAG = process.env.CAMERPAY_SOURCE || 'drinkquickcal';
const DEFAULT_TIMEOUT_MS = Number(process.env.CAMERPAY_TIMEOUT_MS || 30000);

/** Payment methods CamerPay accepts in `payment_method`. */
const METHODS = ['orange_money', 'mtn_momo', 'stripe', 'paypal'];

/** Statuses CamerPay documents for a transaction. */
const STATUSES = ['pending', 'processing', 'completed', 'failed', 'cancelled', 'refunded'];

/**
 * failure_code → who is at fault. Mirrors the table published at
 * https://camerpay.biz/docs/webhooks so the app can say "try another number"
 * (payer) instead of "wait for the operator" (provider).
 */
const FAILURE_SIDE = {
  '60019': 'payer', '60020': 'payer', '60021': 'payer', '60022': 'payer',
  '60024': 'payer', '60030': 'provider',
  USER_NOT_REGISTERED: 'payer',
  INVALID_MSISDN: 'payer',
  LOW_BALANCE_OR_PAYEE_LIMIT_REACHED_OR_NOT_ALLOWED: 'payer',
  WAITING_FOR_CUSTOMER_APPROVAL_TIMEOUT: 'payer',
  USER_CANCELED_PAYMENT: 'payer',
  SENDER_ACCOUNT_NOT_ACTIVE: 'payer',
  PAYER_NOT_FOUND: 'payer',
  EXPIRED: 'provider',
  COULD_NOT_PERFORM_TRANSACTION: 'provider',
  INTERNAL_ERROR: 'provider',
  insufficient_funds: 'payer',
  card_declined: 'payer',
  user_cancelled: 'payer',
  PROVIDER_INIT_ERROR: 'provider',
  abandoned_no_payment: 'payer',
};

/**
 * Error carrying the HTTP status, CamerPay's machine-readable `error` code and
 * the raw payload, so a route can map 402 (KYC/plan quota) to the upgrade
 * message and 422 (validation) to the offending field.
 */
class CampayError extends Error {
  constructor(message, { status = 0, code = null, payload = null } = {}) {
    super(message);
    this.name = 'CampayError';
    this.status = status;
    this.code = code;
    this.payload = payload;
  }
}

function isConfigured() {
  return Boolean(PLATFORM_TOKEN);
}

/**
 * The platform account's configuration, for /health and startup logging.
 * `modeVerifiable: false` is deliberate — see the header comment.
 */
function status() {
  return {
    tokenSet: Boolean(PLATFORM_TOKEN),
    webhookSecretSet: Boolean(PLATFORM_WEBHOOK_SECRET),
    mode: keyMode(),
    modeVerifiable: canVerifyKeyMode(),
    baseUrl: CAMPAY_BASE_URL,
  };
}

/**
 * CamerPay exposes no key prefix to read the mode from, unlike Notch Pay.
 * @returns {'account'}
 */
function keyMode() {
  return 'account';
}

/**
 * @returns {boolean} false — the token never proves test or live. Callers must
 * use the transaction's `is_sandbox` flag instead (see isVerifiablePaidTransaction).
 */
function canVerifyKeyMode() {
  return false;
}

/** True only when a per-company token is present and usable. */
function hasToken(token) {
  return Boolean(String(token || '').trim());
}

/** True when a merchant can actually be charged right now. */
function isLive() {
  return false; // unknowable from a token; kept for interface parity
}
/**
 * Normalise a Cameroonian number to the digits CamerPay shows in its examples
 * (237XXXXXXXXX, no spaces, no plus). Accepts "+237 6XX XX XX XX", "6XXXXXXXX"
 * and "2376XXXXXXXX".
 */
function normalizePhone(phone) {
  const digits = String(phone || '').replace(/[^\d]/g, '');
  if (!digits) return '';
  if (digits.startsWith('237')) return digits;
  if (digits.length === 9) return `237${digits}`;
  return digits;
}

/** Our reference → CamerPay's merchant_invoice_id (documented max: 100 chars). */
function invoiceId(reference) {
  return String(reference || '').slice(0, 100);
}

/** An https URL, required by CamerPay for callbacks (it blocks internal URLs). */
function isHttpsUrl(value) {
  try {
    return new URL(String(value)).protocol === 'https:';
  } catch (e) {
    return false;
  }
}

/**
 * Shared HTTP call. Bearer auth, hard timeout, typed errors (401 auth, 402 KYC
 * or plan quota, 422 validation, 429 rate limit, 5xx provider).
 * @returns {Promise<{data: object, httpStatus: number}>}
 */
async function callApi(path, {
  method = 'GET',
  token,
  body,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  fetchImpl = fetch,
} = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let response;
  try {
    response = await fetchImpl(`${CAMPAY_BASE_URL}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${String(token || PLATFORM_TOKEN || '')}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });
  } catch (error) {
    throw new CampayError(`CamerPay request failed: ${error.message}`, {
      status: 0,
      code: 'network_error',
    });
  } finally {
    clearTimeout(timer);
  }

  const data = await response.json().catch(() => ({}));
  if (!response.ok || (typeof data.code === 'number' && data.code >= 400)) {
    throw new CampayError(
      data.message || data.error || `CamerPay HTTP ${response.status}`,
      { status: response.status, code: data.error || data.code || null, payload: data }
    );
  }
  return { data, httpStatus: response.status };
}

/**
 * Start a payment and get back the hosted payment page. Amounts are whole XAF
 * (CamerPay validates per-method limits and answers 422 when out of range).
 *
 * @param {object} params token, amount, currency, paymentMethod, customerPhone,
 *   customerEmail, customerName, merchantInvoiceId, callbackUrl, returnUrl,
 *   source, idempotencyKey, timeoutMs, fetchImpl
 * @returns {Promise<{httpStatus, success, transactionUuid, status, payUrl,
 *   redirectUrl, replayed}>} replayed=true on HTTP 200 (a live key was reused)
 */
async function initiatePayment({
  token,
  amount,
  currency = 'XAF',
  paymentMethod,
  customerPhone,
  customerEmail,
  customerName,
  merchantInvoiceId,
  callbackUrl,
  returnUrl,
  source,
  idempotencyKey,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  fetchImpl = fetch,
} = {}) {
  const value = Number(amount);
  if (!Number.isFinite(value) || value <= 0) {
    throw new CampayError('CamerPay amount must be a positive number', {
      status: 422, code: 'validation_error',
    });
  }
  const amountXaf = Math.round(value);
  if (String(currency).toUpperCase() !== 'XAF') {
    throw new CampayError('CamerPay only accepts XAF', {
      status: 422, code: 'validation_error',
    });
  }
  if (paymentMethod && !METHODS.includes(paymentMethod)) {
    throw new CampayError(`Unsupported CamerPay payment method: ${paymentMethod}`, {
      status: 422, code: 'validation_error',
    });
  }
  if (!merchantInvoiceId) {
    throw new CampayError('merchant_invoice_id is required', {
      status: 422, code: 'validation_error',
    });
  }
  if (!isHttpsUrl(callbackUrl) || !isHttpsUrl(returnUrl)) {
    throw new CampayError('CamerPay requires https callback and return URLs', {
      status: 422, code: 'validation_error',
    });
  }
  const limit = paymentMethod ? providerAmountLimits(paymentMethod) : null;
  if (limit && (amountXaf < limit.min || amountXaf > limit.max)) {
    throw new CampayError(
      `Amount ${amountXaf} XAF is outside ${paymentMethod} limits (${limit.min}-${limit.max})`,
      { status: 422, code: 'amount_out_of_range' }
    );
  }

  const body = {
    amount: amountXaf,
    currency: 'XAF',
    merchant_invoice_id: invoiceId(merchantInvoiceId),
    merchant_callback_url: callbackUrl,
    merchant_return_url: returnUrl,
    source: String(source || SOURCE_TAG).slice(0, 40),
  };
  if (paymentMethod) body.payment_method = paymentMethod;
  const phone = normalizePhone(customerPhone);
  if (phone) body.customer_phone = phone;
  if (customerEmail) body.customer_email = customerEmail;
  if (customerName) body.customer_name = customerName;
  // Documented idempotence: an active key returns the existing transaction (200,
  // no duplicate). Reuse after failed/cancelled is NOT guaranteed — callers must
  // create a fresh reference rather than replay a dead one.
  body.idempotency_key = String(idempotencyKey || merchantInvoiceId).slice(0, 100);

  const { data, httpStatus } = await callApi('/payment/initiate', {
    method: 'POST', token, body, timeoutMs, fetchImpl,
  });

  return {
    httpStatus,
    success: data.success !== false,
    transactionUuid: data.transaction_uuid || '',
    status: normalizeStatus(data.status),
    payUrl: data.pay_url || '',
    redirectUrl: data.redirect_url || data.pay_url || '',
    replayed: httpStatus === 200,
  };
}
/**
 * Current state of a transaction. This is the only place `is_sandbox` is
 * available, and therefore the only trustworthy source for "was this real
 * money?".
 * @returns {Promise<object|null>} normalised transaction, or null when unknown
 */
async function getPaymentStatus(uuid, {
  token,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  fetchImpl = fetch,
} = {}) {
  if (!uuid) return null;
  const { data } = await callApi(`/payment/${encodeURIComponent(uuid)}/status`, {
    method: 'GET', token, timeoutMs, fetchImpl,
  });
  const tx = data.transaction || data.data;
  if (!tx || typeof tx !== 'object') return null;
  return {
    uuid: tx.uuid || uuid,
    status: normalizeStatus(tx.status),
    rawStatus: tx.status || '',
    amount: tx.amount != null ? Number(tx.amount) : null,
    currency: tx.currency || 'XAF',
    paymentMethod: tx.payment_method || '',
    customerPhone: tx.customer_phone || '',
    merchantInvoiceId: tx.merchant_invoice_id || '',
    isSandbox: tx.is_sandbox === true,
    paidAt: tx.paid_at || null,
    createdAt: tx.created_at || null,
  };
}

/**
 * The plan-activation gate: completed AND confirmed to be real money.
 *
 * A sandbox account simulates payments, and the same token serves both modes, so
 * "completed" alone would hand out a paid plan for a simulated payment. Sandbox
 * payments never count towards KYC volume either, so they are not income.
 *
 * @param {object} tx transaction from getPaymentStatus()
 * @returns {boolean}
 */
function isVerifiablePaidTransaction(tx) {
  if (!tx || typeof tx !== 'object') return false;
  if (normalizeStatus(tx.status) !== 'completed') return false;
  return tx.isSandbox === false || tx.is_sandbox === false;
}

/** Map a CamerPay status onto our canonical set. Unknown values stay pending. */
function normalizeStatus(status) {
  const s = String(status || '').toLowerCase();
  if (['completed', 'complete', 'success', 'successful', 'succeeded', 'paid'].includes(s)) {
    return 'completed';
  }
  if (['pending', 'processing', 'initiated', 'accepted', 'created'].includes(s)) {
    return 'pending';
  }
  if (['failed', 'fail', 'rejected', 'error', 'declined'].includes(s)) return 'failed';
  if (['cancelled', 'canceled', 'cancel', 'expired', 'abandoned'].includes(s)) return 'cancelled';
  if (['refunded', 'refund'].includes(s)) return 'refunded';
  return 'pending';
}

/**
 * Parse CamerPay's webhook body. It is `application/x-www-form-urlencoded`,
 * NOT JSON — parsing it as JSON yields an empty object, which the docs call out
 * as one of the five most common integration failures.
 * @param {string|Buffer} rawBody
 * @returns {object} fields, e.g. { uuid, invoice_id, status, amount, signature }
 */
function parseWebhookBody(rawBody) {
  const text = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody || '');
  const params = new URLSearchParams(text);
  const out = {};
  for (const [key, value] of params.entries()) out[key] = value;
  return out;
}

/** The webhook fields that are signed, in CamerPay's documented order. */
function canonicalPayload(fields) {
  const { signature, ...rest } = fields || {};
  return Object.keys(rest).sort().map((k) => `${k}=${rest[k]}`).join('&');
}
/** Constant-time string compare that never throws on length mismatch. */
function timingSafeEquals(a, b) {
  const left = Buffer.from(String(a || ''), 'utf8');
  const right = Buffer.from(String(b || ''), 'utf8');
  if (left.length !== right.length || left.length === 0) return false;
  return crypto.timingSafeEqual(left, right);
}

/** The raw form body with its own `signature` parameter removed. */
function stripSignatureParam(rawBody) {
  const text = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody || '');
  return text.split('&').filter((part) => !/^signature=/.test(part)).join('&');
}

function hmacHex(secret, value) {
  return crypto.createHmac('sha256', String(secret)).update(value).digest('hex');
}

/**
 * Which recipe produced this signature, or null when none matches.
 *
 * CamerPay publishes the raw-body recipe (`/docs/examples`): "utilisez le corps
 * brut, pas un JSON re-sérialisé". Its transaction webhook is form-encoded with
 * the signature included in the body, so two derived candidates are also tried;
 * keeping them explicit means the first captured sandbox webhook can pin the
 * answer for good instead of us guessing it into production.
 *
 * @returns {'raw'|'without_signature'|'sorted_fields'|null}
 */
function matchSignatureMode(rawBody, signature, secret) {
  if (!secret || !signature) return null;
  const received = String(signature).trim().toLowerCase();
  const candidates = [
    ['raw', hmacHex(secret, Buffer.isBuffer(rawBody) ? rawBody : String(rawBody || ''))],
    ['without_signature', hmacHex(secret, stripSignatureParam(rawBody))],
    ['sorted_fields', hmacHex(secret, canonicalPayload(parseWebhookBody(rawBody)))],
  ];
  for (const [mode, expected] of candidates) {
    if (timingSafeEquals(expected, received)) return mode;
  }
  return null;
}

/**
 * Verify a webhook signature (HMAC-SHA256 hex, header `X-CamerPay-Signature`,
 * also repeated as the body's `signature` field — the two are identical).
 * @param {string|Buffer} rawBody the bytes as received, never re-serialised
 * @param {string} signature header or body value
 * @param {string} [secret] per-company secret, or the platform secret
 * @param {'auto'|'raw'|'without_signature'|'sorted_fields'} [mode]
 * @returns {boolean}
 */
function verifyWebhookSignature(rawBody, signature, secret, mode = 'auto') {
  const useSecret = secret || PLATFORM_WEBHOOK_SECRET;
  if (!useSecret || !signature) return false;
  if (mode && mode !== 'auto') {
    const value = mode === 'raw'
      ? Buffer.isBuffer(rawBody) ? rawBody : String(rawBody || '')
      : mode === 'without_signature'
        ? stripSignatureParam(rawBody)
        : canonicalPayload(parseWebhookBody(rawBody));
    return timingSafeEquals(hmacHex(useSecret, value), String(signature).trim().toLowerCase());
  }
  return matchSignatureMode(rawBody, signature, useSecret) !== null;
}

/**
 * Refund a completed transaction. CamerPay's API documents FULL refunds only
 * (partial refunds appear in the PHP SDK) — pass `amount` only if the account
 * supports it, and expect a `refunded` webhook afterwards.
 */
async function refundPayment(uuid, {
  reason,
  amount,
  token,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  fetchImpl = fetch,
} = {}) {
  if (!uuid) {
    throw new CampayError('CamerPay refund needs a transaction uuid', {
      status: 422, code: 'validation_error',
    });
  }
  const body = {};
  if (reason) body.reason = String(reason).slice(0, 255);
  if (amount != null) body.amount = Math.round(Number(amount));
  const { data, httpStatus } = await callApi(
    `/payment/${encodeURIComponent(uuid)}/refund`,
    { method: 'POST', token, body, timeoutMs, fetchImpl }
  );
  return { httpStatus, success: data.success !== false, refund: data };
}

/**
 * Who is at fault for a failure, so the app can tell a customer to retry with
 * another number (payer) instead of waiting for the operator (provider).
 * @returns {'payer'|'provider'|'unknown'}
 */
function classifyFailure(code) {
  const key = String(code == null ? '' : code).trim();
  return FAILURE_SIDE[key] || 'unknown';
}

module.exports = {
  METHODS,
  STATUSES,
  CampayError,
  isConfigured,
  status,
  keyMode,
  canVerifyKeyMode,
  isLive,
  hasToken,
  normalizePhone,
  invoiceId,
  isHttpsUrl,
  initiatePayment,
  getPaymentStatus,
  isVerifiablePaidTransaction,
  normalizeStatus,
  parseWebhookBody,
  canonicalPayload,
  verifyWebhookSignature,
  matchSignatureMode,
  refundPayment,
  classifyFailure,
  timingSafeEquals,
};



