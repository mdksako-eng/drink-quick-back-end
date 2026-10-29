// backend/utils/companyReadiness.js
// "Which companies can actually collect money through CamerPay, and what is the
// one next thing each of them needs?" — the platform owner's view.
//
// Pure: no database, no network. It only reshapes what
// utils/companyPaymentCredentials.js already decides (healthFor), so the
// per-company Settings card and this list can never disagree about a company.
//
// SECURITY: this module exists for a platform-admin surface, and it carries no
// secret material at all — not the token, not even the masked token, and NOT the
// webhook path. That path contains the company's opaque webhook token: a manager
// may copy it from its own Settings card, but a list across companies must not
// carry it. tests/company_readiness.test.js locks this down.

const credentials = require('./companyPaymentCredentials');

/** The one next thing a company needs, in the order it has to happen. */
const STEPS = {
  VAULT_KEY: 'set_vault_key',
  TOKEN: 'connect_token',
  WEBHOOK_SECRET: 'add_webhook_secret',
  READY: 'ready',
};

/**
 * The columns the admin query may read — what `healthFor` needs and nothing else.
 *
 * Note what is deliberately absent: `campay_webhook_token` (the opaque token in
 * the webhook URL) and the plaintext `campay_token` / `campay_webhook_secret`
 * columns. The token and secret are only ever read as ciphertext, to answer
 * "is one set?" — never to be returned.
 */
const COLUMNS = [
  'id',
  'name',
  'plan',
  'subscription_status',
  'campay_enabled',
  'campay_token_enc',
  'campay_webhook_secret_enc',
  'campay_connected_at',
];

/**
 * The single next action for a company, decided from its blockers.
 *
 * Order matters. A missing vault key is the platform's fault and blocks every
 * company at once, so it is reported before a company's own missing token; and a
 * token without a webhook secret cannot be trusted to confirm a payment, so it
 * comes last. Reporting "connect your account" to a company whose server cannot
 * store the account would just send someone in a circle.
 *
 * @param {{blockers?: string[]}} health from credentials.healthFor
 * @returns {string} one of STEPS
 */
function nextStepFor(health) {
  const blockers = (health && health.blockers) || [];
  if (blockers.includes('vault_key_missing')) return STEPS.VAULT_KEY;
  if (blockers.includes('no_token')) return STEPS.TOKEN;
  if (blockers.includes('no_webhook_secret')) return STEPS.WEBHOOK_SECRET;
  return STEPS.READY;
}

/**
 * One safe row for the admin list.
 *
 * @param {object} company row with (at least) COLUMNS
 * @param {{baseUrl?: string, accountDeclaredLive?: boolean}} [options]
 */
function rowFor(company, { baseUrl = '', accountDeclaredLive = false } = {}) {
  const health = credentials.healthFor(company, { baseUrl, accountDeclaredLive });
  return {
    id: company.id,
    name: company.name,
    plan: company.plan || null,
    subscriptionStatus: company.subscription_status || null,
    // Booleans only — the facts a decision needs, never the material.
    connected: health.connected,
    enabled: health.enabled,
    webhookSecretSet: health.webhookSecretSet,
    connectedAt: health.connectedAt || null,
    canCollect: health.canCollect,
    canVerifyWebhooks: health.canVerifyWebhooks,
    accountDeclaredLive: health.accountDeclaredLive,
    blockers: health.blockers,
    nextStep: nextStepFor(health),
  };
}

/** Totals for the header, so "6 companies, 0 ready" is one line. */
function summarize(rows) {
  const list = Array.isArray(rows) ? rows : [];
  const byStep = {};
  list.forEach((row) => {
    byStep[row.nextStep] = (byStep[row.nextStep] || 0) + 1;
  });
  const ready = list.filter((row) => row.nextStep === STEPS.READY).length;
  return { total: list.length, ready, blocked: list.length - ready, byStep };
}

/**
 * Platform-wide facts, reported ONCE rather than repeated on every company.
 *
 * `vaultReady` is the one blocker that is not a company's fault: without the
 * storage key nothing can be stored, so every company reports `set_vault_key` and
 * the fix is on the server (PAYMENT_CREDENTIALS_KEY). Reporting it here is what
 * makes "the key is set on Render" a checkable fact instead of an assumption —
 * the ops script prints it on the first line.
 */
function platformState() {
  return { vaultReady: credentials.vaultReady() };
}

module.exports = {
  STEPS,
  COLUMNS,
  nextStepFor,
  rowFor,
  summarize,
  platformState,
};
