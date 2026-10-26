// tests/order_payment.test.js
// How a sale's money is split at the counter: full, overpaid (change), or paid
// in part with the rest on the customer's tab.
//
// The Z-report derives collected = sum(amount_paid) and on_credit = sales -
// collected, so an inconsistent split makes the cash-up lie — these rules are
// what stops one reaching the table.
const {
  splitPayment,
  goesOnTab,
  validateOrderPayment,
} = require('../utils/orderPayment');

describe('splitPayment', () => {
  test('a sale paid in full leaves nothing owed and no change', () => {
    expect(splitPayment({ total: 5000, paid: 5000 })).toMatchObject({
      ok: true,
      total: 5000,
      paid: 5000,
      tabAmount: 0,
      change: 0,
    });
  });

  test('paying more is change for the customer, never a negative tab', () => {
    const split = splitPayment({ total: 1500, paid: 2000 });
    expect(split.change).toBe(500);
    expect(split.tabAmount).toBe(0);
  });

  test('paying less puts the remainder on the tab, never a negative change', () => {
    const split = splitPayment({ total: 5000, paid: 2000 });
    expect(split.tabAmount).toBe(3000);
    expect(split.change).toBe(0);
  });

  test('money is kept to two decimals', () => {
    const split = splitPayment({ total: 5000.005, paid: 2000.004 });
    expect(split.total).toBe(5000.01);
    expect(split.paid).toBe(2000);
    expect(split.tabAmount).toBe(3000.01);
  });

  test('a free sale (total 0) is still a sale', () => {
    expect(splitPayment({ total: 0, paid: 0 }).tabAmount).toBe(0);
  });

  test('nonsense numbers are refused instead of guessed', () => {
    expect(splitPayment({ total: null, paid: 100 }).ok).toBe(false);
    expect(splitPayment({ total: 100, paid: null }).ok).toBe(false);
    expect(splitPayment({ total: 100, paid: 'five' }).ok).toBe(false);
    expect(splitPayment({ total: 100, paid: -1 }).ok).toBe(false);
    expect(splitPayment({ total: -1, paid: 0 }).ok).toBe(false);
  });
});

describe('goesOnTab', () => {
  test('only an underpaid sale does', () => {
    expect(goesOnTab({ total: 5000, paid: 2000 })).toBe(true);
    expect(goesOnTab({ total: 5000, paid: 5000 })).toBe(false);
    expect(goesOnTab({ total: 5000, paid: 6000 })).toBe(false);
  });
});

describe('validateOrderPayment', () => {
  const customer = 42;

  test('a sale paid in full needs no customer account', () => {
    const result = validateOrderPayment({
      total: 5000,
      paid: 5000,
      tabAmount: 0,
      customerId: null,
    });
    expect(result.ok).toBe(true);
    expect(result.tabAmount).toBe(0);
  });

  test('a part-paid sale is allowed when the tab names an account', () => {
    const result = validateOrderPayment({
      total: 5000,
      paid: 2000,
      tabAmount: 3000,
      customerId: customer,
    });
    expect(result.ok).toBe(true);
    expect(result.tabAmount).toBe(3000);
    expect(result.change).toBe(0);
  });

  test('a tab that belongs to nobody is refused', () => {
    const result = validateOrderPayment({
      total: 5000,
      paid: 2000,
      tabAmount: 3000,
      customerId: null,
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toContain('customer account');
  });

  test('a tab that does not match the arithmetic is refused, showing the sum', () => {
    const result = validateOrderPayment({
      total: 5000,
      paid: 2000,
      tabAmount: 1000,
      customerId: customer,
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toContain('3000');
  });

  test('a negative tab is refused', () => {
    expect(
      validateOrderPayment({ total: 5000, paid: 5000, tabAmount: -100, customerId: customer }).ok
    ).toBe(false);
  });

  test('an older client that sends no tab still cannot hide a debt', () => {
    // No tabAmount sent: the remainder is derived, and it still needs an account.
    const refused = validateOrderPayment({
      total: 5000,
      paid: 1000,
      customerId: null,
    });
    expect(refused.ok).toBe(false);
    expect(refused.reason).toContain('customer account');

    const allowed = validateOrderPayment({
      total: 5000,
      paid: 1000,
      customerId: customer,
    });
    expect(allowed.ok).toBe(true);
    expect(allowed.tabAmount).toBe(4000);
  });

  test('a nonsense sale never reaches the table', () => {
    expect(validateOrderPayment({ total: 5000, paid: 'lots', customerId: customer }).ok).toBe(false);
    expect(validateOrderPayment({ total: null, paid: 100, customerId: customer }).ok).toBe(false);
  });
});
