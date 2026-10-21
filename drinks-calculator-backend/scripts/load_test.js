#!/usr/bin/env node
// scripts/load_test.js
// Measures how the backend behaves under a till-like load: log in once, then hammer
// the endpoints a screen actually calls, and report latency percentiles and errors.
//
// Answers the "can one instance serve 500 users?" question with numbers instead of
// estimates. Run it against staging first, never against production during service.
//
// CREDENTIALS: never stored here. Pass them on the command line or via the
// environment; the password is never printed.
//
//   node scripts/load_test.js --base https://backend.example --user demo --password '...'
//   node scripts/load_test.js --base ... --user demo --password ... --requests 400 --concurrency 20
//   node scripts/load_test.js --dry-run          # parse/validate only, sends nothing
//   node scripts/load_test.js --help
//
// Exit code: 0 when every request was 2xx, 1 if anything failed (so CI can gate on it).
const { summarise, formatSummary } = require('../utils/loadStats');

const DEFAULT_PATHS = ['/api/drinks', '/api/orders', '/api/inventory', '/api/settings'];
const USAGE = `
Usage: node scripts/load_test.js --base <url> --user <username> --password <pw> [options]

  --base <url>         backend origin, e.g. https://drink-quick-back.onrender.com
  --user <name>        account used for the login (username or email)
  --password <pw>      its password (or set LOAD_PASSWORD)
  --requests <n>       total requests to send (default 200)
  --concurrency <n>    parallel workers (default 10)
  --path <p>           repeatable; default ${DEFAULT_PATHS.join(', ')}
  --dry-run            validate the arguments, print the plan, send nothing
  --help               this text
`.trim();

function parseArgs(argv) {
  const config = {
    base: '', user: '', password: process.env.LOAD_PASSWORD || '',
    requests: 200, concurrency: 10, paths: [], dryRun: false, help: false,
  };
  const explicitPaths = [];
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => argv[i + 1] ?? '';
    if (arg === '--base') { config.base = next(); i += 1; }
    else if (arg === '--user') { config.user = next(); i += 1; }
    else if (arg === '--password') { config.password = next(); i += 1; }
    else if (arg === '--requests') { config.requests = Number(next()) || config.requests; i += 1; }
    else if (arg === '--concurrency') { config.concurrency = Number(next()) || config.concurrency; i += 1; }
    else if (arg === '--path') { explicitPaths.push(next()); i += 1; }
    else if (arg.startsWith('--path=')) { explicitPaths.push(arg.slice(7)); }
    else if (arg === '--dry-run') config.dryRun = true;
    else if (arg === '--help' || arg === '-h') config.help = true;
  }
  config.paths = (explicitPaths.length ? explicitPaths : DEFAULT_PATHS)
    .map((p) => p.trim()).filter(Boolean);
  config.requests = Math.max(1, Math.trunc(config.requests));
  config.concurrency = Math.max(1, Math.trunc(config.concurrency));
  config.base = config.base.replace(/\/+$/, '');
  return config;
}

function validConfig(c) {
  const problems = [];
  if (!c.base || !/^https?:\/\//i.test(c.base)) problems.push('--base must be an http(s) URL');
  if (!c.user) problems.push('--user is required');
  if (!c.password) problems.push('--password (or LOAD_PASSWORD) is required');
  if (c.paths.length === 0) problems.push('at least one --path is required');
  return problems;
}

async function login(base, user, password) {
  const response = await fetch(`${base}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: user, password }),
  });
  const text = await response.text();
  let body = {};
  try { body = JSON.parse(text); } catch { /* not JSON */ }
  const token = body?.data?.sessionToken || body?.sessionToken || '';
  if (!response.ok || !token) {
    throw new Error(`login failed (HTTP ${response.status})${body?.message ? `: ${body.message}` : ''}`);
  }
  return token;
}

async function run(config, token) {
  const samples = new Map(config.paths.map((p) => [p, []]));
  const failures = new Map();
  let issued = 0;
  const started = Date.now();

  async function worker() {
    for (;;) {
      const index = issued;
      issued += 1;
      if (index >= config.requests) return;
      const path = config.paths[index % config.paths.length];
      const t0 = process.hrtime.bigint();
      let status = 0;
      try {
        const response = await fetch(`${config.base}${path}`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        status = response.status;
        await response.arrayBuffer(); // consume the body like a client would
      } catch {
        status = -1;
      }
      const ms = Number(process.hrtime.bigint() - t0) / 1e6;
      samples.get(path).push(ms);
      if (status < 200 || status >= 300) {
        failures.set(status, (failures.get(status) || 0) + 1);
      }
    }
  }

  await Promise.all(Array.from({ length: config.concurrency }, worker));
  return { samples, failures, elapsedMs: Date.now() - started };
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) return console.log(USAGE);

  const problems = validConfig(config);
  if (config.dryRun) {
    console.log('Load test plan (nothing was sent)');
    console.log(`  base     : ${config.base || '(missing)'}`);
    console.log(`  user     : ${config.user || '(missing)'}`);
    console.log(`  password : ${config.password ? '*** (set)' : '(missing)'}`);
    console.log(`  requests : ${config.requests} across ${config.concurrency} workers`);
    console.log(`  paths    : ${config.paths.join(', ')}`);
    console.log(problems.length ? `  PROBLEMS : ${problems.join('; ')}` : '  arguments OK');
    return process.exit(problems.length ? 2 : 0);
  }
  if (problems.length) {
    console.error(`Invalid arguments:\n  - ${problems.join('\n  - ')}\n\n${USAGE}`);
    return process.exit(2);
  }

  console.log(`Logging in as ${config.user} …`);
  const token = await login(config.base, config.user, config.password);
  console.log(`Running ${config.requests} requests, ${config.concurrency} at a time\n`);

  const { samples, failures, elapsedMs } = await run(config, token);

  const all = [];
  for (const [path, values] of samples) {
    all.push(...values);
    console.log(formatSummary(`GET ${path}`, summarise(values)));
  }
  console.log(''.padEnd(78, '-'));
  console.log(formatSummary('ALL REQUESTS', summarise(all)));
  console.log(`\n${Math.round((config.requests / elapsedMs) * 1000)} req/s over ${(elapsedMs / 1000).toFixed(1)} s`);

  if (failures.size === 0) {
    console.log('Errors: none');
    return process.exit(0);
  }
  const failed = [...failures.values()].reduce((a, b) => a + b, 0);
  const detail = [...failures.entries()]
    .map(([status, count]) => `${status === -1 ? 'network' : `HTTP ${status}`}: ${count}`)
    .join(', ');
  console.log(`Errors: ${detail} — success rate ${(((config.requests - failed) / config.requests) * 100).toFixed(1)}%`);
  process.exit(1);
}

main().catch((error) => {
  console.error(`Load test failed: ${error.message}`);
  process.exit(1);
});
