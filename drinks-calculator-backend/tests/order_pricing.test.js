// tests/order_pricing.test.js
// The server has to be able to price a cart on its own: that is the only way to
// stop a tampered/buggy till from collecting less than the sale is worth.
const { priceCart, parseCart, MAX_CART_LINES } = require('../utils/orderPricing');

const catalogue = { d1: 1000, d2: 2500, free: 0 };

describe('priceCart', () => {
  test('sums one line per unit (a crate sale is 24 lines of the same drink)', () => {
    const lines = Array.from({ length: 24 }, () => ({ drinkId: 'd1' }));
    const quote = priceCart(lines, catalogue);
    expect(quote.valid).toBe(true);
    expect(quote.unitCount).toBe(24);
    expect(quote.total).toBe(24000);
    // 24 identical lines collapse into ONE priced row for the receipt.
    expect(quote.lines).toHaveLength(1);
    expect(quote.lines[0]).toEqual({
      drinkId: 'd1', quantity: 24, unitPrice: 1000, lineTotal: 24000,
    });
  });

  test('mixed cart adds up', () => {
    const quote = priceCart(
      [{ drinkId: 'd1' }, { drinkId: 'd2', quantity: 2 }, { drinkId: 'd1' }],
      catalogue
    );
    expect(quote.total).toBe(1000 + 5000 + 1000);
    expect(quote.unitCount).toBe(4);
  });

  test('a free drink is priced at zero, not treated as unknown', () => {
    const quote = priceCart([{ drinkId: 'free' }], catalogue);
    expect(quote.valid).toBe(true);
    expect(quote.total).toBe(0);
    expect(quote.lines[0].unitPrice).toBe(0);
  });

  test('an unknown drink makes the whole quote invalid instead of being dropped', () => {
    const quote = priceCart([{ drinkId: 'd1' }, { drinkId: 'ghost' }], catalogue);
    expect(quote.valid).toBe(false);
    expect(quote.unknown).toEqual(['ghost']);
    // The known part is still priced, so the caller can show what it did see.
    expect(quote.total).toBe(1000);
  });

  test('bad quantities are rejected, never silently priced', () => {
    const quote = priceCart(
      [{ drinkId: 'd1', quantity: 0 }, { drinkId: 'd1', quantity: -3 },
        { drinkId: 'd1', quantity: 1.5 }, { drinkId: 'd1', quantity: 'two' }],
      catalogue
    );
    expect(quote.valid).toBe(false);
    expect(quote.rejected.map((r) => r.reason))
      .toEqual(['invalid_quantity', 'invalid_quantity', 'invalid_quantity', 'invalid_quantity']);
    expect(quote.total).toBe(0);
  });

  test('rejects a line with no drink id and a non-object line', () => {
    const quote = priceCart([{ quantity: 1 }, 'd1', null], catalogue);
    expect(quote.valid).toBe(false);
    expect(quote.rejected.map((r) => r.reason))
      .toEqual(['missing_drink_id', 'invalid_line', 'invalid_line']);
  });

  test('an empty cart yields zero and is not "valid"', () => {
    const quote = priceCart([], catalogue);
    expect(quote.valid).toBe(false);
    expect(quote.total).toBe(0);
  });

  test('prices are rounded to 2 decimals', () => {
    const quote = priceCart([{ drinkId: 'p', quantity: 3 }], { p: 0.1 });
    expect(quote.total).toBe(0.3);
  });

  test('accepts a Map as the price source', () => {
    const quote = priceCart([{ drinkId: 'd2' }], new Map([['d2', 2500]]));
    expect(quote.total).toBe(2500);
  });
});

describe('parseCart', () => {
  test('requires an items array', () => {
    expect(parseCart({}).error).toBe('items must be an array');
    expect(parseCart(null).error).toBe('items must be an array');
  });

  test('caps the cart size', () => {
    const huge = { items: new Array(MAX_CART_LINES + 1).fill({ drinkId: 'd1' }) };
    expect(parseCart(huge).error).toContain(String(MAX_CART_LINES));
  });

  test('passes a normal cart through', () => {
    const parsed = parseCart({ items: [{ drinkId: 'd1' }] });
    expect(parsed.error).toBeNull();
    expect(parsed.lines).toHaveLength(1);
  });
});
