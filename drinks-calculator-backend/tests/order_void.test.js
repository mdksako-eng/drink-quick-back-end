/**
 * Voiding an order — the rule that keeps the Z-report honest.
 *
 * Covers the rule the shop asked for: a wrong order is corrected WITH a trace
 * (who/when/why), stops counting as a sale, restores the stock, and is reported
 * separately on the shift report instead of vanishing from it.
 *
 * Run with: npm test
 */
const {
  isVoided,
  canVoidOrder,
  validateVoid,
  validateRestore,
  stockToRestore,
  summariseVoids,
} = require('../utils/orderVoid');

const manager = { id: 5, role: 'Manager' };
const owner = { id: 9, role: 'Manager' };
const staff = { id: 7, role: 'Staff' };

describe('who may void an order', () => {
  test('a manager may', () => {
    expect(canVoidOrder({ user: manager }).ok).toBe(true);
  });

  test('the company owner may', () => {
    expect(canVoidOrder({ user: owner, isOwner: true }).ok).toBe(true);
  });

  test('an administrator may', () => {
    expect(canVoidOrder({ user: { role: 'administrator' } }).ok).toBe(true);
  });

  test('staff may not — they ask a manager', () => {
    const result = canVoidOrder({ user: staff });
    expect(result.ok).toBe(false);
    expect(result.reason).toMatch(/manager/i);
  });

  test('a signed-out caller may not', () => {
    expect(canVoidOrder({}).ok).toBe(false);
  });
});

describe('what a void requires', () => {
  test('a reason is mandatory', () => {
    expect(validateVoid({ order: {}, reason: '' }).ok).toBe(false);
    expect(validateVoid({ order: {}, reason: '   ' }).ok).toBe(false);
    expect(validateVoid({ order: {} }).ok).toBe(false);
  });

  test('the reason is trimmed and returned', () => {
    const result = validateVoid({ order: {}, reason: '  wrong drink  ' });
    expect(result.ok).toBe(true);
    expect(result.reason).toBe('wrong drink');
  });

  test('an over-long reason is refused', () => {
    expect(validateVoid({ order: {}, reason: 'x'.repeat(201) }).ok).toBe(false);
    expect(validateVoid({ order: {}, reason: 'x'.repeat(200) }).ok).toBe(true);
  });

  test('the same order cannot be voided twice', () => {
    const order = { voided_at: '2026-09-27T10:00:00Z' };
    const result = validateVoid({ order, reason: 'typo' });
    expect(result.ok).toBe(false);
    expect(result.reason).toMatch(/already voided/i);
  });

  test('an unknown order is refused', () => {
    expect(validateVoid({ reason: 'typo' }).ok).toBe(false);
  });
});

describe('putting a void back', () => {
  test('only a voided order can be restored', () => {
    expect(validateRestore({ order: {} }).ok).toBe(false);
    expect(validateRestore({ order: { voided_at: 'now' } }).ok).toBe(true);
    expect(validateRestore({}).ok).toBe(false);
  });
});

describe('isVoided', () => {
  test('the timestamp is the flag', () => {
    expect(isVoided({ voided_at: '2026-09-27T10:00:00Z' })).toBe(true);
    expect(isVoided({ voided_at: null })).toBe(false);
    expect(isVoided({})).toBe(false);
    expect(isVoided(null)).toBe(false);
  });
});

describe('stock to put back', () => {
  test('one entry per sold unit is counted', () => {
    const items = [
      { id: 'd1', name: 'Beer' },
      { id: 'd1', name: 'Beer' },
      { id: 'd2', name: 'Water' },
    ];
    expect(stockToRestore(items)).toEqual([
      { drinkId: 'd1', drinkName: 'Beer', quantity: 2 },
      { drinkId: 'd2', drinkName: 'Water', quantity: 1 },
    ]);
  });

  test('a line with a quantity is trusted', () => {
    const items = [{ drinkName: 'Beer', quantity: 3, pricePerUnit: 1000 }];
    expect(stockToRestore(items)).toEqual([
      { drinkId: null, drinkName: 'Beer', quantity: 3 },
    ]);
  });

  test('JSON text (how the column stores it) is accepted', () => {
    const json = JSON.stringify([{ id: 'd1', name: 'Beer' }, { id: 'd1', name: 'Beer' }]);
    expect(stockToRestore(json)).toEqual([
      { drinkId: 'd1', drinkName: 'Beer', quantity: 2 },
    ]);
  });

  test('broken JSON, empty and junk input restore nothing instead of throwing', () => {
    ['not json', '{}', '', null, undefined, [], '[]'].forEach((input) => {
      expect(stockToRestore(input)).toEqual([]);
    });
  });

  test('a zero or missing quantity still means one unit sold', () => {
    expect(stockToRestore([{ id: 'd1', name: 'Beer', quantity: 0 }]))
      .toEqual([{ drinkId: 'd1', drinkName: 'Beer', quantity: 1 }]);
    expect(stockToRestore([{ drinkName: 'Beer' }]))
      .toEqual([{ drinkId: null, drinkName: 'Beer', quantity: 1 }]);
  });

  test('an entry with neither id nor name is skipped', () => {
    expect(stockToRestore([{ quantity: 2 }, null, 'junk'])).toEqual([]);
  });
});

describe('the voids of a shift', () => {
  test('counts and values only the voided orders', () => {
    const orders = [
      { total_amount: 5000, voided_at: null },
      { total_amount: '3000.00', voided_at: '2026-09-27T11:00:00Z' },
      { total_amount: 2000, voided_at: '2026-09-27T12:00:00Z' },
    ];
    expect(summariseVoids(orders)).toEqual({ voidCount: 2, voidValue: 5000 });
  });

  test('nothing voided means nothing to report', () => {
    expect(summariseVoids([{ total_amount: 1000 }])).toEqual({
      voidCount: 0,
      voidValue: 0,
    });
    expect(summariseVoids()).toEqual({ voidCount: 0, voidValue: 0 });
  });
});
