// tests/order_void.test.js — staff correction window
// A staff member may correct a sale they rang themselves, but only inside the
// window; every other case stays manager-only.
const {
  canVoidOrder,
  STAFF_CORRECTION_WINDOW_MS,
} = require('../utils/orderVoid');

describe('canVoidOrder — staff correction window', () => {
  const now = Date.parse('2026-10-21T20:00:00.000Z');
  const staff = { role: 'Staff', username: 'onean' };
  const mine = (minutesAgo) => ({
    staff_name: 'onean',
    date: new Date(now - minutesAgo * 60000).toISOString(),
  });

  test('the window is ten minutes', () => {
    expect(STAFF_CORRECTION_WINDOW_MS).toBe(10 * 60 * 1000);
  });

  test('a staff member may void their own sale inside the window', () => {
    expect(canVoidOrder({ user: staff, order: mine(5), now }).ok).toBe(true);
    expect(canVoidOrder({ user: staff, order: mine(5), now }).staffWindow).toBe(true);
  });

  test('the same sale is refused after the window', () => {
    expect(canVoidOrder({ user: staff, order: mine(11), now }).ok).toBe(false);
  });

  test('the boundary is inclusive', () => {
    expect(canVoidOrder({ user: staff, order: mine(10), now }).ok).toBe(true);
  });

  test('another cashier\'s sale is refused', () => {
    const other = { staff_name: 'ama', date: new Date(now).toISOString() };
    const verdict = canVoidOrder({ user: staff, order: other, now });
    expect(verdict.ok).toBe(false);
    expect(verdict.reason).toMatch(/their own sale/i);
  });

  test('a sale with no staff attribution is refused', () => {
    expect(canVoidOrder({
      user: staff, order: { staff_name: '', date: new Date(now).toISOString() }, now,
    }).ok).toBe(false);
  });

  test('a missing or future date is refused (no endless window)', () => {
    expect(canVoidOrder({ user: staff, order: { staff_name: 'onean' }, now }).ok).toBe(false);
    const future = { staff_name: 'onean', date: new Date(now + 300000).toISOString() };
    expect(canVoidOrder({ user: staff, order: future, now }).ok).toBe(false);
  });

  test('without an order, staff are still refused', () => {
    expect(canVoidOrder({ user: staff, now }).ok).toBe(false);
  });

  test('managers keep unrestricted rights', () => {
    expect(canVoidOrder({ user: { role: 'Manager' }, order: mine(600), now }).ok).toBe(true);
    expect(canVoidOrder({ user: { role: 'Admin' }, now }).ok).toBe(true);
    expect(canVoidOrder({ user: { role: 'Staff' }, isOwner: true, now }).ok).toBe(true);
  });

  test('a customer account never voids', () => {
    expect(canVoidOrder({ user: { role: 'Customer' }, order: mine(1), now }).ok).toBe(false);
  });
});
