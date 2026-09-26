// backend/routes/subscriptions.js
// Subscription (freemium) management + Flutterwave card payments.
const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { getSessionUser } = require('../middleware/sessionAuth');
const flutterwave = require('../utils/flutterwave');
const momo = require('../utils/momo');
const orangeMoney = require('../utils/orange_money');
const notchpay = require('../utils/notchpay');
const paymentChannels = require('../utils/paymentChannels');
const paymentGuard = require('../utils/paymentGuard');
const { rawBodyOf } = require('../utils/requestBody');

// Plan prices (XAF — Central African CFA franc). Overridable via env.
const PLAN_PRICES = {
  starter: {
    amount: parseInt(process.env.STARTER_PRICE_XAF || '5000', 10),
    currency: 'XAF',
    label: 'Starter',
  },
  pro: {
    amount: parseInt(process.env.PRO_PRICE_XAF || '15000', 10),
    currency: 'XAF',
    label: 'Pro',
  },
};

const SUBSCRIPTION_MONTHS = 1;
const VALID_PLANS = ['starter', 'pro'];

// Platform-level (YOUR) Mobile Money config for subscriptions.
// These env vars point to YOUR OWN MoMo account — NOT the company's — so
// subscription money is paid to you. Customer order payments (in
// payment.routes.js) still use the company's own account.
const platformMomo = {
  mtn_merchant_phone: process.env.PLATFORM_MTN_PHONE || '',
  orange_merchant_phone: process.env.PLATFORM_ORANGE_PHONE || '',
  mtn_merchant_id: process.env.PLATFORM_MTN_MERCHANT_ID || '',
  mtn_api_key: process.env.PLATFORM_MTN_API_KEY || '',
  mtn_secret_key: process.env.PLATFORM_MTN_SECRET_KEY || '',
  mtn_sandbox_mode: (process.env.PLATFORM_MTN_SANDBOX || 'true') === 'true',
  orange_merchant_id: process.env.PLATFORM_ORANGE_MERCHANT_ID || '',
  orange_api_key: process.env.PLATFORM_ORANGE_API_KEY || '',
  orange_secret_key: process.env.PLATFORM_ORANGE_SECRET_KEY || '',
};

// Resolves the authenticated user from the Bearer session token (DB-backed).
async function requireSessionUser(req) {
  const authHeader = req.headers.authorization;
  const token =
    authHeader && authHeader.startsWith('Bearer ')
      ? authHeader.split(' ')[1]
      : null;
  return getSessionUser(req.db, token);
}

function generateReference(companyId) {
  return `sub_${companyId}_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
}

// Shared helper: activate a plan for a company after a successful payment.
async function activateSubscription(
  db,
  { companyId, plan, provider, reference, transactionId, amount, currency }
) {
  const now = new Date();
  const endsAt = new Date(now.getTime() + SUBSCRIPTION_MONTHS * 30 * 24 * 60 * 60 * 1000);

  await db.query(
    `INSERT INTO subscriptions
       (company_id, plan, status, provider, reference, transaction_id, amount, currency, starts_at, ends_at)
     VALUES ($1, $2, 'active', $3, $4, $5, $6, $7, $8, $9)`,
    [companyId, plan, provider, reference, transactionId, amount, currency, now, endsAt]
  );

  await db.query(
    `UPDATE companies
       SET plan = $1, plan_expires_at = $2, subscription_status = 'active'
     WHERE id = $3`,
    [plan, endsAt, companyId]
  );

  return { plan, expiresAt: endsAt };
}

// ============================================================
// 📊 GET current subscription status
// ============================================================
router.get('/subscriptions/status', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    }
    if (!user.company_id) {
      return res.status(400).json({ success: false, error: 'No company' });
    }

    const result = await req.db.query(
      `SELECT plan, plan_expires_at, subscription_status FROM companies WHERE id = $1`,
      [user.company_id]
    );
    const company = result.rows[0];
    if (!company) {
      return res.status(404).json({ success: false, error: 'Company not found' });
    }

    let plan = company.plan || 'free';
    let status = company.subscription_status || 'none';
    let expiresAt = company.plan_expires_at;

    // Auto-expire.
    if (expiresAt && new Date(expiresAt) < new Date()) {
      plan = 'free';
      status = 'expired';
      await req.db.query(
        `UPDATE companies SET plan = 'free', subscription_status = 'expired' WHERE id = $1`,
        [user.company_id]
      );
      expiresAt = null;
    }

    res.json({
      success: true,
      data: {
        plan,
        status,
        expiresAt,
        prices: PLAN_PRICES,
      },
    });
  } catch (error) {
    console.error('GET /subscriptions/status error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

// ============================================================
// 💳 POST initiate payment (card via Flutterwave)
// ============================================================
router.post('/subscriptions/initiate', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    }
    if (!user.company_id) {
      return res.status(400).json({ success: false, error: 'No company' });
    }

    const { plan, provider = 'flutterwave' } = req.body || {};
    if (!VALID_PLANS.includes(plan)) {
      return res.status(400).json({ success: false, error: 'Invalid plan' });
    }

    if (provider !== 'flutterwave') {
      return res.status(400).json({
        success: false,
        error: 'Unsupported provider',
        message: 'Only card (flutterwave) is available for now.',
      });
    }

    if (!flutterwave.isConfigured()) {
      return res.status(503).json({
        success: false,
        error: 'Payment provider not configured',
      });
    }

    const price = PLAN_PRICES[plan];
    const reference = generateReference(user.company_id);
    const redirectUrl =
      process.env.FLUTTERWAVE_REDIRECT_URL ||
      `${process.env.APP_BASE_URL || 'http://localhost:3000'}/api/subscriptions/return`;

    const data = await flutterwave.initiatePayment({
      txRef: reference,
      amount: price.amount,
      currency: price.currency,
      email: user.email,
      name: user.username,
      phone: user.phone || '',
      redirectUrl,
      plan,
      companyId: user.company_id,
    });

    res.json({
      success: true,
      data: {
        reference,
        checkoutUrl: data.link || data.authorization_url || null,
        amount: price.amount,
        currency: price.currency,
        plan,
      },
    });
  } catch (error) {
    console.error('POST /subscriptions/initiate error:', error.message);
    res.status(500).json({ success: false, error: error.message || 'Internal server error' });
  }
});

// ============================================================
// 🔎 GET verify payment (called by the app after checkout)
// ============================================================
router.get('/subscriptions/verify', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    }

    const { transaction_id: transactionId, plan } = req.query;
    if (!transactionId || !VALID_PLANS.includes(plan)) {
      return res.status(400).json({ success: false, error: 'transaction_id and plan are required' });
    }

    const tx = await flutterwave.verifyTransaction(transactionId);
    if (!tx) {
      return res.status(404).json({ success: false, error: 'Transaction not found' });
    }

    if (String(tx.status).toLowerCase() !== 'successful') {
      return res.json({
        success: true,
        data: { active: false, status: tx.status },
      });
    }

    const amount = parseFloat(tx.amount) || PLAN_PRICES[plan].amount;
    const currency = tx.currency || PLAN_PRICES[plan].currency;
    const result = await activateSubscription(req.db, {
      companyId: user.company_id,
      plan,
      provider: 'flutterwave',
      reference: tx.tx_ref || null,
      transactionId: String(tx.id || transactionId),
      amount,
      currency,
    });

    res.json({
      success: true,
      data: { active: true, ...result },
    });
  } catch (error) {
    console.error('GET /subscriptions/verify error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

// ============================================================
// 🔔 POST webhook (Flutterwave server-to-server)
// ============================================================
router.post('/subscriptions/webhook', async (req, res) => {
  try {
    const signature = req.headers['verif-hash'];
    // Verify the HMAC against the bytes that were sent, not a re-serialisation.
    if (!flutterwave.verifyWebhookSignature(rawBodyOf(req), signature)) {
      console.warn('⚠️ Subscription webhook: invalid signature');
      return res.status(401).json({ success: false, error: 'Invalid signature' });
    }

    const { event, data } = req.body || {};
    if (event !== 'charge.completed' && data?.status !== 'successful') {
      return res.json({ success: true, ignored: true });
    }

    const meta = data?.meta || {};
    const companyId = parseInt(meta.companyId, 10);
    const plan = meta.plan;
    if (!companyId || !VALID_PLANS.includes(plan)) {
      return res.json({ success: true, ignored: true, reason: 'missing meta' });
    }

    const amount = parseFloat(data.amount) || PLAN_PRICES[plan].amount;
    const currency = data.currency || PLAN_PRICES[plan].currency;

    await activateSubscription(req.db, {
      companyId,
      plan,
      provider: 'flutterwave',
      reference: data.tx_ref || null,
      transactionId: String(data.id || data.flw_ref || ''),
      amount,
      currency,
    });

    console.log(`✅ Subscription activated via webhook for company ${companyId} (${plan})`);
    res.json({ success: true });
  } catch (error) {
    console.error('POST /subscriptions/webhook error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

// ============================================================
// 📲 POST initiate mobile-money payment (MTN / Orange)
// ============================================================
function validatePhone(phone, provider) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (provider === 'mtn') {
    return /^(237)?(6[5789]|68[0-9])\d{7}$/.test(digits);
  }
  if (provider === 'orange') {
    return /^(237)?(6[9]|69[0-9])\d{7}$/.test(digits);
  }
  return false;
}

router.post('/subscriptions/momo-initiate', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    }
    if (!user.company_id) {
      return res.status(400).json({ success: false, error: 'No company' });
    }

    const { plan, provider, customerPhone } = req.body || {};
    if (!VALID_PLANS.includes(plan)) {
      return res.status(400).json({ success: false, error: 'Invalid plan' });
    }
    if (!['mtn', 'orange'].includes(provider)) {
      return res.status(400).json({ success: false, error: 'Invalid provider (use mtn or orange)' });
    }
    if (!customerPhone || !validatePhone(customerPhone, provider)) {
      return res.status(400).json({ success: false, error: `Invalid ${provider} phone number` });
    }

    const price = PLAN_PRICES[plan];
    const reference = generateReference(user.company_id);
    const merchantPhone = provider === 'mtn'
        ? platformMomo.mtn_merchant_phone
        : platformMomo.orange_merchant_phone;

    // Auto mode: if YOUR platform MTN MoMo API credentials are configured,
    // send a real collection request to the customer's phone and verify
    // automatically (subscription money is paid to you, not the company).
    let transactionId = null;
    let paymentUrl = null;
    let auto = false;
    if (provider === 'mtn' && momo.isConfigured(platformMomo)) {
      transactionId = await momo.requestToPay({
        apiUser: platformMomo.mtn_merchant_id,
        apiKey: platformMomo.mtn_api_key,
        subscriptionKey: platformMomo.mtn_secret_key,
        sandbox: platformMomo.mtn_sandbox_mode,
        amount: price.amount,
        currency: price.currency,
        phone: customerPhone,
        externalId: reference,
      });
      auto = true;
    }

    // Auto mode: Orange Money web payment (YOUR platform credentials).
    if (provider === 'orange' && orangeMoney.isConfigured(platformMomo)) {
      try {
        const token = await orangeMoney.getAccessToken({
          clientId: platformMomo.orange_api_key,
          clientSecret: platformMomo.orange_secret_key,
        });
        const baseUrl =
            process.env.APP_BASE_URL || 'https://drink-quick-cal-kja1.onrender.com';
        const data = await orangeMoney.initiatePayment({
          accessToken: token,
          merchantKey: platformMomo.orange_merchant_id,
          amount: price.amount,
          currency: price.currency,
          orderId: reference,
          reference,
          returnUrl: `${baseUrl}/api/subscriptions/orange-return`,
          cancelUrl: `${baseUrl}/api/subscriptions/orange-return`,
          notifUrl: `${baseUrl}/api/subscriptions/orange-webhook`,
        });
        paymentUrl = data.payment_url || null;
        auto = true;
      } catch (e) {
        console.error('⚠️ Orange auto subscription failed, falling back to manual:', e.message);
      }
    }

    await req.db.query(
      `INSERT INTO subscriptions
         (company_id, plan, status, provider, reference, transaction_id, amount, currency)
       VALUES ($1, $2, 'pending', $3, $4, $5, $6, $7)`,
      [user.company_id, plan, provider, reference, transactionId, price.amount, price.currency]
    );

    res.json({
      success: true,
      data: {
        reference,
        transactionId,
        paymentUrl,
        auto,
        amount: price.amount,
        currency: price.currency,
        provider,
        merchantPhone: merchantPhone || '',
        customerPhone,
      },
    });
  } catch (error) {
    console.error('POST /subscriptions/momo-initiate error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

// ============================================================
// ✅ POST confirm mobile-money payment (PLATFORM verified — admin only)
// ============================================================
router.post('/subscriptions/momo-confirm', async (req, res) => {
  try {
    // Platform-only action: the paying manager must NOT be able to
    // self-confirm (otherwise they could subscribe without paying).
    // Requires the platform admin secret (ADMIN_PASSWORD env var).
    const adminSecret = req.headers['x-admin-secret'];
    const expectedSecret = process.env.ADMIN_PASSWORD || '';
    if (!expectedSecret || !adminSecret || adminSecret !== expectedSecret) {
      return res.status(403).json({ success: false, error: 'Manual payment requires platform verification' });
    }

    const { reference, plan } = req.body || {};
    if (!reference || !VALID_PLANS.includes(plan)) {
      return res.status(400).json({ success: false, error: 'reference and plan are required' });
    }

    const pending = await req.db.query(
      `SELECT id, company_id, plan FROM subscriptions
       WHERE reference = $1 AND status = 'pending'`,
      [reference]
    );
    if (pending.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Pending subscription not found' });
    }

    const sub = pending.rows[0];
    const now = new Date();
    const endsAt = new Date(now.getTime() + SUBSCRIPTION_MONTHS * 30 * 24 * 60 * 60 * 1000);

    await req.db.query(
      `UPDATE subscriptions SET status = 'active', starts_at = $1, ends_at = $2 WHERE id = $3`,
      [now, endsAt, sub.id]
    );
    await req.db.query(
      `UPDATE companies SET plan = $1, plan_expires_at = $2, subscription_status = 'active' WHERE id = $3`,
      [sub.plan, endsAt, sub.company_id]
    );

    res.json({ success: true, data: { active: true, plan: sub.plan, expiresAt: endsAt } });
  } catch (error) {
    console.error('POST /subscriptions/momo-confirm error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

// ============================================================
// 🔄 GET mobile-money payment status (auto-verify via MTN MoMo API)
// ============================================================
router.get('/subscriptions/momo-status', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    }

    const { reference } = req.query;
    if (!reference) {
      return res.status(400).json({ success: false, error: 'reference is required' });
    }

    const pending = await req.db.query(
      `SELECT id, plan, provider, reference, transaction_id, status FROM subscriptions
       WHERE reference = $1 AND company_id = $2 AND status = 'pending'`,
      [reference, user.company_id]
    );
    if (pending.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Pending subscription not found' });
    }
    const sub = pending.rows[0];

    // Only auto-verify MTN (Orange collection API can be added later).
    if (sub.provider !== 'mtn' || !sub.transaction_id) {
      return res.json({ success: true, data: { status: 'pending', auto: false } });
    }

    if (!momo.isConfigured(platformMomo)) {
      return res.json({ success: true, data: { status: 'pending', auto: false } });
    }

    const tx = await momo.getTransactionStatus({
      apiUser: platformMomo.mtn_merchant_id,
      apiKey: platformMomo.mtn_api_key,
      subscriptionKey: platformMomo.mtn_secret_key,
      sandbox: platformMomo.mtn_sandbox_mode,
      referenceId: sub.transaction_id,
    });

    const mtnStatus = String(tx.status || 'PENDING').toUpperCase();
    if (mtnStatus === 'SUCCESSFUL') {
      const now = new Date();
      const endsAt = new Date(now.getTime() + SUBSCRIPTION_MONTHS * 30 * 24 * 60 * 60 * 1000);
      await req.db.query(
        `UPDATE subscriptions SET status = 'active', starts_at = $1, ends_at = $2 WHERE id = $3`,
        [now, endsAt, sub.id]
      );
      await req.db.query(
        `UPDATE companies SET plan = $1, plan_expires_at = $2, subscription_status = 'active' WHERE id = $3`,
        [sub.plan, endsAt, user.company_id]
      );
      return res.json({ success: true, data: { active: true, plan: sub.plan, expiresAt: endsAt } });
    }

    if (mtnStatus === 'FAILED') {
      await req.db.query(`UPDATE subscriptions SET status = 'failed' WHERE id = $1`, [sub.id]);
      return res.json({ success: true, data: { active: false, status: 'failed' } });
    }

    return res.json({ success: true, data: { active: false, status: 'pending' } });
  } catch (error) {
    console.error('GET /subscriptions/momo-status error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

// ============================================================
// 🏁 GET return page (Flutterwave redirects here after card payment)
// ============================================================
router.get('/subscriptions/return', (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Payment Complete</title>
</head>
<body style="font-family:system-ui,sans-serif;background:#f7f8fa;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
  <div style="text-align:center;background:#fff;padding:40px;border-radius:12px;box-shadow:0 2px 20px rgba(0,0,0,0.08);max-width:420px;">
    <div style="font-size:48px;">✅</div>
    <h2 style="margin:16px 0 8px;">Payment received</h2>
    <p style="color:#555;margin:0 0 24px;">Your subscription is being activated. Return to the app and tap Refresh.</p>
  </div>
</body>
</html>`);
});

// ============================================================
// 🍊 Orange Money web payment (subscriptions): return + notif
// ============================================================
router.get('/subscriptions/orange-return', (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Payment Complete</title></head>
<body style="font-family:system-ui,sans-serif;background:#f7f8fa;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
  <div style="text-align:center;background:#fff;padding:40px;border-radius:12px;box-shadow:0 2px 20px rgba(0,0,0,0.08);max-width:420px;">
    <div style="font-size:48px;">✅</div>
    <h2 style="margin:16px 0 8px;">Payment received</h2>
    <p style="color:#555;margin:0 0 24px;">Return to the app — your subscription is being activated.</p>
  </div>
</body>
</html>`);
});

router.post('/subscriptions/orange-webhook', async (req, res) => {
  try {
    const { order_id, orderId, reference, status } = req.body || {};
    const ref = order_id || orderId || reference;
    if (!ref) {
      return res.json({ success: false, error: 'Missing order_id' });
    }

    const st = String(status || '').toUpperCase();
    const pending = await req.db.query(
      `SELECT id, plan, company_id FROM subscriptions WHERE reference = $1 AND status = 'pending'`,
      [ref]
    );
    if (pending.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Pending subscription not found' });
    }
    const sub = pending.rows[0];

    if (st === 'SUCCESS' || st === 'SUCCESSFUL' || st === 'COMPLETED') {
      const now = new Date();
      const endsAt = new Date(now.getTime() + SUBSCRIPTION_MONTHS * 30 * 24 * 60 * 60 * 1000);
      await req.db.query(
        `UPDATE subscriptions SET status = 'active', starts_at = $1, ends_at = $2 WHERE id = $3`,
        [now, endsAt, sub.id]
      );
      await req.db.query(
        `UPDATE companies SET plan = $1, plan_expires_at = $2, subscription_status = 'active' WHERE id = $3`,
        [sub.plan, endsAt, sub.company_id]
      );
      console.log(`✅ Orange subscription activated for company ${sub.company_id} (${sub.plan})`);
    } else if (st === 'FAILED' || st === 'CANCELLED' || st === 'EXPIRED') {
      await req.db.query(`UPDATE subscriptions SET status = 'failed' WHERE id = $1`, [sub.id]);
    }

    res.json({ success: true });
  } catch (error) {
    console.error('Orange subscription webhook error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🟢 NOTCH PAY (subscription — unified MoMo/OM/card via one API)
// Money is paid to YOU (platform). Configured via NOTCHPAY_* env vars.
// ============================================================

// Which rails the account can charge changes only when Notch Pay is
// reconfigured, yet the app asks on every upgrade tap — so cache it briefly.
const CHANNELS_TTL_MS = 5 * 60 * 1000;
let channelsCache = { at: 0, channels: [] };

/**
 * The Notch Pay channels this account can charge right now.
 * Never throws: a failed lookup means "we don't know", which callers treat as
 * "leave every rail enabled" rather than hiding a rail that may well work.
 * @returns {Promise<Array>} [] when unknown
 */
async function loadChannels({ force = false } = {}) {
  const fresh = channelsCache.channels.length > 0
    && Date.now() - channelsCache.at < CHANNELS_TTL_MS;
  if (!force && fresh) return channelsCache.channels;
  if (!notchpay.isConfigured()) return channelsCache.channels;

  try {
    const items = await notchpay.listChannels({ country: 'CM' });
    if (Array.isArray(items)) channelsCache = { at: Date.now(), channels: items };
  } catch (error) {
    console.warn('⚠️ Notch Pay channels lookup failed:', error.message);
  }
  return channelsCache.channels;
}

/** The account's card channel slug, or '' when it has none / we cannot tell. */
async function cardSlugFromAccount() {
  return paymentChannels.findCardSlug(await loadChannels());
}

/**
 * Activate the pending subscription behind a reference.
 *
 * `payment` carries what the provider says was paid (from the webhook). It is
 * checked against the amount we asked for before a month is handed over — see
 * utils/paymentGuard.js. The polling path calls Notch Pay's own API with the
 * platform key, so it has no amount to check and passes none.
 *
 * @returns {Promise<{activated: boolean, plan?: string, expiresAt?: Date, reason?: string}>}
 */
async function activatePendingSubscription(db, reference, companyId, payment = {}) {
  const pending = await db.query(
    `SELECT id, plan, company_id, amount, currency FROM subscriptions WHERE reference = $1 AND status = 'pending'`,
    [reference]
  );
  if (pending.rows.length === 0) return { activated: false, reason: 'no pending subscription' };
  const sub = pending.rows[0];
  if (companyId && sub.company_id !== companyId) {
    return { activated: false, reason: 'no pending subscription' };
  }

  const guard = paymentGuard.paidAmountMatches({
    paidAmount: payment.amount,
    paidCurrency: payment.currency,
    expectedAmount: sub.amount,
    expectedCurrency: sub.currency,
  });
  if (!guard.ok) {
    if (paymentGuard.shouldEnforce()) {
      console.warn(
        `⚠️ Notch Pay ${reference}: ${guard.reason} (paid ${guard.paid} / expected ${guard.expected}) — subscription NOT activated`
      );
      return { activated: false, reason: guard.reason };
    }
    console.warn(
      `⚠️ Notch Pay ${reference}: ${guard.reason} (paid ${guard.paid} / expected ${guard.expected}) — allowed because NOTCHPAY_ALLOW_UNDERPAYMENT=true`
    );
  }

  const now = new Date();
  const endsAt = new Date(now.getTime() + SUBSCRIPTION_MONTHS * 30 * 24 * 60 * 60 * 1000);
  await db.query(
    `UPDATE subscriptions SET status = 'active', starts_at = $1, ends_at = $2 WHERE id = $3`,
    [now, endsAt, sub.id]
  );
  await db.query(
    `UPDATE companies SET plan = $1, plan_expires_at = $2, subscription_status = 'active' WHERE id = $3`,
    [sub.plan, endsAt, sub.company_id]
  );
  return { activated: true, plan: sub.plan, expiresAt: endsAt };
}

router.post('/subscriptions/notchpay-initiate', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    if (!user.company_id) return res.status(400).json({ success: false, error: 'No company' });

    // channel: 'card' | 'mtn' | 'orange' (or a raw slug such as 'cm.mtn').
    // 'card' locks to the account's card channel when it has one, and otherwise
    // opens the checkout page where card is one of the choices.
    const { plan, channel } = req.body || {};
    if (!VALID_PLANS.includes(plan)) return res.status(400).json({ success: false, error: 'Invalid plan' });
    if (!notchpay.isConfigured()) return res.status(503).json({ success: false, error: 'Notch Pay not configured' });

    const resolved = paymentChannels.resolveChannel(channel, {
      cardSlug: await cardSlugFromAccount(),
    });
    if (!resolved) {
      return res.status(400).json({
        success: false,
        error: `Unsupported payment channel. Use one of: ${paymentChannels.PROVIDERS.join(', ')}.`,
      });
    }

    const price = PLAN_PRICES[plan];
    const reference = generateReference(user.company_id);
    const baseUrl = process.env.APP_BASE_URL || 'http://localhost:3000';

    const data = await notchpay.initiatePayment({
      amount: price.amount,
      currency: price.currency,
      email: user.email || undefined,
      reference,
      channel: resolved.slug || undefined,
      // A locked channel must lock its country too, or Notch Pay rejects it.
      country: resolved.lockCountry || undefined,
      description: `Drink Quick Cal ${plan} subscription`,
      callback: `${baseUrl}/api/subscriptions/notchpay-return`,
    });

    await req.db.query(
      `INSERT INTO subscriptions (company_id, plan, status, provider, reference, transaction_id, amount, currency)
       VALUES ($1, $2, 'pending', 'notchpay', $3, $4, $5, $6)`,
      [user.company_id, plan, reference, data.transaction || null, price.amount, price.currency]
    );

    res.json({
      success: true,
      data: {
        reference,
        transactionId: data.transaction || null,
        checkoutUrl: data.authorizationUrl || null,
        auto: Boolean(data.authorizationUrl),
        amount: price.amount,
        currency: price.currency,
        provider: 'notchpay',
        rail: resolved.provider,
        channel: resolved.slug || null,
      },
    });
  } catch (error) {
    console.error('POST /subscriptions/notchpay-initiate error:', error.message);
    res.status(500).json({ success: false, error: error.message || 'Internal server error' });
  }
});

router.get('/subscriptions/notchpay-status', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    const { reference } = req.query;
    if (!reference) return res.status(400).json({ success: false, error: 'reference is required' });

    const pending = await req.db.query(
      `SELECT status FROM subscriptions WHERE reference = $1 AND company_id = $2 AND status = 'pending'`,
      [reference, user.company_id]
    );
    if (pending.rows.length === 0) return res.status(404).json({ success: false, error: 'Pending subscription not found' });

    const status = await notchpay.getPaymentStatus(reference);
    if (status === 'completed') {
      const result = await activatePendingSubscription(req.db, reference, user.company_id);
      if (result.activated) {
        return res.json({
          success: true,
          data: { active: true, plan: result.plan, expiresAt: result.expiresAt },
        });
      }
    }
    if (status === 'failed' || status === 'expired' || status === 'cancelled') {
      await req.db.query(
        `UPDATE subscriptions SET status = 'failed' WHERE reference = $1 AND status = 'pending'`,
        [reference]
      );
      return res.json({ success: true, data: { active: false, status: 'failed' } });
    }
    return res.json({ success: true, data: { active: false, status: 'pending' } });
  } catch (error) {
    console.error('GET /subscriptions/notchpay-status error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

router.post('/subscriptions/notchpay-webhook', async (req, res) => {
  try {
    const signature = req.headers['x-notch-signature'];
    // The HMAC covers the exact bytes Notch Pay sent, so verify against the raw
    // body Express captured (falling back to a re-serialisation).
    const rawBody = rawBodyOf(req);
    if (!notchpay.verifyWebhookSignature(rawBody, signature)) {
      console.warn('⚠️ Subscription Notch Pay webhook: invalid signature');
      return res.status(401).json({ success: false, error: 'Invalid signature' });
    }

    // Notch Pay payloads wrap the transaction; be defensive about shape.
    // NOTE: field names should be cross-checked against a live webhook sample.
    const body = req.body || {};
    const data = body.data || body.transaction || {};
    const reference =
      body.reference ||
      (data && typeof data === 'object' ? data.reference : null) ||
      (typeof body.transaction === 'string' ? body.transaction : null);
    if (!reference) {
      return res.json({ success: true, ignored: true, reason: 'missing reference' });
    }

    const status = notchpay.normalizeStatus(
      body.status || (data && data.status) || (data && data.state) || body.event
    );

    if (status === 'completed') {
      const result = await activatePendingSubscription(req.db, reference, null, {
        amount: body.amount ?? (data && data.amount),
        currency: body.currency ?? (data && data.currency),
      });
      if (result.activated) {
        console.log(`✅ Notch Pay subscription activated (${result.plan})`);
        return res.json({ success: true });
      }
      return res.json({ success: true, ignored: true, reason: result.reason || 'no pending subscription' });
    }
    if (status === 'failed' || status === 'expired' || status === 'cancelled') {
      await req.db.query(
        `UPDATE subscriptions SET status = 'failed' WHERE reference = $1 AND status = 'pending'`,
        [reference]
      );
    }
    return res.json({ success: true, ignored: true });
  } catch (error) {
    console.error('POST /subscriptions/notchpay-webhook error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

router.get('/subscriptions/notchpay-return', (req, res) => {
  res.send('<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Payment Complete</title></head><body style="font-family:system-ui,sans-serif;background:#f7f8fa;display:flex;align-items:center;justify-content:center;height:100vh;margin:0"><div style="text-align:center;background:#fff;padding:40px;border-radius:12px;box-shadow:0 2px 20px rgba(0,0,0,0.08);max-width:420px"><div style="font-size:48px">✅</div><h2 style="margin:16px 0 8px">Payment received</h2><p style="color:#555;margin:0 0 24px">Your subscription is being activated. Return to the app and tap Refresh.</p></div></body></html>');
});

//  Payment readiness (no secrets) — confirms whether subscriptions can take
// REAL money: Notch Pay (platform account) in live mode and/or direct operator
// credentials in live (non-sandbox) mode.
router.get('/subscriptions/notchpay/health', (req, res) => {
  const notch = notchpay.status();
  res.json({
    success: true,
    notchpayConfigured: notchpay.isConfigured(),
    ...notch,
    //  'live' means real money will be collected from customers.
    notchpayMode: notch.mode,
    // The rails the platform sells on: card, MTN MoMo, Orange Money.
    rails: paymentChannels.PROVIDERS,
    platformMomo: {
      mtnConfigured: momo.isConfigured(platformMomo),
      orangeConfigured: orangeMoney.isConfigured(platformMomo),
      mtnMode: platformMomo.mtn_sandbox_mode ? 'sandbox' : 'live',
      mtnMerchantPhoneSet: Boolean(platformMomo.mtn_merchant_phone),
      orangeMerchantPhoneSet: Boolean(platformMomo.orange_merchant_phone),
    },
    // ✅ True when at least one LIVE path is ready for real subscriptions.
    liveReady: notch.mode === 'live'
      || (!platformMomo.mtn_sandbox_mode && platformMomo.mtn_merchant_phone),
    hint: notch.mode === 'live'
      ? 'Live Notch Pay keys detected — subscription payments are real.'
      : 'Set NOTCHPAY_PUBLIC_KEY/PRIVATE_KEY to your pk_live_/sk_live_ keys (and PLATFORM_MTN_SANDBOX=false for direct MoMo) to take live payments.',
  });
});

// 🔎 Which rails can be charged right now (card / MTN / Orange). The app reads
// this before showing the upgrade options, so a rail the account cannot charge
// is never presented as if it works. `known:false` means we could not ask (the
// app then leaves every rail enabled instead of hiding a working one).
router.get('/subscriptions/notchpay-channels', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) return res.status(401).json({ success: false, error: 'Invalid or expired session' });

    const channels = await loadChannels({ force: req.query.refresh === '1' });
    const supported = paymentChannels.summarizeChannels(channels);
    const known = channels.length > 0;

    res.json({
      success: true,
      data: {
        notchpayConfigured: notchpay.isConfigured(),
        mode: notchpay.status().mode,
        known,
        rails: paymentChannels.PROVIDERS,
        supported: known
          ? { card: supported.card, mtn: supported.mtn, orange: supported.orange }
          : null,
        channels: known ? supported.slugs : [],
        cardChannel: paymentChannels.findCardSlug(channels) || null,
      },
    });
  } catch (error) {
    console.error('GET /subscriptions/notchpay-channels error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

module.exports = router;
