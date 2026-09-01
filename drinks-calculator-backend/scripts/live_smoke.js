/* Live smoke test against the deployed Render backend.
 * Verifies the security model: unauthenticated calls are rejected (401),
 * and authenticated calls succeed. Run: node scripts/live_smoke.js
 */
const https = require('https');

const B = 'https://drink-quick-cal-kja1.onrender.com';
const EMAIL = process.env.TEST_EMAIL;
const PWD = process.env.TEST_PASSWORD;

function api(path, token) {
  const headers = { Accept: 'application/json' };
  if (token) headers.Authorization = 'Bearer ' + token;
  return new Promise((resolve) => {
    https.get(B + path, { headers }, (r) => {
      let b = '';
      r.on('data', (c) => (b += c));
      r.on('end', () => resolve({ status: r.statusCode, body: b }));
    }).on('error', (e) => resolve({ error: e.message }));
  });
}

function post(path, json, token) {
  const data = JSON.stringify(json);
  const headers = { 'Content-Type': 'application/json', Accept: 'application/json' };
  if (token) headers.Authorization = 'Bearer ' + token;
  return new Promise((resolve) => {
    const req = https.request(B + path, { method: 'POST', headers }, (r) => {
      let b = '';
      r.on('data', (c) => (b += c));
      r.on('end', () => resolve({ status: r.statusCode, body: b }));
    });
    req.on('error', (e) => resolve({ error: e.message }));
    req.write(data);
    req.end();
  });
}

(async () => {
  let pass = 0, fail = 0;
  const ok = (name, cond) => (cond ? pass++ : fail++, console.log((cond ? '✅' : '❌') + ' ' + name));

  // 1. Unauthenticated calls must be rejected
  const d401 = await api('/api/data/drinks');
  ok('GET /api/data/drinks without token → 401', d401.status === 401);

  const u401 = await api('/api/users');
  ok('GET /api/users without token → 401', u401.status === 401);

  const m401 = await api('/api/auth/me');
  ok('GET /api/auth/me without token → 401', m401.status === 401);

  // 2. Login with real credentials + use the session token
  if (EMAIL && PWD) {
    const login = await post('/api/auth/login', { email: EMAIL, password: PWD });
    const ld = JSON.parse(login.body || '{}');
    ok('Login succeeds (200)', login.status === 200 && ld.token);
    const token = ld.token;
    ok('Token is a random session (starts sq_)', token && token.startsWith('sq_'));

    const d200 = await api('/api/data/drinks', token);
    ok('GET /api/data/drinks with token → 200', d200.status === 200);

    const o200 = await api('/api/data/orders', token);
    ok('GET /api/data/orders with token → 200', o200.status === 200);

    const c200 = await api('/api/data/company', token);
    ok('GET /api/data/company with token → 200', c200.status === 200);

    const company = JSON.parse(c200.body || 'null');
    ok('Company object has NO mtn_api_key', !company || !company.mtn_api_key);
    ok('Company object has NO orange_secret_key', !company || !company.orange_secret_key);
  } else {
    console.log('⏭️  Skipping authenticated tests (set TEST_EMAIL / TEST_PASSWORD env vars)');
  }

  // 3. Public customer endpoint still reachable
  const pub = await api('/api/company/1/public');
  ok('GET /api/company/1/public reachable (any 2xx/4xx)', pub.status && pub.status < 500);

  console.log('\\n📊 ' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail > 0 ? 1 : 0);
})();
