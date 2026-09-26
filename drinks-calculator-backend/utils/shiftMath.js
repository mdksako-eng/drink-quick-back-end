// utils/shiftMath.js
// Pure shift / cash-up arithmetic for the Z-report. No Express, no DB writes —
// so every number below is unit tested.
//
// A shift belongs to the staff member who opened it (one open shift per user,
// enforced by a partial unique index). Its Z-report is computed from the orders
// taken inside its time window and then FROZEN onto the row when it closes, so
// a report that was printed once never changes afterwards.

/** Money helper: Postgres NUMERIC arrives as a string ("5000.00"). */
function num(value) {
  if (value == null || value === '') return 0;
  const parsed = typeof value === 'number' ? value : parseFloat(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

/** Rounds to 2 decimals so float noise never shows up in a variance. */
function money(value) {
  return Math.round(num(value) * 100) / 100;
}

/**
 * Totals for the orders taken during a shift.
 *  - sales       = what was billed (order totals)
 *  - collected   = what was actually paid at the counter
 *  - onCredit    = what went on a tab (balance)
 */
function summariseOrders(orders) {
  let sales = 0;
  let collected = 0;
  for (const order of orders || []) {
    sales += num(order && order.total_amount);
    collected += num(order && order.amount_paid);
  }
  return {
    orderCount: (orders || []).length,
    sales: money(sales),
    collected: money(collected),
    onCredit: money(sales - collected),
  };
}

/**
 * The mobile-money / cash breakdown, when the caller passes the shift's
 * successful payment transactions (they carry the method).
 */
function summarisePayments(payments) {
  const byMethod = {};
  let counted = 0;
  for (const payment of payments || []) {
    const status = (payment && payment.status ? String(payment.status) : '').toLowerCase();
    if (status && status !== 'success' && status !== 'successful' && status !== 'completed') {
      continue;
    }
    const method = (payment && payment.payment_method)
      ? String(payment.payment_method)
      : 'other';
    const amount = num(payment && payment.amount);
    byMethod[method] = money(num(byMethod[method]) + amount);
    counted += amount;
  }
  return { byMethod, total: money(counted) };
}

/**
 * The whole Z-report for a shift window.
 * `payments` is optional: without it the report still works from the orders
 * (a till with no network keeps taking sales).
 */
function summariseShift({ shift, orders, payments }) {
  const openingFloat = money(shift && shift.opening_float);
  const payouts = money(shift && shift.cash_payouts);
  const orderTotals = summariseOrders(orders);
  const paymentTotals = summarisePayments(payments);

  // What should be in the drawer: the float, plus what was collected in cash,
  // minus anything paid out of the till during the shift.
  const expectedCash = money(openingFloat + orderTotals.collected - payouts);
  const counted = shift && (shift.status === 'closed' || shift.cash_counted != null)
    ? money(shift.cash_counted)
    : null;

  return {
    openingFloat,
    payouts,
    expectedCash,
    counted,
    variance: counted == null ? null : money(counted - expectedCash),
    byMethod: paymentTotals.byMethod,
    paymentsTotal: paymentTotals.total,
    ...orderTotals,
  };
}

/** How far the drawer is off: positive = too much cash, negative = missing. */
function cashVariance({ counted, expectedCash }) {
  return money(num(counted) - num(expectedCash));
}

/** A shift is closed once it has a timestamp; open ones are still running. */
function isOpen(shift) {
  return !!shift && shift.status === 'open';
}

/**
 * Who may close a shift:
 *   * the staff member who opened it (they cash up their own till), or
 *   * any manager / administrator (they are accountable for the shop).
 */
function canCloseShift({ user, shift, isOwner = false }) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (!shift) return { ok: false, reason: 'Unknown shift' };
  if (isOwner) return { ok: true };
  const role = (user.role || '').toString().trim().toLowerCase();
  if (role === 'manager' || role === 'administrator' || role === 'admin') {
    return { ok: true };
  }
  if (Number(shift.staff_user_id) === Number(user.id)) return { ok: true };
  return { ok: false, reason: 'You can only close your own shift' };
}

/** A staff member has at most one open shift at a time. */
function openShiftProblem(openShifts) {
  if (openShifts && openShifts.length > 0) {
    return {
      ok: false,
      reason: 'You already have an open shift — close it before starting another',
    };
  }
  return { ok: true };
}

/** The float handed to the till must be a real, non-negative amount. */
function validateOpeningFloat(value) {
  const amount = num(value);
  if (amount < 0) return { ok: false, reason: 'The opening float cannot be negative' };
  return { ok: true, amount: money(amount) };
}

/** Can this shift be closed right now? */
function validateClose({ shift, cashCounted }) {
  if (!shift) return { ok: false, reason: 'Unknown shift' };
  if (!isOpen(shift)) return { ok: false, reason: 'This shift is already closed' };
  const counted = num(cashCounted);
  if (counted < 0) return { ok: false, reason: 'The counted cash cannot be negative' };
  return { ok: true, counted: money(counted) };
}

module.exports = {
  num,
  money,
  summariseOrders,
  summarisePayments,
  summariseShift,
  cashVariance,
  isOpen,
  canCloseShift,
  openShiftProblem,
  validateOpeningFloat,
  validateClose,
};
