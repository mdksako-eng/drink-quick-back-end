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
    const { status, body } = await get(`${BASE}/api/subscriptions/notchpay/health`);
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
    ['Notch Pay keys configured', data.notchpayConfigured === true],
    ['Notch Pay public key', data.publicKeySet === true],
    ['Notch Pay private key', data.privateKeySet === true],
    ['Webhook secret', data.webhookSecretSet === true],
    ['Notch Pay LIVE mode', String(data.mode || data.notchpayMode) === 'live'],
    ['MTN direct creds', data.platformMomo ? data.platformMomo.mtnConfigured === true : false],
    ['Orange direct creds', data.platformMomo ? data.platformMomo.orangeConfigured === true : false],
    ['Everything ready for real money', data.liveReady === true],
  ];

  for (const [label, ok] of rows) {
    console.log(`${ok ? '✅' : '⚠️ '} ${label}`);
  }

  console.log(`\nmode: ${data.mode || data.notchpayMode || 'unknown'}`);
  if (data.hint) console.log(`hint: ${data.hint}`);

  if (data.liveReady === true) {
    console.log('\n🎉 LIVE: subscription payments will collect real money.');
    // Set the code instead of process.exit(): exiting while the HTTP socket is
    // still closing trips a libuv assertion on Windows.
    process.exitCode = 0;
    return;
  }

  console.log('\n🧪 TEST MODE: no real money will be collected.');
  console.log('To go live (Render → your service → Environment):');
  console.log('  NOTCHPAY_PUBLIC_KEY=pk_live_…   NOTCHPAY_PRIVATE_KEY=sk_live_…');
  console.log('  NOTCHPAY_WEBHOOK_SECRET=<live webhook secret>');
  console.log(`  webhook URL: ${BASE}/api/subscriptions/notchpay-webhook`);
  console.log('  optional card rail: FLUTTERWAVE_PUBLIC_KEY / FLUTTERWAVE_SECRET_KEY');
  console.log('  optional direct MoMo: PLATFORM_MTN_SANDBOX=false + merchant credentials');
  console.log('Then redeploy and run this script again.');
  process.exitCode = 1;
})();
