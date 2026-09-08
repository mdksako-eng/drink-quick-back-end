// backend/routes/subscriptions.js
// Subscription (freemium) management + Flutterwave card payments.
const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { getSessionUser } = require('../middleware/sessionAuth');
const flutterwave = require('../utils/flutterwave');

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
    if (!flutterwave.verifyWebhookSignature(JSON.stringify(req.body), signature)) {
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

module.exports = router;
