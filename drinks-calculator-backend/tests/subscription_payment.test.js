// backend/tests/subscription_payment.test.js
// The gate that decides whether a verified payment may hand out a paid plan —
// and, for CamerPay, the rule that a sandbox payment never can.
const {
  REASONS,
  decideActivation,
  isFailureStatus,
  isCompletedStatus,
  isTruthy,
  describeReason,
} = require('../utils/subscriptionPayment');
const paymentGuard = require('../utils/paymentGuard');

const base = {
  status: 'completed',
  isSandbox: false,
  paidAmount: 5000,
  paidCurrency: 'XAF',
  expectedAmount: 5000,
  expectedCurrency: 'XAF',
};

describe('decideActivation', () => {
  test('completes a real payment for the right amount', () => {
    const d = decideActivation(base);
    expect(d.activate).toBe(true);
    expect(d.reason).toBe(REASONS.ACTIVATED);
  });

  test('a SANDBOX payment never activates, even when completed', () => {
    expect(decideActivation({ ...base, isSandbox: true })).toMatchObject({
      activate: false, reason: REASONS.SANDBOX,
    });
    expect(decideActivation({ ...base, isSandbox: 'true' })).toMatchObject({
      activate: false, reason: REASONS.SANDBOX,
    });
  });

  test('a numeric sandbox flag is treated as sandbox', () => {
    expect(decideActivation({ ...base, isSandbox: undefined }).activate).toBe(true);
    expect(decideActivation({ ...base, isSandbox: 1 })).toMatchObject({ reason: REASONS.SANDBOX });
  });

  test('a pending transaction does not activate', () => {
    expect(decideActivation({ ...base, status: 'pending' })).toMatchObject({
      activate: false, reason: REASONS.NOT_COMPLETED,
    });
    expect(decideActivation({ ...base, status: 'processing' })).toMatchObject({
      reason: REASONS.NOT_COMPLETED,
    });
  });

  test('a failed or cancelled payment is reported as failed', () => {
    for (const status of ['failed', 'cancelled', 'expired', 'abandoned']) {
      expect(decideActivation({ ...base, status })).toMatchObject({
        activate: false, reason: REASONS.FAILED,
      });
    }
  });

  test('an underpayment is refused while enforcement is on', () => {
    const d = decideActivation({ ...base, paidAmount: 1000 });
    expect(d.activate).toBe(false);
    expect(d.reason).toBe('underpaid');
    expect(d.guard.paid).toBe(1000);
    expect(d.guard.expected).toBe(5000);
  });

  test('an underpayment is allowed only when the operator opted out', () => {
    expect(decideActivation({ ...base, paidAmount: 1000, enforceUnderpayment: false }).activate)
      .toBe(true);
  });

  test('an overpayment still activates (the payer rounded up)', () => {
    expect(decideActivation({ ...base, paidAmount: 5077 }).activate).toBe(true);
  });

  test('a currency mismatch is refused', () => {
    expect(decideActivation({ ...base, paidCurrency: 'EUR' })).toMatchObject({
      activate: false, reason: 'currency_mismatch',
    });
  });

  test('no pending row means nothing to activate', () => {
    expect(decideActivation({ ...base, pendingExists: false })).toMatchObject({
      activate: false, reason: REASONS.NO_PENDING,
    });
  });

  test('a completed sandbox payment is refused before any amount check', () => {
    expect(decideActivation({ ...base, isSandbox: true, paidAmount: 999999 })).toMatchObject({
      reason: REASONS.SANDBOX,
    });
  });

  test('an empty call refuses instead of throwing', () => {
    expect(decideActivation({}).activate).toBe(false);
  });
});

describe('status helpers', () => {
  test('failure and completion detection', () => {
    expect(isFailureStatus('failed')).toBe(true);
    expect(isFailureStatus('cancelled')).toBe(true);
    expect(isFailureStatus('pending')).toBe(false);
    expect(isCompletedStatus('completed')).toBe(true);
    expect(isCompletedStatus('successful')).toBe(true);
    expect(isCompletedStatus('failed')).toBe(false);
  });

  test('isTruthy covers the string and number forms', () => {
    expect(isTruthy(true)).toBe(true);
    expect(isTruthy('true')).toBe(true);
    expect(isTruthy(1)).toBe(true);
    expect(isTruthy('1')).toBe(true);
    expect(isTruthy(false)).toBe(false);
    expect(isTruthy('false')).toBe(false);
    expect(isTruthy(undefined)).toBe(false);
  });

  test('every reason has an honest sentence', () => {
    for (const reason of Object.values(REASONS)) {
      const text = describeReason(reason);
      expect(typeof text).toBe('string');
      expect(text.length).toBeGreaterThan(5);
    }
    expect(describeReason(REASONS.SANDBOX)).toMatch(/no money moved/i);
    expect(describeReason('nonsense')).toMatch(/Unknown/);
  });
});

describe('provider-neutral payment flags', () => {
  const KEYS = [
    'PAYMENTS_REQUIRE_LIVE',
    'NOTCHPAY_REQUIRE_LIVE',
    'PAYMENTS_ALLOW_UNDERPAYMENT',
    'NOTCHPAY_ALLOW_UNDERPAYMENT',
  ];
  const saved = {};
  beforeEach(() => {
    for (const key of KEYS) {
      saved[key] = process.env[key];
      delete process.env[key];
    }
  });
  afterEach(() => {
    for (const key of KEYS) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  });

  test('PAYMENTS_REQUIRE_LIVE switches live enforcement on', () => {
    expect(paymentGuard.liveKeyRequired()).toBe(false);
    process.env.PAYMENTS_REQUIRE_LIVE = 'true';
    expect(paymentGuard.liveKeyRequired()).toBe(true);
  });

  test('the older NOTCHPAY_REQUIRE_LIVE still works', () => {
    process.env.NOTCHPAY_REQUIRE_LIVE = 'true';
    expect(paymentGuard.liveKeyRequired()).toBe(true);
  });

  test('underpayment is enforced by default and relaxed by either name', () => {
    expect(paymentGuard.shouldEnforce()).toBe(true);
    process.env.PAYMENTS_ALLOW_UNDERPAYMENT = 'true';
    expect(paymentGuard.shouldEnforce()).toBe(false);
    delete process.env.PAYMENTS_ALLOW_UNDERPAYMENT;
    process.env.NOTCHPAY_ALLOW_UNDERPAYMENT = 'true';
    expect(paymentGuard.shouldEnforce()).toBe(false);
  });
});
