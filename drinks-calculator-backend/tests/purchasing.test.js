// tests/purchasing.test.js
// Buying stock: who may commit the shop's money, what an order may contain, and
// what receiving writes onto the shelf.
const {
  ORDER_STATUSES,
  canWriteOrders,
  canReceive,
  canMoveStatus,
  validateLine,
  validateLines,
  orderTotal,
  receivingPlan,
} = require('../utils/purchasing');

const staff = { id: 7, role: 'Staff', company_id: 42 };
const manager = { id: 3, role: 'Manager', company_id: 42 };
const admin = { id: 1, role: 'Administrator', company_id: 42 };
const customer = { id: 9, role: 'Customer', company_id: 42 };

describe('who may do what', () => {
  test('a manager commits the shop money', () => {
    expect(canWriteOrders(manager).ok).toBe(true);
    expect(canWriteOrders(admin).ok).toBe(true);
    expect(canWriteOrders(staff).ok).toBe(false);
    expect(canWriteOrders(null).ok).toBe(false);
  });

  test('receiving is a physical fact at the door, so staff may record it', () => {
    expect(canReceive(staff).ok).toBe(true);
    expect(canReceive(manager).ok).toBe(true);
    expect(canReceive(customer).ok).toBe(false);
    expect(canReceive(null).ok).toBe(false);
  });
});

describe('the life of an order', () => {
  test('a draft is sent or dropped', () => {
    expect(canMoveStatus('draft', 'sent').ok).toBe(true);
    expect(canMoveStatus('draft', 'cancelled').ok).toBe(true);
    expect(canMoveStatus('draft', 'received').ok).toBe(false);
  });

  test('a sent order is received or cancelled', () => {
    expect(canMoveStatus('sent', 'received').ok).toBe(true);
    expect(canMoveStatus('sent', 'cancelled').ok).toBe(true);
    expect(canMoveStatus('sent', 'draft').ok).toBe(false);
  });

  test('received and cancelled are terminal', () => {
    // A delivery that arrived is a fact; correcting it is a stock adjustment
    // with its own reason, never a quiet status flip.
    expect(canMoveStatus('received', 'sent').ok).toBe(false);
    expect(canMoveStatus('received', 'cancelled').ok).toBe(false);
    expect(canMoveStatus('cancelled', 'sent').ok).toBe(false);
  });

  test('unknown and repeated statuses are refused', () => {
    expect(canMoveStatus('draft', 'gone').ok).toBe(false);
    expect(canMoveStatus('draft', 'draft').ok).toBe(false);
    expect(ORDER_STATUSES).toEqual(['draft', 'sent', 'received', 'cancelled']);
  });
});

describe('a line', () => {
  test('a whole number of units at a cost', () => {
    const result = validateLine({
      drinkId: '1782946175142',
      drinkName: 'coke',
      quantity: 24,
      unitCost: 600,
    });
    expect(result.ok).toBe(true);
    expect(result.value).toMatchObject({ quantity: 24, unitCost: 600 });
  });

  test('the cost is optional and defaults to zero, to the centime', () => {
    expect(validateLine({ drinkName: 'coke', quantity: 1 }).value.unitCost).toBe(0);
    expect(
      validateLine({ drinkName: 'coke', quantity: 1, unitCost: 12.345 }).value.unitCost
    ).toBe(12.35);
  });

  test('a line without a drink, or with a bad quantity or cost, is refused', () => {
    expect(validateLine({ quantity: 1 }).ok).toBe(false);
    expect(validateLine({ drinkName: 'coke', quantity: 0 }).ok).toBe(false);
    expect(validateLine({ drinkName: 'coke', quantity: -3 }).ok).toBe(false);
    expect(validateLine({ drinkName: 'coke', quantity: 1.5 }).ok).toBe(false);
    expect(validateLine({ drinkName: 'coke', quantity: 'two' }).ok).toBe(false);
    expect(validateLine({ drinkName: 'coke', quantity: 1, unitCost: -5 }).ok).toBe(false);
  });

  test('a line is identified by its drink, id or name', () => {
    expect(validateLine({ drinkId: 'd1', quantity: 1 }).ok).toBe(true);
    expect(validateLine({ drinkName: '   ', quantity: 1 }).ok).toBe(false);
  });
});

describe('the order as a whole', () => {
  test('an order with no lines is not an order, and one bad line stops it', () => {
    expect(validateLines([]).ok).toBe(false);
    expect(validateLines(null).ok).toBe(false);
    const mixed = validateLines([
      { drinkName: 'coke', quantity: 2, unitCost: 500 },
      { drinkName: 'beer', quantity: 0 },
    ]);
    expect(mixed.ok).toBe(false);
  });

  test('every line is kept when they are all valid', () => {
    const result = validateLines([
      { drinkName: 'coke', quantity: 2, unitCost: 500 },
      { drinkName: 'beer', quantity: 1, unitCost: 1000 },
    ]);
    expect(result.ok).toBe(true);
    expect(result.value).toHaveLength(2);
  });

  test('the total is units x cost, to the centime', () => {
    expect(
      orderTotal([
        { quantity: 3, unitCost: 1000 },
        { quantity: 2, unitCost: 250.5 },
      ])
    ).toBe(3501);
    expect(orderTotal([])).toBe(0);
    expect(orderTotal([{ quantity: 3 }])).toBe(0);
  });
});

describe('what receiving writes', () => {
  test('one movement per line, at the cost actually paid', () => {
    const plan = receivingPlan([
      { drinkId: 'd1', drinkName: 'coke', quantity: 24, unitCost: 600 },
      { drinkId: null, drinkName: 'beer', quantity: 6, unitCost: 1000 },
    ]);
    expect(plan).toEqual([
      { drinkId: 'd1', drinkName: 'coke', quantity: 24, unitCost: 600 },
      { drinkId: null, drinkName: 'beer', quantity: 6, unitCost: 1000 },
    ]);
  });

  test('an empty order receives nothing', () => {
    expect(receivingPlan([])).toEqual([]);
    expect(receivingPlan(null)).toEqual([]);
  });
});
