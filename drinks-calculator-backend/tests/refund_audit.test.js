// tests/refund_audit.test.js
// Refunds are recorded, not executed here — so the record must be strict, and the
// audit row must never be able to fail the action it documents.
const { validateRefund, buildRefundRow } = require('../utils/refundRecord');
const { buildEntry, isValidEntry, record, MAX_DETAIL } = require('../utils/auditLog');

describe('validateRefund', () => {
  const base = { amount: 500, reason: 'Customer changed their mind', orderTotal: 5000 };

  test('a normal refund is accepted', () => {
    const verdict = validateRefund({ ...base, reference: 'CAM-123' });
    expect(verdict.ok).toBe(true);
    expect(verdict.amount).toBe(500);
    expect(verdict.note).toBeNull();
  });

  test('an amount must be positive and numeric', () => {
    expect(validateRefund({ ...base, amount: 0 }).ok).toBe(false);
    expect(validateRefund({ ...base, amount: -5 }).ok).toBe(false);
    expect(validateRefund({ ...base, amount: 'abc' }).ok).toBe(false);
    expect(validateRefund({ ...base, amount: null }).ok).toBe(false);
  });

  test('a reason is required, and bounded', () => {
    expect(validateRefund({ ...base, reason: '   ' }).ok).toBe(false);
    expect(validateRefund({ ...base, reason: 'x'.repeat(201) }).ok).toBe(false);
  });

  test('a refund cannot exceed what is left on the order', () => {
    const verdict = validateRefund({ ...base, amount: 6000 });
    expect(verdict.ok).toBe(false);
    expect(verdict.reason).toMatch(/left to refund/);
  });

  test('earlier refunds reduce what is refundable', () => {
    const verdict = validateRefund({
      ...base, amount: 600, orderTotal: 1000, alreadyRefunded: 500,
    });
    expect(verdict.ok).toBe(false);
    expect(validateRefund({
      ...base, amount: 500, orderTotal: 1000, alreadyRefunded: 500,
    }).ok).toBe(true);
  });

  test('a missing provider reference is allowed but flagged', () => {
    expect(validateRefund(base).note).toMatch(/no provider reference/);
  });

  test('amounts are rounded to 2 decimals', () => {
    expect(validateRefund({ ...base, amount: 10.005 }).amount).toBe(10.01);
  });
});

describe('buildRefundRow', () => {
  test('stores who, why and the provider reference', () => {
    const at = new Date('2026-10-21T20:00:00Z');
    const row = buildRefundRow({
      companyId: 42, orderId: 'o1', amount: 500, reason: ' wrong drink ',
      reference: ' CAM-9 ', performedBy: 7, performedByName: 'onean', createdAt: at,
    });
    expect(row).toEqual({
      company_id: 42, order_id: 'o1', amount: 500, reason: 'wrong drink',
      reference: 'CAM-9', method: 'card', performed_by: 7,
      performed_by_name: 'onean', status: 'approved', created_at: at,
    });
  });
});

describe('auditLog', () => {
  test('an entry carries actor, action, target and detail', () => {
    const entry = buildEntry({
      companyId: 42, actorId: 7, actorName: 'onean', action: 'refund.record',
      target: 'order:o1', detail: '500 XAF — wrong drink',
    });
    expect(isValidEntry(entry)).toBe(true);
    expect(entry.action).toBe('refund.record');
    expect(entry.target).toBe('order:o1');
  });

  test('an entry without an action is refused', () => {
    expect(isValidEntry(buildEntry({ action: '  ' }))).toBe(false);
  });

  test('long text is truncated, never rejected', () => {
    const entry = buildEntry({ action: 'a', detail: 'x'.repeat(2000) });
    expect(entry.detail.length).toBe(MAX_DETAIL);
  });

  test('record() writes one row and returns true', async () => {
    const calls = [];
    const db = { query: async (sql, params) => { calls.push(params); return { rowCount: 1 }; } };
    await expect(record(db, { action: 'user.block', actorName: 'admin' })).resolves.toBe(true);
    expect(calls).toHaveLength(1);
    expect(calls[0][3]).toBe('user.block');
  });

  test('record() never throws when the table is missing', async () => {
    const db = { query: async () => { throw new Error('relation "audit_log" does not exist'); } };
    await expect(record(db, { action: 'user.block' })).resolves.toBe(false);
  });

  test('record() refuses an empty action without touching the database', async () => {
    let called = false;
    const db = { query: async () => { called = true; return {}; } };
    await expect(record(db, {})).resolves.toBe(false);
    expect(called).toBe(false);
  });
});
