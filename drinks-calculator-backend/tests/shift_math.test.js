/**
 * Shift / cash-up arithmetic — no database required.
 *
 * Covers the Z-report rules:
 *   - sales, collected and "on the tab" come from the orders in the window
 *   - expected cash = opening float + collected − payouts
 *   - the variance is counted − expected (negative = the till is short)
 *   - a staff member closes their own shift; a manager closes anyone's
 *   - one open shift per person, and a float / count may never be negative
 *
 * Run with: npm test
 */
const {
  summariseOrders,
  summarisePayments,
  summariseShift,
  cashVariance,
  isOpen,
  canCloseShift,
  openShiftProblem,
  validateOpeningFloat,
  validateClose,
} = require('../utils/shiftMath');

const openShift = {
  id: 5,
  company_id: 7,
  staff_user_id: 11,
  status: 'open',
  opening_float: '5000.00',
  cash_payouts: '0',
  cash_counted: null,
};

const closedShift = { ...openShift, status: 'closed', cash_counted: '23000.00' };

const staff = { id: 11, role: 'Staff', company_id: 7 };
const otherStaff = { id: 12, role: 'Staff', company_id: 7 };
const manager = { id: 9, role: 'Manager', company_id: 7 };
const admin = { id: 1, role: 'Administrator', company_id: null };

describe('order totals for the shift window', () => {
  test('splits sales, collected and credit', () => {
    const totals = summariseOrders([
      { total_amount: '2000.00', amount_paid: '2000.00' },
      { total_amount: '3000.00', amount_paid: '1000.00' },
      { total_amount: 500, amount_paid: 500 },
    ]);
    expect(totals.orderCount).toBe(3);
    expect(totals.sales).toBe(5500);
    expect(totals.collected).toBe(3500);
    expect(totals.onCredit).toBe(2000);
  });

  test('an empty shift sold nothing', () => {
    const totals = summariseOrders([]);
    expect(totals.orderCount).toBe(0);
    expect(totals.sales).toBe(0);
    expect(totals.onCredit).toBe(0);
  });

  test('missing amounts are treated as zero', () => {
    const totals = summariseOrders([
      { total_amount: null, amount_paid: undefined },
    ]);
    expect(totals.sales).toBe(0);
    expect(totals.collected).toBe(0);
  });
});

describe('payment methods', () => {
  test('groups successful payments by method', () => {
    const totals = summarisePayments([
      { payment_method: 'MTN', amount: '1000.00', status: 'success' },
      { payment_method: 'Orange', amount: '2500.00', status: 'SUCCESS' },
      { payment_method: 'MTN', amount: '500.00', status: 'completed' },
    ]);
    expect(totals.byMethod.MTN).toBe(1500);
    expect(totals.byMethod.Orange).toBe(2500);
    expect(totals.total).toBe(4000);
  });

  test('a failed payment never reaches the report', () => {
    const totals = summarisePayments([
      { payment_method: 'MTN', amount: 1000, status: 'failed' },
      { payment_method: 'MTN', amount: 2000, status: 'pending' },
    ]);
    expect(totals.total).toBe(0);
    expect(totals.byMethod.MTN).toBeUndefined();
  });

  test('a payment with no method is still counted', () => {
    const totals = summarisePayments([{ amount: 700, status: 'success' }]);
    expect(totals.byMethod.other).toBe(700);
    expect(totals.total).toBe(700);
  });
});

describe('the Z-report of a shift', () => {
  test('expected cash is float + collected − payouts', () => {
    const summary = summariseShift({
      shift: { ...openShift, cash_payouts: '1000.00' },
      orders: [
        { total_amount: '2000.00', amount_paid: '2000.00' },
        { total_amount: '3000.00', amount_paid: '1000.00' },
      ],
    });
    expect(summary.openingFloat).toBe(5000);
    expect(summary.collected).toBe(3000);
    expect(summary.payouts).toBe(1000);
    expect(summary.expectedCash).toBe(7000);
    expect(summary.onCredit).toBe(2000);
  });

  test('an open shift has no count and no variance yet', () => {
    const summary = summariseShift({ shift: openShift, orders: [] });
    expect(summary.counted).toBeNull();
    expect(summary.variance).toBeNull();
  });

  test('a closed shift reports counted and the variance', () => {
    const summary = summariseShift({
      shift: closedShift,
      orders: [{ total_amount: '20000.00', amount_paid: '20000.00' }],
    });
    // 5000 float + 20000 collected = 25000 expected, 23000 counted.
    expect(summary.expectedCash).toBe(25000);
    expect(summary.variance).toBe(-2000);
  });

  test('the method breakdown is passed through', () => {
    const summary = summariseShift({
      shift: openShift,
      orders: [],
      payments: [{ payment_method: 'MTN', amount: 4000, status: 'success' }],
    });
    expect(summary.byMethod.MTN).toBe(4000);
    expect(summary.paymentsTotal).toBe(4000);
  });
});

describe('cash variance', () => {
  test('negative when the till is short, positive when it is over', () => {
    expect(cashVariance({ counted: 8000, expectedCash: 10000 })).toBe(-2000);
    expect(cashVariance({ counted: 10500, expectedCash: 10000 })).toBe(500);
  });

  test('rounds away floating point noise', () => {
    expect(cashVariance({ counted: 0.1 + 0.2, expectedCash: 0 })).toBe(0.3);
  });
});

describe('shift state and permissions', () => {
  test('open vs closed', () => {
    expect(isOpen(openShift)).toBe(true);
    expect(isOpen(closedShift)).toBe(false);
    expect(isOpen(null)).toBe(false);
  });

  test('a staff member closes their own shift', () => {
    expect(canCloseShift({ user: staff, shift: openShift }).ok).toBe(true);
  });

  test('a staff member cannot close someone else\u2019s shift', () => {
    const result = canCloseShift({ user: otherStaff, shift: openShift });
    expect(result.ok).toBe(false);
    expect(result.reason).toMatch(/own shift/i);
  });

  test('a manager or administrator closes anyone\u2019s shift', () => {
    expect(canCloseShift({ user: manager, shift: openShift }).ok).toBe(true);
    expect(canCloseShift({ user: admin, shift: openShift }).ok).toBe(true);
  });

  test('the owner may always close', () => {
    const result = canCloseShift({
      user: otherStaff,
      shift: openShift,
      isOwner: true,
    });
    expect(result.ok).toBe(true);
  });

  test('one open shift at a time per person', () => {
    expect(openShiftProblem([]).ok).toBe(true);
    expect(openShiftProblem([openShift]).ok).toBe(false);
    expect(openShiftProblem([openShift]).reason).toMatch(
      /already have an open shift/i
    );
  });

  test('the float and the count may not be negative', () => {
    expect(validateOpeningFloat('5000').ok).toBe(true);
    expect(validateOpeningFloat('5000').amount).toBe(5000);
    expect(validateOpeningFloat(-1).ok).toBe(false);
    expect(validateClose({ shift: openShift, cashCounted: -5 }).ok).toBe(false);
  });

  test('a closed shift cannot be closed twice', () => {
    const result = validateClose({ shift: closedShift, cashCounted: 1000 });
    expect(result.ok).toBe(false);
    expect(result.reason).toMatch(/already closed/i);
  });
});