// utils/subscriptionExpiry.js
// Pure rules for what happens when a company's paid plan runs out.
//
// WHY THIS EXISTS
//   What the app reads is on the COMPANY row (`plan`, `plan_expires_at`,
//   `subscription_status`); the `subscriptions` table is the purchase history.
//   Auto-expiring used to update only the company, so its subscription rows kept
//   saying 'active' for ever — five were still 'active' in production while the
//   company read 'free' / 'expired', which makes the history lie about what the
//   shop is entitled to.

const EXPIRED = 'expired';

/** Statuses that describe a subscription the shop is CURRENTLY entitled to. */
const LIVE_STATUSES = ['active'];

/**
 * Whether a subscription row should be marked expired when its company's plan
 * runs out.
 *
 * ONLY 'active' rows. A 'pending' row is an attempt that a late webhook may
 * still confirm, and expiring it would turn that confirmation into a no-op —
 * the customer's money would be taken and the plan never granted. A row that is
 * already expired, failed or cancelled is left exactly as it is.
 */
function shouldExpireSubscription(status) {
  return LIVE_STATUSES.includes(String(status || '').trim().toLowerCase());
}

/** Which of these rows the sweep must expire (pure, so the route stays thin). */
function subscriptionsToExpire(rows) {
  return (rows || []).filter((row) =>
    shouldExpireSubscription(row && row.status)
  );
}

module.exports = {
  EXPIRED,
  LIVE_STATUSES,
  shouldExpireSubscription,
  subscriptionsToExpire,
};
