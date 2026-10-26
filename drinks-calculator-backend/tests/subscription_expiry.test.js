// tests/subscription_expiry.test.js
// When a company's paid plan runs out, its purchase history must agree with it.
//
// Found in production: five `subscriptions` rows still said 'active' while the
// company read 'free' / 'expired', because auto-expiry updated only the company.
const {
  EXPIRED,
  LIVE_STATUSES,
  shouldExpireSubscription,
  subscriptionsToExpire,
} = require('../utils/subscriptionExpiry');

describe('which subscriptions expire with the company', () => {
  test('an active subscription expires with the plan', () => {
    expect(shouldExpireSubscription('active')).toBe(true);
    expect(LIVE_STATUSES).toEqual(['active']);
    expect(EXPIRED).toBe('expired');
  });

  test('a PENDING attempt is left alone — a late webhook may still confirm it', () => {
    // Expiring it would make the confirmation a no-op: the money is taken and
    // the plan is never granted.
    expect(shouldExpireSubscription('pending')).toBe(false);
  });

  test('rows that are already finished are left exactly as they are', () => {
    expect(shouldExpireSubscription('expired')).toBe(false);
    expect(shouldExpireSubscription('failed')).toBe(false);
    expect(shouldExpireSubscription('cancelled')).toBe(false);
    expect(shouldExpireSubscription('refunded')).toBe(false);
  });

  test('a missing or odd status is never treated as live', () => {
    expect(shouldExpireSubscription(null)).toBe(false);
    expect(shouldExpireSubscription(undefined)).toBe(false);
    expect(shouldExpireSubscription('')).toBe(false);
  });

  test('the check is case and space tolerant', () => {
    // The column is lowercase in practice, but a stray ' Active ' must not
    // survive the very sweep meant to clean it up.
    expect(shouldExpireSubscription(' Active ')).toBe(true);
    expect(shouldExpireSubscription('ACTIVE')).toBe(true);
  });

  test('the sweep picks out only the live rows', () => {
    const rows = [
      { id: 1, status: 'active' },
      { id: 2, status: 'pending' },
      { id: 3, status: 'expired' },
      { id: 4, status: 'active' },
    ];
    expect(subscriptionsToExpire(rows).map((r) => r.id)).toEqual([1, 4]);
    expect(subscriptionsToExpire([])).toEqual([]);
    expect(subscriptionsToExpire(null)).toEqual([]);
  });
});
