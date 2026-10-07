// backend/utils/subscriptionPayment.js
// One question, and only that: may this verified payment hand out a paid plan?
// Pure — no network, no database — so the rule stays testable.
//
// Why it exists separately from the routes: for CamerPay the token cannot tell
// test from live (the account decides), so the ONLY trustworthy signals are the
// transaction's own status and its `is_sandbox` flag. A webhook body alone must
// never activate anything: the route re-reads the transaction, then asks this
// module. Sandbox payments also never count towards KYC volume, so activating on
// one would hand out a free month and lie in the books.
const { paidAmountMatches } = require('./paymentGuard');

/** Machine-readable outcomes; the app turns these into localized messages. */
const REASONS = {
  ACTIVATED: 'activated',
  NOT_COMPLETED: 'not_completed',
  SANDBOX: 'sandbox_payment',
  UNDERPAID: 'underpaid',
  CURRENCY_MISMATCH: 'currency_mismatch',
  NO_PENDING: 'no_pending_subscription',
  FAILED: 'payment_failed',
};

/** Statuses that mean "the payer said no / it never happened". */
const FAILURE_STATUSES = ['failed', 'cancelled', 'expired', 'abandoned'];

const COMPLETED_STATUSES = ['completed', 'complete', 'success', 'successful', 'succeeded', 'paid'];

/** True for a boolean or the string forms providers sometimes send. */
function isTruthy(value) {
  return value === true || value === 'true' || value === 1 || value === '1';
}

/**
 * Decide whether to activate, and why not when refusing.
 *
 * Order matters: a completed sandbox payment is refused BEFORE the amount is
 * even considered, so no amount check can ever talk us into it.
 *
 * @param {object} params
 *   status          provider status (raw or normalised)
 *   isSandbox       transaction is_sandbox flag
 *   paidAmount, paidCurrency        what the provider says was paid
 *   expectedAmount, expectedCurrency what the pending row asked for
 *   enforceUnderpayment             false only when the operator opted out
 *   pendingExists                   false when there is no pending row to activate
 * @returns {{activate: boolean, reason: string, guard?: object}}
 */
function decideActivation({
  status,
  isSandbox,
  paidAmount,
  paidCurrency,
  expectedAmount,
  expectedCurrency,
  enforceUnderpayment = true,
  pendingExists = true,
} = {}) {
  if (!pendingExists) return { activate: false, reason: REASONS.NO_PENDING };

  const normalized = String(status || '').toLowerCase();
  if (FAILURE_STATUSES.includes(normalized)) {
    return { activate: false, reason: REASONS.FAILED };
  }
  if (!COMPLETED_STATUSES.includes(normalized)) {
    return { activate: false, reason: REASONS.NOT_COMPLETED };
  }
  if (isTruthy(isSandbox)) {
    return { activate: false, reason: REASONS.SANDBOX };
  }

  const guard = paidAmountMatches({
    paidAmount,
    paidCurrency,
    expectedAmount,
    expectedCurrency,
  });
  if (!guard.ok && enforceUnderpayment) {
    return { activate: false, reason: guard.reason, guard };
  }
  return { activate: true, reason: REASONS.ACTIVATED, guard };
}

/** Did the payer walk away (as opposed to "still pending")? */
function isFailureStatus(status) {
  return FAILURE_STATUSES.includes(String(status || '').toLowerCase());
}

/** Did money move? */
function isCompletedStatus(status) {
  return COMPLETED_STATUSES.includes(String(status || '').toLowerCase());
}

/**
 * A short, honest sentence for logs, /health and support tickets. Never claims
 * success the caller did not get.
 */
function describeReason(reason) {
  switch (reason) {
    case REASONS.ACTIVATED:
      return 'Paid and verified — the plan was activated.';
    case REASONS.SANDBOX:
      return 'Sandbox payment: no money moved, so no plan was activated.';
    case REASONS.NOT_COMPLETED:
      return 'The transaction is not completed yet.';
    case REASONS.UNDERPAID:
      return 'The amount paid is less than the plan price.';
    case REASONS.CURRENCY_MISMATCH:
      return 'The currency paid does not match the plan price.';
    case REASONS.FAILED:
      return 'The payment failed, was cancelled or expired.';
    case REASONS.NO_PENDING:
      return 'No pending subscription matches that reference.';
    default:
      return 'Unknown outcome.';
  }
}

module.exports = {
  REASONS,
  FAILURE_STATUSES,
  COMPLETED_STATUSES,
  isTruthy,
  decideActivation,
  isFailureStatus,
  isCompletedStatus,
  describeReason,
};
