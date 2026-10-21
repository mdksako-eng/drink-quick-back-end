// utils/loadStats.js
// Pure latency statistics for scripts/load_test.js.
//
// WHY PERCENTILES: an average hides the problem. Nine requests at 40 ms and one at
// 4 s average 436 ms — which sounds fine and is nothing like what the tenth user
// experiences. p95/p99 are what an operator actually feels on a till.
//
// Percentiles use the nearest-rank method: p95 of 10 values is the 10th.

function sortNumbers(values) {
  return (Array.isArray(values) ? values : [])
    // Drop null/undefined/'' BEFORE Number(): Number(null) is 0, which would be
    // reported as a real (very fast) sample instead of being ignored.
    .filter((v) => v !== null && v !== undefined && v !== '')
    .map(Number)
    .filter((n) => Number.isFinite(n))
    .sort((a, b) => a - b);
}

/**
 * Nearest-rank percentile of an ALREADY SORTED ascending array.
 * @param {number[]} sorted
 * @param {number} p 0-100
 */
function percentile(sorted, p) {
  if (!sorted || sorted.length === 0) return 0;
  const rank = Math.ceil((Math.min(100, Math.max(0, p)) / 100) * sorted.length);
  const index = Math.min(sorted.length - 1, Math.max(0, rank - 1));
  return sorted[index];
}

/**
 * @param {number[]} values latencies in ms
 * @returns {{count: number, min: number, mean: number, p50: number, p90: number,
 *            p95: number, p99: number, max: number}} all rounded to 1 decimal
 */
function summarise(values) {
  const sorted = sortNumbers(values);
  if (sorted.length === 0) {
    return { count: 0, min: 0, mean: 0, p50: 0, p90: 0, p95: 0, p99: 0, max: 0 };
  }
  const round = (n) => Math.round(n * 10) / 10;
  const total = sorted.reduce((sum, n) => sum + n, 0);
  return {
    count: sorted.length,
    min: round(sorted[0]),
    mean: round(total / sorted.length),
    p50: round(percentile(sorted, 50)),
    p90: round(percentile(sorted, 90)),
    p95: round(percentile(sorted, 95)),
    p99: round(percentile(sorted, 99)),
    max: round(sorted[sorted.length - 1]),
  };
}

/** One aligned line for the console, e.g. `GET /api/drinks  n=50 p95=180.2ms`. */
function formatSummary(label, stats) {
  const pad = (n) => String(n).padStart(8);
  return `${label.padEnd(22)} n=${String(stats.count).padStart(4)}` +
    ` p50=${pad(stats.p50)} p90=${pad(stats.p90)} p95=${pad(stats.p95)}` +
    ` p99=${pad(stats.p99)} max=${pad(stats.max)} ms`;
}

module.exports = { percentile, summarise, formatSummary, sortNumbers };
