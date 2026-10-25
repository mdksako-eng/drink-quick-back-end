// tests/container_ledger.test.js
// Returnable containers (crates and bottles) a customer holds.
//
// The balance is money standing in someone's yard, so the rules are pinned here:
// who may record what, and — most importantly — that the pile can never go below
// zero (nobody takes back or writes off more than is actually out).
const {
  CONTAINER_KINDS,
  canRecordContainers,
  canWriteOff,
  canManageTypes,
  canDecideKind,
  validateQuantity,
  sumContainers,
  outstandingFor,
  outstandingByType,
  validateMovement,
  orderByOutstanding,
} = require('../utils/containerLedger');

const staff = { id: 7, role: 'Staff', company_id: 42 };
const manager = { id: 3, role: 'Manager', company_id: 42 };
const admin = { id: 1, role: 'Administrator', company_id: 42 };
const customer = { id: 9, role: 'Customer', company_id: 42 };

const crate = { id: 1, name: 'Crate 33cl', depositValue: 1000 };
const bottle = { id: 2, name: 'Bottle 65cl', depositValue: 100 };

describe('container permissions', () => {
  test('staff hand out and take back containers at the counter', () => {
    expect(canRecordContainers(staff).ok).toBe(true);
    expect(canDecideKind(staff, 'out').ok).toBe(true);
    expect(canDecideKind(staff, 'back').ok).toBe(true);
  });

  test('a write-off is stock disappearing, so only a manager may do it', () => {
    expect(canDecideKind(staff, 'writeoff').ok).toBe(false);
    expect(canWriteOff(staff).ok).toBe(false);
    expect(canWriteOff(manager).ok).toBe(true);
    expect(canWriteOff(admin).ok).toBe(true);
  });

  test('the container catalogue itself is shop setup, so a manager owns it', () => {
    expect(canManageTypes(staff).ok).toBe(false);
    expect(canManageTypes(manager).ok).toBe(true);
    expect(canManageTypes(null).ok).toBe(false);
  });

  test('a customer account records nothing, and nobody is anonymous', () => {
    expect(canRecordContainers(customer).ok).toBe(false);
    expect(canRecordContainers(null).ok).toBe(false);
    expect(canWriteOff(null).ok).toBe(false);
  });

  test('an unknown movement is refused before any role check', () => {
    const result = canDecideKind(manager, 'stolen');
    expect(result.ok).toBe(false);
    expect(CONTAINER_KINDS).toEqual(['out', 'back', 'writeoff']);
  });
});

describe('quantities', () => {
  test('a whole number of containers greater than zero', () => {
    expect(validateQuantity(1).value).toBe(1);
    expect(validateQuantity('24').value).toBe(24);
  });

  test('zero, negatives, fractions and words are refused', () => {
    expect(validateQuantity(0).ok).toBe(false);
    expect(validateQuantity(-3).ok).toBe(false);
    expect(validateQuantity(1.5).ok).toBe(false);
    expect(validateQuantity('two').ok).toBe(false);
    expect(validateQuantity(null).ok).toBe(false);
  });
});

describe('the balance is summed, never stored', () => {
  const entries = [
    { containerTypeId: 1, kind: 'out', quantity: 5 },
    { containerTypeId: 1, kind: 'back', quantity: 2 },
    { containerTypeId: 1, kind: 'writeoff', quantity: 1 },
    { containerTypeId: 2, kind: 'out', quantity: 3 },
  ];

  test('out - back - writeoff', () => {
    expect(sumContainers(entries)).toEqual({
      out: 8,
      back: 2,
      writtenOff: 1,
      outstanding: 5,
    });
  });

  test('per container type, ignoring the others', () => {
    expect(outstandingFor(entries, 1)).toBe(2);
    expect(outstandingFor(entries, 2)).toBe(3);
    expect(outstandingFor(entries, 99)).toBe(0);
  });

  test('an empty ledger holds nothing, and unknown kinds are ignored', () => {
    expect(sumContainers([]).outstanding).toBe(0);
    expect(sumContainers(null).outstanding).toBe(0);
    expect(
      sumContainers([{ containerTypeId: 1, kind: '?', quantity: 9 }]).outstanding
    ).toBe(0);
  });

  test('a type with nothing outstanding is left out of the list', () => {
    const rows = outstandingByType([crate, bottle], [
      { containerTypeId: 1, kind: 'out', quantity: 4 },
      { containerTypeId: 1, kind: 'back', quantity: 4 },
      { containerTypeId: 2, kind: 'out', quantity: 6 },
    ]);
    expect(rows).toHaveLength(1);
    expect(rows[0].containerTypeId).toBe(2);
    expect(rows[0].outstanding).toBe(6);
  });

  test('the deposit is informational only (containers are goods, not cash)', () => {
    const rows = outstandingByType([crate, bottle], [
      { containerTypeId: 1, kind: 'out', quantity: 3 },
      { containerTypeId: 2, kind: 'out', quantity: 7 },
    ]);
    // biggest pile first, and the value is deposit x outstanding
    expect(rows.map((r) => r.outstanding)).toEqual([7, 3]);
    expect(rows[0].value).toBe(700);
    expect(rows[1].value).toBe(3000);
    expect(
      outstandingByType([{ id: 3, name: 'No deposit' }], [
        { containerTypeId: 3, kind: 'out', quantity: 2 },
      ])[0].value
    ).toBe(0);
  });
});

describe('a movement is refused when the pile cannot cover it', () => {
  test('handing out is always allowed', () => {
    const result = validateMovement({
      user: staff,
      kind: 'out',
      quantity: 24,
      outstanding: 0,
    });
    expect(result.ok).toBe(true);
  });

  test('taking back exactly what is out is allowed (the pile reaches zero)', () => {
    const result = validateMovement({
      user: staff,
      kind: 'back',
      quantity: 5,
      outstanding: 5,
    });
    expect(result.ok).toBe(true);
    expect(result.value).toBe(5);
  });

  test('taking back more than is out is refused, naming the number held', () => {
    const result = validateMovement({
      user: staff,
      kind: 'back',
      quantity: 6,
      outstanding: 5,
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toContain('Only 5');
  });

  test('writing off more than is out is refused, and staff cannot write off', () => {
    expect(
      validateMovement({ user: manager, kind: 'writeoff', quantity: 6, outstanding: 5 }).ok
    ).toBe(false);
    expect(
      validateMovement({ user: manager, kind: 'writeoff', quantity: 5, outstanding: 5 }).ok
    ).toBe(true);
    const staffWriteOff = validateMovement({
      user: staff,
      kind: 'writeoff',
      quantity: 1,
      outstanding: 5,
    });
    expect(staffWriteOff.ok).toBe(false);
    expect(staffWriteOff.reason).toContain('manager');
  });

  test('a bad quantity or an unknown kind never reaches the ledger', () => {
    expect(
      validateMovement({ user: staff, kind: 'out', quantity: 0, outstanding: 0 }).ok
    ).toBe(false);
    expect(
      validateMovement({ user: manager, kind: 'gone', quantity: 1, outstanding: 5 }).ok
    ).toBe(false);
  });
});

describe('who is holding my containers', () => {
  test('biggest holder first, empty hands dropped', () => {
    const rows = orderByOutstanding([
      { customerId: 1, customerNumber: '000001', outstanding: 3 },
      { customerId: 2, customerNumber: '000002', outstanding: 12 },
      { customerId: 3, customerNumber: '000003', outstanding: 0 },
    ]);
    expect(rows.map((r) => r.customerNumber)).toEqual(['000002', '000001']);
  });

  test('a tie is broken by the customer number, so the list is stable', () => {
    const rows = orderByOutstanding([
      { customerNumber: '000009', outstanding: 2 },
      { customerNumber: '000004', outstanding: 2 },
    ]);
    expect(rows.map((r) => r.customerNumber)).toEqual(['000004', '000009']);
  });
});
