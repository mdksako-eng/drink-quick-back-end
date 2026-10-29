#!/usr/bin/env node
// scripts/check_payments.js
// Answers "can we take REAL money yet?" against the deployed backend.
//
// Usage:
//   node scripts/check_payments.js
//   node scripts/check_payments.js https://my-service.onrender.com
//
// Exit code 0 = live payments ready, 1 = still test/sandbox (or unreachable).
const BASE = (process.argv[2] || 'https://drink-quick-cal-kja1.onrender.com')
  .replace(/\/$/, '');

async function get(url) {
  const res = await fetch(url, { headers: { Accept: 'application/json' } });
  const text = await res.text();
  let body = text;
  try {
    body = JSON.parse(text);
  } catch (_) {}
  return { status: res.status, body };
}

(async () => {
  console.log(`Checking payments readiness at ${BASE}\n`);

  let data = null;
  try {
    const { status, body } = await get(`${BASE}/api/subscriptions/campay/health`);
    if (status !== 200) {
      console.error(`❌ Health check returned HTTP ${status}`);
      console.error(typeof body === 'string' ? body.slice(0, 300) : body);
      process.exit(1);
    }
    data = (body && body.data) || body || {};
  } catch (e) {
    console.error(`❌ Could not reach the backend: ${e.message}`);
    process.exit(1);
  }

  const rows = [
    ['CamerPay token configured', data.configured === true],
    ['Webhook secret', data.webhookSecretSet === true],
    ['Account declared live (CAMERPAY_ACCOUNT_LIVE)', data.accountDeclaredLive === true],
    ['Fee rates configured', data.feeRatesConfigured === true],
    ['Everything ready for real money', data.liveReady === true],
  ];

  for (const [label, ok] of rows) {
    console.log(`${ok ? '✅' : '⚠️ '} ${label}`);
  }

  console.log(`\naccount declared live: ${data.accountDeclaredLive === true ? 'yes' : 'no'}`);
  if (data.hint) console.log(`hint: ${data.hint}`);

  if (data.liveReady === true) {
    console.log('\n🎉 LIVE: subscription payments will collect real money.');
    // Set the code instead of process.exit(): exiting while the HTTP socket is
    // still closing trips a libuv assertion on Windows.
    process.exitCode = 0;
    return;
  }

  console.log('\n🧪 NOT LIVE YET: no real money will be collected.');
  console.log('To go live (Render → your service → Environment):');
  console.log('  CAMERPAY_TOKEN=<token from the CamerPay dashboard>');
  console.log('  CAMERPAY_WEBHOOK_SECRET=<webhook secret>');
  console.log('  CAMERPAY_ACCOUNT_LIVE=true   (only once KYC is approved)');
  console.log(`  webhook URL: ${BASE}/api/subscriptions/campay-webhook`);
  console.log('Then redeploy and run this script again.');
  process.exitCode = 1;
})();
