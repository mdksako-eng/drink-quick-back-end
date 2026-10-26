// utils/purchasing.js
// Pure rules for buying stock: suppliers, purchase orders and receiving.
//
// WHY THIS EXISTS
//   The app already RECOMMENDS what to reorder (the forecast) but had no way to
//   turn that into an order, and no memory of what a supplier charges — the
//   project notes said it plainly: "supplier prices are not stored yet". A
//   purchase order is the document that closes that loop, and receiving it is
//   what puts the stock on the shelf at the price actually paid.
//
// WHAT IS A DECISION AND WHAT IS A PHYSICAL FACT
//   * Creating, editing, sending or cancelling an order is a DECISION about the
//     shop's money, so a MANAGER makes it.
//   * Receiving what actually arrived is a PHYSICAL FACT at the door, like a
//     restock, so any staff member may do it — refusing would only stop the
//     delivery from being recorded at all.

const { isManagerRole } = require('./customerApproval');

const ORDER_STATUSES = ['draft', 'sent', 'received', 'cancelled'];

function normalizeRole(role) {
  return (role || '').toString().trim().toLowerCase();
}

/** Creating, editing, sending and cancelling an order is the manager's call. */
function canWriteOrders(user) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (isManagerRole(user.role)) return { ok: true };
  return { ok: false, reason: 'Only a manager can change a purchase order' };
}

/** Receiving a delivery: any role except the customer's own. */
function canReceive(user) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (normalizeRole(user.role) === 'customer') {
    return { ok: false, reason: 'Customers cannot receive stock' };
  }
  return { ok: true };
}

/**
 * Allowed moves. A draft becomes an order (sent) or is dropped (cancelled); an
 * order that was sent can be received or cancelled. Received and cancelled are
 * terminal: a delivery that arrived is a fact, and correcting it is a stock
 * adjustment with its own reason, never a quiet status flip.
 */
const STATUS_TRANSITIONS = {
  draft: ['sent', 'cancelled'],
  sent: ['received', 'cancelled'],
  received: [],
  cancelled: [],
};

function canMoveStatus(from, to) {
  if (!ORDER_STATUSES.includes(to)) {
    return { ok: false, reason: 'Unknown purchase order status' };
  }
  const current = ORDER_STATUSES.includes(from) ? from : 'draft';
  if (current === to) {
    return { ok: false, reason: `The order is already ${to}` };
  }
  if (!(STATUS_TRANSITIONS[current] || []).includes(to)) {
    return { ok: false, reason: `Cannot move a ${current} order to ${to}` };
  }
  return { ok: true };
}

/**
 * One line of an order: a whole number of units at a cost that cannot be
 * negative. Returns { ok, value, reason } so the route answers with the exact
 * message.
 */
function validateLine({ drinkId, drinkName, quantity, unitCost }) {
  const id = drinkId == null || drinkId === '' ? null : String(drinkId);
  const name = (drinkName == null ? '' : String(drinkName)).trim();
  if (!name && !id) {
    return { ok: false, reason: 'A line needs a drink' };
  }

  const qty = Number(quantity);
  if (!Number.isFinite(qty) || !Number.isInteger(qty) || qty <= 0) {
    return { ok: false, reason: 'A line needs a whole number of units above zero' };
  }

  const cost = Number(unitCost == null || unitCost === '' ? 0 : unitCost);
  if (!Number.isFinite(cost) || cost < 0) {
    return { ok: false, reason: 'A unit cost cannot be negative' };
  }

  return {
    ok: true,
    value: {
      drinkId: id,
      drinkName: name,
      quantity: qty,
      unitCost: Math.round(cost * 100) / 100,
    },
  };
}

/** Every line must be valid, and an order with no lines is not an order. */
function validateLines(lines) {
  if (!Array.isArray(lines) || lines.length === 0) {
    return { ok: false, reason: 'A purchase order needs at least one line' };
  }
  const checked = [];
  for (const line of lines) {
    const result = validateLine(line || {});
    if (!result.ok) return result;
    checked.push(result.value);
  }
  return { ok: true, value: checked };
}

/** What the order is worth: units x unit cost, to the centime. */
function orderTotal(lines) {
  const total = (lines || []).reduce((sum, line) => {
    const qty = Number(line && line.quantity) || 0;
    const cost = Number(line && line.unitCost) || 0;
    return sum + qty * cost;
  }, 0);
  return Math.round(total * 100) / 100;
}

/**
 * What receiving writes: one stock movement per line, at the cost actually
 * paid. Pure, so the receiving route stays thin and this is unit tested without
 * a database.
 */
function receivingPlan(lines) {
  return (lines || []).map((line) => ({
    drinkId: line && line.drinkId != null ? String(line.drinkId) : null,
    drinkName: (line && line.drinkName) || '',
    quantity: Number(line && line.quantity) || 0,
    unitCost: Number(line && line.unitCost) || 0,
  }));
}

module.exports = {
  ORDER_STATUSES,
  STATUS_TRANSITIONS,
  canWriteOrders,
  canReceive,
  canMoveStatus,
  validateLine,
  validateLines,
  orderTotal,
  receivingPlan,
};
