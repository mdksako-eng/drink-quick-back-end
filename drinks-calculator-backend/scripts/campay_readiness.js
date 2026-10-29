#!/usr/bin/env node
// scripts/campay_readiness.js
// "Which of my companies can actually take electronic payments, and what is the
// one next thing each of them needs?" — the same list the admin panel would show.
//
// Usage (the platform admin password is read from the ENVIRONMENT on purpose: an
// argument would end up in the shell history and in the process list):
//   ADMIN_PASSWORD=<platform admin password> node scripts/campay_readiness.js
//   ADMIN_PASSWORD=... node scripts/campay_readiness.js https://my-service.onrender.com
//
// Exit code 0 = every company is ready; 1 = something still blocks collection, or
// the backend was unreachable. That makes it usable as an ops check after a deploy.
//
// It never prints a token, a secret or a webhook URL: the endpoint it calls does
// not carry them either (see utils/companyReadiness.js).
const BASE = (process.argv[2] || 'https://drink-quick-cal-kja1.onrender.com')
  .replace(/\/$/, '');
const PASSWORD = (process.env.ADMIN_PASSWORD || '').trim();

/** What each next step means in words, so the output is actionable. */
const STEPS = {
  set_vault_key:
    'the SERVER needs PAYMENT_CREDENTIALS_KEY (nothing can connect until it exists)',
  connect_token:
    'the company adds its CamerPay token: Settings > Business Payment Settings',
  add_webhook_secret:
    'the company pastes its CamerPay webhook secret (payments cannot be confirmed without it)',
  ready: 'nothing - ready to collect',
};

(async () => {
  if (!PASSWORD) {
    console.error('Set ADMIN_PASSWORD (the platform admin password) in the environment.');
    process.exitCode = 1;
    return;
  }

  let data = null;
  try {
    const res = await fetch(`${BASE}/api/admin/campay-readiness`, {
      headers: { Accept: 'application/json', Authorization: `Bearer ${PASSWORD}` },
    });
    const body = await res.json().catch(() => ({}));
    if (res.status === 401 || res.status === 403) {
      console.error('The admin password was refused. Is ADMIN_PASSWORD (>= 12 characters) set on the server?');
      process.exitCode = 1;
      return;
    }
    if (res.status !== 200 || body.success !== true) {
      console.error(`HTTP ${res.status}: ${body.message || 'unexpected reply'}`);
      process.exitCode = 1;
      return;
    }
    data = body.data || {};
  } catch (e) {
    console.error(`Could not reach the backend: ${e.message}`);
    process.exitCode = 1;
    return;
  }

  const summary = data.summary || {};
  const companies = data.companies || [];
  const platform = data.platform || {};

  console.log(`CamerPay readiness at ${BASE}`);
  console.log(`${summary.ready || 0} of ${summary.total || 0} companies can collect electronic payments.`);
  // The one blocker that is the platform's own: without the storage key no company
  // can be connected, so it is stated once, loudly, before the per-company list.
  if (platform.vaultReady === true) {
    console.log('Storage key (PAYMENT_CREDENTIALS_KEY): configured');
  } else {
    console.log('Storage key (PAYMENT_CREDENTIALS_KEY): MISSING — nothing can be connected until it is set');
  }
  console.log('');

  for (const c of companies) {
    const mark = c.nextStep === 'ready' ? '✅' : '⚠️ ';
    const plan = c.plan || 'free';
    const status = c.subscriptionStatus ? ` (${c.subscriptionStatus})` : '';
    console.log(`${mark} #${c.id} ${c.name} - ${plan}${status}`);
    if (c.blockers && c.blockers.length) {
      console.log(`     blockers: ${c.blockers.join(', ')}`);
    }
    console.log(`     next: ${STEPS[c.nextStep] || c.nextStep}`);
  }

  if ((summary.blocked || 0) > 0) {
    console.log(`\n${summary.blocked} company(ies) cannot collect yet - a sale taken on them must be cash.`);
    process.exitCode = 1;
  } else {
    console.log('\nEvery company can collect through its own CamerPay account.');
    process.exitCode = 0;
  }
})();
