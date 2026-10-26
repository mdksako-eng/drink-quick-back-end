// utils/orderPayment.js
// Pure rules for how a sale's money is split at the counter.
//
// WHY THIS EXISTS
//   A sale can be paid in full, overpaid (the customer gets change), or paid in
//   PART with the rest going on the customer's tab. The Z-report derives its two
//   money lines from exactly these numbers:
//       collected = sum(amount_paid)
//       on_credit = sales - collected          (utils/shiftMath.js)
//   so an order whose amount_paid and tab_amount disagree with its own total
//   makes the cash-up lie. POST /orders used to store whatever the client sent.
//
// WHY tab_amount IS ITS OWN COLUMN
//   `orders.balance` already means "change handed back" for a cash sale
//   (paid - total, positive). A tab means the opposite (total - paid, still
//   owed), so overloading one column with both meanings would make the invoice
//   and the order history ambiguous. The debt gets its own field, and the
//   customer's account is the single source of truth for what is still owed.

const EPSILON = 0.005; // half a centime: money is kept to 2 decimals

function num(value) {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function round2(value) {
  return Math.round(value * 100) / 100;
}

/**
 * What the counter should store for a sale of `total` with `paid` handed over.
 * - change  = what goes back to the customer (paid > total)
 * - tabAmount = what is owed on the customer's account (paid < total)
 * Returns { ok, reason } when the numbers cannot describe a sale at all.
 */
function splitPayment({ total, paid }) {
  const t = num(total);
  const p = num(paid);
  if (t === null) return { ok: false, reason: 'The sale has no total' };
  if (p === null) {
    return { ok: false, reason: 'The amount received is not a number' };
  }
  if (t < 0) return { ok: false, reason: 'The sale total cannot be negative' };
  if (p < 0) return { ok: false, reason: 'The amount received cannot be negative' };

  const saleTotal = round2(t);
  const handed = round2(p);
  return {
    ok: true,
    total: saleTotal,
    paid: handed,
    tabAmount: handed < saleTotal ? round2(saleTotal - handed) : 0,
    change: handed > saleTotal ? round2(handed - saleTotal) : 0,
  };
}

/** True when part of the sale is going on the customer's tab. */
function goesOnTab({ total, paid }) {
  const split = splitPayment({ total, paid });
  return split.ok && split.tabAmount > EPSILON;
}

/**
 * Whether an order a client sent may be written.
 *
 * `tabAmount` is optional: a client that does not send one is only checked for
 * arithmetic it DID send (so an older build keeps working). What is never
 * allowed is a sale that claims to be paid in full while leaving a debt, or a
 * tab that belongs to nobody — the remainder is a debt, so it must name a
 * customer account, which is what the credit ledger and the statement read.
 */
function validateOrderPayment({ total, paid, tabAmount, customerId }) {
  const split = splitPayment({ total, paid });
  if (!split.ok) return split;

  const sentTab = num(tabAmount);
  if (sentTab !== null) {
    if (sentTab < 0) return { ok: false, reason: 'A tab cannot be negative' };
    if (Math.abs(sentTab - split.tabAmount) > EPSILON) {
      return {
        ok: false,
        reason: `The tab (${sentTab}) does not match the sale: ${split.total} - ${split.paid} = ${split.tabAmount}`,
      };
    }
  }

  const tab = sentTab === null ? split.tabAmount : sentTab;
  if (tab > EPSILON) {
    const id = num(customerId);
    if (id === null) {
      return {
        ok: false,
        reason:
          'Part of this sale goes on a tab, so it needs a customer account',
      };
    }
  }

  return { ok: true, ...split, tabAmount: tab };
}

module.exports = {
  EPSILON,
  splitPayment,
  goesOnTab,
  validateOrderPayment,
};
