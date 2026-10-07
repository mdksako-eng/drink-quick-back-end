// backend/utils/paymentGuard.js
// The money question, and only that: did this payment actually pay the price we
// asked for? Pure — no network, no database — so the rule stays testable.
//
// Why it exists: a webhook is only as trustworthy as its signature. If that
// secret ever leaks (pasted in a screenshot, shared in a chat), anyone can POST
// `{reference, status: 'completed', amount: 1}` and get a paid plan for free.
// Checking the amount against the pending row makes that attempt fail closed.
// Amounts arrive as JSON numbers, as strings ("5000") or, from `pg`, as NUMERIC
// strings — all three are accepted.

/** @returns {number|null} null when the value is missing or not a number. */
function normalizeAmount(value) {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** @returns {string|null} upper-cased currency code, or null. */
function normalizeCurrency(value) {
  const code = String(value ?? '').trim().toUpperCase();
  return code || null;
}

/**
 * Compare what was paid with what the pending subscription asked for.
 *
 * Deliberately asymmetric: paying MORE is fine (fees, rounding, an operator
 * charging in the customer's favour), paying LESS is not — a month of service
 * must not be handed out for a partial payment.
 *
 * @returns {{ok: boolean, reason: string, paid: number|null, expected: number|null}}
 *   reason: 'exact' | 'overpaid' | 'underpaid' | 'currency_mismatch'
 *         | 'amount_unknown' | 'no_expectation'
 */
function paidAmountMatches({
  paidAmount,
  paidCurrency,
  expectedAmount,
  expectedCurrency,
} = {}) {
  const paid = normalizeAmount(paidAmount);
  const expected = normalizeAmount(expectedAmount);
  const paidCur = normalizeCurrency(paidCurrency);
  const expectedCur = normalizeCurrency(expectedCurrency);

  // Nothing to compare against, or the provider did not repeat the amount.
  // Both are allowed through — refusing here would block honest payments — and
  // the caller logs which one it was.
  if (expected === null) {
    return { ok: true, reason: 'no_expectation', paid, expected };
  }
  if (paid === null) {
    return { ok: true, reason: 'amount_unknown', paid, expected };
  }

  if (expectedCur && paidCur && expectedCur !== paidCur) {
    return { ok: false, reason: 'currency_mismatch', paid, expected };
  }
  // 0.5 of a unit of tolerance: XAF/XOF have no decimals, so this only absorbs
  // floating point noise, never a real shortfall.
  if (paid + 0.5 < expected) {
    return { ok: false, reason: 'underpaid', paid, expected };
  }
  if (paid > expected + 0.5) {
    return { ok: true, reason: 'overpaid', paid, expected };
  }
  return { ok: true, reason: 'exact', paid, expected };
}

/**
 * Is underpayment enforcement switched on? On by default.
 *
 * `PAYMENTS_ALLOW_UNDERPAYMENT=true` turns it off for every provider. The older
 * per-provider name keeps working, so a deployment already using it does not
 * change behaviour when this code lands.
 */
function shouldEnforce() {
  const legacy = String(process.env.NOTCHPAY_ALLOW_UNDERPAYMENT || 'false').toLowerCase() === 'true';
  const general = String(process.env.PAYMENTS_ALLOW_UNDERPAYMENT || 'false').toLowerCase() === 'true';
  return !(legacy || general);
}

/**
 * Must real money actually move for a payment to be started?
 *
 * Off by default, because test keys are useful for demos and dry runs. Set
 * `PAYMENTS_REQUIRE_LIVE=true` on a production service so a test key can never
 * silently hand out a paid plan without collecting anything.
 * `NOTCHPAY_REQUIRE_LIVE` stays supported for existing deployments.
 *
 * NOTE for CamerPay: its token cannot reveal the mode (the account decides), so
 * this flag is only an operator assertion that the account is expected to be
 * live. The activation gate never trusts it — it reads `is_sandbox` from the
 * transaction (see utils/subscriptionPayment.js).
 */
function liveKeyRequired() {
  const legacy = String(process.env.NOTCHPAY_REQUIRE_LIVE || 'false').toLowerCase() === 'true';
  const general = String(process.env.PAYMENTS_REQUIRE_LIVE || 'false').toLowerCase() === 'true';
  return legacy || general;
}

module.exports = {
  normalizeAmount,
  normalizeCurrency,
  paidAmountMatches,
  shouldEnforce,
  liveKeyRequired,
};
