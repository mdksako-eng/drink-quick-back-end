// utils/orderPricing.js
// Prices a till cart SERVER-SIDE.
//
// WHY: today the app computes the sale total and the server only checks that the
// amount is > 0 (routes/payment.routes.js). A buggy — or tampered — app can ask
// the provider to collect 500 for a 5 000 order and the books would believe it.
// The fix has to start by knowing the real price of a cart on the server, which
// is what this module does, with no database access so it can be unit tested.
//
// The cart is ONE LINE PER UNIT (a crate sale is 24 lines of the same drink), so
// duplicates are summed — never rejected, never de-duplicated.

/** Largest cart we will price; protects the quote endpoint from a huge body. */
const MAX_CART_LINES = 500;

/**
 * @typedef {{drinkId: string|number, quantity?: number}} CartLine
 * @typedef {Map<string, number>|Record<string, number>} PriceById
 */

function lookup(priceById, key) {
  if (priceById instanceof Map) return priceById.get(key);
  return priceById[key];
}

function round2(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

/**
 * Price a cart from the catalogue.
 *
 * @param {CartLine[]} lines the cart, one entry per unit
 * @param {PriceById} priceById selling price per drink id (string keys)
 * @returns {{valid: boolean, total: number, unitCount: number,
 *            lines: Array<{drinkId: string, quantity: number, unitPrice: number, lineTotal: number}>,
 *            unknown: string[], rejected: Array<{line: number, reason: string}>}}
 *   `valid` is false when any line cannot be priced: a quote that silently drops
 *   a line would under-charge the customer.
 */
function priceCart(lines, priceById) {
  const rows = Array.isArray(lines) ? lines : [];
  const priced = new Map(); // drinkId -> quantity, so 24 identical lines become one
  const rejected = [];

  rows.forEach((line, index) => {
    if (!line || typeof line !== 'object') {
      rejected.push({ line: index, reason: 'invalid_line' });
      return;
    }
    const rawQty = line.quantity === undefined ? 1 : Number(line.quantity);
    if (!Number.isFinite(rawQty) || rawQty <= 0 || !Number.isInteger(rawQty)) {
      rejected.push({ line: index, reason: 'invalid_quantity' });
      return;
    }
    if (line.drinkId === undefined || line.drinkId === null || line.drinkId === '') {
      rejected.push({ line: index, reason: 'missing_drink_id' });
      return;
    }
    const key = String(line.drinkId);
    priced.set(key, (priced.get(key) || 0) + rawQty);
  });

  const unknown = [];
  const out = [];
  for (const [drinkId, quantity] of priced) {
    const unitPrice = Number(lookup(priceById, drinkId));
    if (!Number.isFinite(unitPrice) || unitPrice < 0) {
      unknown.push(drinkId);
      continue;
    }
    out.push({
      drinkId,
      quantity,
      unitPrice: round2(unitPrice),
      lineTotal: round2(unitPrice * quantity),
    });
  }

  const total = round2(out.reduce((sum, line) => sum + line.lineTotal, 0));
  const unitCount = out.reduce((sum, line) => sum + line.quantity, 0);

  return {
    valid: unknown.length === 0 && rejected.length === 0 && out.length > 0,
    total,
    unitCount,
    lines: out,
    unknown,
    rejected,
  };
}

/**
 * Normalise a request body into cart lines, refusing huge carts.
 * @param {unknown} body
 * @returns {{lines: CartLine[], error: string|null}}
 */
function parseCart(body) {
  const raw = body && body.items;
  if (!Array.isArray(raw)) return { lines: [], error: 'items must be an array' };
  if (raw.length > MAX_CART_LINES) {
    return { lines: [], error: `cart is limited to ${MAX_CART_LINES} lines` };
  }
  return { lines: raw, error: null };
}

module.exports = { priceCart, parseCart, MAX_CART_LINES };
