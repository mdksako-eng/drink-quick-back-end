// utils/orderVoid.js
// Voiding an order: who may do it, what a void requires, what it restores and
// how it shows up in the numbers. Pure — no Express, no DB — so every rule below
// is unit tested.
//
// Why an order is voided rather than deleted: the Z-report must stay honest.
// A deleted order silently changes yesterday's cash-up; a VOID is visible — it
// keeps who/when/why, restores the stock, stops counting as a sale, and is
// reported separately on the shift report.

/** An order that was voided carries the timestamp of the void. */
function isVoided(order) {
  return !!(order && order.voided_at);
}

/**
 * An order that was taken off the sales without a void trace.
 *
 * Two different things put `is_active = false` on a row:
 *   * a VOID (`POST /orders/:id/void`), which also stamps `voided_at` and puts
 *     the stock back, and
 *   * a CANCEL (`POST /orders/:id/cancel`), used when the sale never really
 *     happened — the app writes the order row before it commits the stock, so a
 *     refused commit leaves a row that must stop counting but must NOT restore
 *     stock (nothing, or only some lines, were ever taken off the shelf).
 *
 * Either way the row stops counting as a sale; only the void has a timestamp.
 */
function isInactive(order) {
  return !!(order && order.is_active === false);
}

/** How long a staff member may correct a sale they rang themselves. */
const STAFF_CORRECTION_WINDOW_MS = 10 * 60 * 1000;

/**
 * Who may void (or restore) an order:
 *   * the company owner, and
 *   * any manager / administrator;
 *   * **a staff member, but only for a sale they rang themselves, within
 *     `STAFF_CORRECTION_WINDOW_MS`** — the classic mistake (wrong drink, wrong
 *     quantity) is noticed immediately, and sending the customer away to wait for
 *     a manager is worse than letting the cashier correct it. It stays auditable:
 *     the void still records who/when/why, restores the stock and shows on the
 *     shift report, so a manager sees every correction.
 */
function canVoidOrder({
  user,
  isOwner = false,
  order = null,
  now = Date.now(),
  windowMs = STAFF_CORRECTION_WINDOW_MS,
} = {}) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (isOwner) return { ok: true };
  const role = (user.role || '').toString().trim().toLowerCase();
  if (role === 'manager' || role === 'administrator' || role === 'admin') {
    return { ok: true };
  }

  if (role === 'staff') {
    if (!order) {
      return { ok: false, reason: 'Staff can only correct their own sale — ask a manager' };
    }
    const owner = String(order.staff_name || '').trim().toLowerCase();
    const mine = owner.length > 0 &&
      owner === String(user.username || '').trim().toLowerCase();
    const soldAt = order.date ? new Date(order.date).getTime() : NaN;
    const withinWindow = Number.isFinite(soldAt) && now >= soldAt && (now - soldAt) <= windowMs;
    if (mine && withinWindow) return { ok: true, staffWindow: true };
    return {
      ok: false,
      reason: mine
        ? `A staff member can only correct their own sale within ${Math.round(windowMs / 60000)} minutes — ask a manager`
        : 'Staff can only correct their own sale — ask a manager',
    };
  }

  return { ok: false, reason: 'Only a manager can void an order' };
}

/**
 * Can this order be voided right now?
 * A reason is required: "why was this sale cancelled" is the whole point.
 */
function validateVoid({ order, reason } = {}) {
  if (!order) return { ok: false, reason: 'Unknown order' };
  if (isVoided(order)) return { ok: false, reason: 'This order is already voided' };
  const text = (reason || '').toString().trim();
  if (!text) return { ok: false, reason: 'A reason is required to void an order' };
  if (text.length > 200) {
    return { ok: false, reason: 'The reason is too long (200 characters max)' };
  }
  return { ok: true, reason: text };
}

/** Can a voided order be put back? */
function validateRestore({ order } = {}) {
  if (!order) return { ok: false, reason: 'Unknown order' };
  if (!isVoided(order)) return { ok: false, reason: 'This order is not voided' };
  return { ok: true };
}

/** The order's items, whether they arrive as JSON text or as an array. */
function parseItems(items) {
  let list = items;
  if (typeof list === 'string') {
    try {
      list = JSON.parse(list);
    } catch (_) {
      return [];
    }
  }
  return Array.isArray(list) ? list : [];
}

/**
 * What the void must put back on the shelf.
 *
 * Orders store either one entry per sold unit (the app's Drink JSON) or a line
 * with a quantity (the local OrderItem shape), so both are handled: count the
 * entries when there is no quantity, otherwise trust it.
 *
 * @returns {Array<{drinkId: (string|number|null), drinkName: string, quantity: number}>}
 */
function stockToRestore(items) {
  const merged = new Map();
  for (const item of parseItems(items)) {
    if (!item || typeof item !== 'object') continue;
    const drinkId = item.id ?? item.drinkId ?? item.drink_id ?? null;
    const drinkName = (item.name ?? item.drinkName ?? item.drink_name ?? '')
      .toString()
      .trim();
    const rawQuantity = Number(item.quantity);
    const quantity = Number.isFinite(rawQuantity) && rawQuantity > 0
      ? rawQuantity
      : 1;
    const key = drinkId != null ? `id:${drinkId}` : `name:${drinkName}`;
    if (key === 'name:' || (drinkId == null && !drinkName)) continue;

    const entry = merged.get(key) || { drinkId, drinkName, quantity: 0 };
    entry.quantity += quantity;
    merged.set(key, entry);
  }
  return [...merged.values()];
}

/**
 * The corrections of a shift window, for the Z-report: how many and how much
 * value was taken off the sales after the fact.
 *
 * A void (stock put back, who/why recorded) and a cancellation (the sale never
 * completed, so nothing was put back) both land here, so a manager always sees
 * what was corrected — including a row the till cancelled on its own. Rows that
 * simply never carried a flag are ignored.
 */
function summariseVoids(orders) {
  let count = 0;
  let value = 0;
  for (const order of orders || []) {
    if (!isVoided(order) && !isInactive(order)) continue;
    count += 1;
    const parsed = typeof order.total_amount === 'number'
      ? order.total_amount
      : parseFloat(order.total_amount);
    value += Number.isFinite(parsed) ? parsed : 0;
  }
  return {
    voidCount: count,
    voidValue: Math.round(value * 100) / 100,
  };
}

module.exports = {
  STAFF_CORRECTION_WINDOW_MS,
  isVoided,
  isInactive,
  canVoidOrder,
  validateVoid,
  validateRestore,
  parseItems,
  stockToRestore,
  summariseVoids,
};
