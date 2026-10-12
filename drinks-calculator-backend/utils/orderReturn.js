// utils/orderReturn.js
// Returning items from a sale — the third correction lane, next to void and
// cancel. Pure (no Express, no DB) so every rule below is unit tested.
//
// Why a return is not a void: a void retires the WHOLE sale (its stock goes back,
// the order stops counting). A return keeps the sale as billed — the customer
// bought two units — and records that one of them came back: that unit goes back
// on the shelf, the money is given back, and the Z-report shows a Returns line so
// the drawer still reconciles. "Void the invoice, then re-invoice one unit"
// reached the same stock number but lost the reason and left a second invoice.
//
// Nothing here assumes what the business sells: the app is used by bars,
// restaurants and shops alike, so a "unit" is whatever was on the invoice.
//
// The ceiling is what makes it safe: an order can never return more units of a
// drink than it sold, counting what earlier returns already took back. That count
// lives in `inventory_transactions` (reason 'return', order_id set), which is also
// the audit row that puts the stock back.
const { parseItems, isVoided, isInactive } = require('./orderVoid');

/** Money helper: Postgres NUMERIC arrives as a string ("1000.00"). */
function num(value) {
  if (value == null || value === '') return 0;
  const parsed = typeof value === 'number' ? value : parseFloat(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function money(value) {
  return Math.round(num(value) * 100) / 100;
}

/**
 * How a line is identified. The drink id wins when there is one, because an
 * invoice stores the name the drink had when it was sold — a rename must not
 * split one product into two lines.
 */
function lineKey(drinkId, drinkName) {
  const id = drinkId == null ? '' : String(drinkId).trim();
  if (id) return `id:${id}`;
  return `name:${String(drinkName == null ? '' : drinkName).trim().toLowerCase()}`;
}

/**
 * What a sale actually sold, merged per drink.
 *
 * Orders store either one entry per sold unit (the app's Drink JSON) or a line
 * with a quantity, so both are counted. The unit price is what the customer was
 * charged at the time, never today's catalogue price: a return gives back exactly
 * what was taken.
 *
 * @returns {Array<{drinkId: (string|null), drinkName: string, quantity: number, unitPrice: number, amount: number}>}
 */
function soldLines(items) {
  const merged = new Map();
  for (const item of parseItems(items)) {
    if (!item || typeof item !== 'object') continue;
    const drinkId = item.id ?? item.drinkId ?? item.drink_id ?? null;
    const drinkName = (item.name ?? item.drinkName ?? item.drink_name ?? '')
      .toString()
      .trim();
    if ((drinkId == null || drinkId === '') && !drinkName) continue;

    const rawQuantity = Number(item.quantity);
    const quantity = Number.isFinite(rawQuantity) && rawQuantity > 0 ? rawQuantity : 1;
    const key = lineKey(drinkId, drinkName);
    const entry = merged.get(key) || {
      drinkId: drinkId == null || drinkId === '' ? null : String(drinkId),
      drinkName,
      quantity: 0,
      unitPrice: null,
    };
    entry.quantity += quantity;
    if (entry.unitPrice == null) {
      const price = item.price ?? item.pricePerUnit ?? item.unitPrice ??
        item.selling_price_at_sale;
      const parsed = num(price);
      if (price != null && parsed > 0) entry.unitPrice = parsed;
    }
    merged.set(key, entry);
  }
  return [...merged.values()].map((line) => ({
    drinkId: line.drinkId,
    drinkName: line.drinkName,
    quantity: line.quantity,
    unitPrice: money(line.unitPrice == null ? 0 : line.unitPrice),
    amount: money((line.unitPrice == null ? 0 : line.unitPrice) * line.quantity),
  }));
}

/**
 * Units already returned against an order, from its `inventory_transactions`
 * rows — the same rows the Z-report totals, so the ceiling and the report can
 * never disagree.
 *
 * @returns {Map<string, number>} lineKey -> units
 */
function alreadyReturned(rows) {
  const map = new Map();
  for (const row of rows || []) {
    if (!row || String(row.reason || '') !== 'return') continue;
    const quantity = num(row.quantity);
    if (!(quantity > 0)) continue;
    const key = lineKey(row.drink_id, row.drink_name);
    map.set(key, (map.get(key) || 0) + quantity);
  }
  return map;
}

/** What a drink's line looks like to the app: sold, already back, still returnable. */
function returnableLines(items, returned) {
  const ledger = returned instanceof Map ? returned : alreadyReturned(returned);
  return soldLines(items).map((line) => {
    const returnedUnits = ledger.get(lineKey(line.drinkId, line.drinkName)) || 0;
    const remaining = Math.max(0, line.quantity - returnedUnits);
    return {
      drinkId: line.drinkId,
      drinkName: line.drinkName,
      sold: line.quantity,
      returned: returnedUnits,
      remaining,
      unitPrice: line.unitPrice,
      amount: money(line.unitPrice * remaining),
    };
  });
}

/**
 * Can these items come back right now?
 *
 * `code` lets the route answer with the right status: 'invalid' is the client's
 * mistake (400), 'conflict' is the order's state (409).
 *
 * @param {object} args.order    the order row as stored (its `items` may be JSON text)
 * @param {Array}  args.lines    [{drink_id, quantity}]
 * @param {string} args.reason   why it is coming back — mandatory
 * @param {Map|Array} args.alreadyReturned  ledger rows, or a Map from alreadyReturned
 */
function validateReturn({ order, lines, reason, alreadyReturned: returned } = {}) {
  if (!order) return { ok: false, code: 'invalid', reason: 'Unknown order' };
  if (isVoided(order)) {
    return {
      ok: false,
      code: 'conflict',
      reason: 'This order is voided — restore it before returning items',
    };
  }
  if (isInactive(order)) {
    return {
      ok: false,
      code: 'conflict',
      reason: 'This sale was cancelled, so there is nothing to return',
    };
  }

  const text = (reason || '').toString().trim();
  if (!text) {
    return { ok: false, code: 'invalid', reason: 'A reason is required to return items' };
  }
  if (text.length > 200) {
    return {
      ok: false,
      code: 'invalid',
      reason: 'The reason is too long (200 characters max)',
    };
  }

  const requested = Array.isArray(lines) ? lines : [];
  if (requested.length === 0) {
    return { ok: false, code: 'invalid', reason: 'Choose at least one item to return' };
  }

  const sold = new Map(
    soldLines(order.items).map((line) => [lineKey(line.drinkId, line.drinkName), line])
  );
  const ledger = returned instanceof Map ? returned : alreadyReturned(returned);
  const accepted = [];
  const seen = new Set();

  for (const line of requested) {
    if (!line || typeof line !== 'object') {
      return { ok: false, code: 'invalid', reason: 'A return line is malformed' };
    }
    const key = lineKey(line.drink_id ?? line.drinkId, '');
    const soldLine = sold.get(key);
    if (!soldLine) {
      return {
        ok: false,
        code: 'invalid',
        reason: 'That drink is not on this invoice — a return can only give back what was sold',
      };
    }
    if (seen.has(key)) {
      return {
        ok: false,
        code: 'invalid',
        reason: 'The same drink appears twice — send one line per drink',
      };
    }
    seen.add(key);

    const quantity = Number(line.quantity);
    if (!Number.isInteger(quantity) || quantity <= 0) {
      return {
        ok: false,
        code: 'invalid',
        reason: 'Each return must be a whole number of items',
      };
    }

    const label = soldLine.drinkName || 'this drink';
    const remaining = soldLine.quantity - (ledger.get(key) || 0);
    if (remaining <= 0) {
      return {
        ok: false,
        code: 'conflict',
        reason: `Every ${label} of this sale has already been returned`,
      };
    }
    if (quantity > remaining) {
      return {
        ok: false,
        code: 'conflict',
        reason: `Only ${remaining} of ${label} ${remaining === 1 ? 'is' : 'are'} left to return`,
      };
    }

    accepted.push({
      drinkId: soldLine.drinkId,
      drinkName: soldLine.drinkName,
      quantity,
      unitPrice: soldLine.unitPrice,
      amount: money(soldLine.unitPrice * quantity),
    });
  }

  return {
    ok: true,
    reason: text,
    lines: accepted,
    totalUnits: accepted.reduce((sum, line) => sum + line.quantity, 0),
    totalAmount: money(accepted.reduce((sum, line) => sum + line.amount, 0)),
  };
}

/**
 * The Returns line of a Z-report: how many returns, how many units, and how much
 * money went back out of the drawer.
 *
 * `returnCount` counts return EVENTS (distinct orders), not movements, so three
 * lines of one return read as one return — `returnUnits` carries the detail.
 */
function summariseReturns(rows) {
  const events = new Set();
  let movements = 0;
  let units = 0;
  let value = 0;

  for (const row of rows || []) {
    if (!row || String(row.reason || '') !== 'return') continue;
    const quantity = num(row.quantity);
    if (!(quantity > 0)) continue;
    movements += 1;
    units += quantity;
    value += quantity * num(row.selling_price_at_sale);
    if (row.order_id != null && String(row.order_id) !== '') {
      events.add(String(row.order_id));
    }
  }

  return {
    returnCount: events.size > 0 ? events.size : movements,
    returnUnits: units,
    returnValue: money(value),
  };
}

module.exports = {
  num,
  money,
  lineKey,
  soldLines,
  alreadyReturned,
  returnableLines,
  validateReturn,
  summariseReturns,
};
