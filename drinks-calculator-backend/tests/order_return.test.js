/**
 * Returning items from a sale — the third correction lane, next to void (retire
 * the whole sale) and cancel (it never completed). No database required.
 *
 * Covers:
 *   • what an order sold, merged per drink and priced as billed,
 *   • the ceiling: never more than sold − already returned, read from the ledger,
 *   • the guards (voided/cancelled order, missing reason, unknown drink),
 *   • POST /orders/:id/returns — manager only, ledger row + stock back, and
 *   • the Returns line of the Z-report, including what it does to expected cash.
 *
 * Run with: npm test
 */
const router = require('../routes/data.routes');
const orderReturn = require('../utils/orderReturn');
const { summariseShift } = require('../utils/shiftMath');

// Grab the final handler of a route, skipping the session middleware layer.
function routeHandler(method, path) {
  const layer = router.stack.find(
    (l) => l.route && l.route.path === path && l.route.methods[method]
  );
  if (!layer) throw new Error(`Route ${method.toUpperCase()} ${path} not found`);
  const handlers = layer.route.stack.map((s) => s.handle);
  return handlers[handlers.length - 1];
}

function fakeRes() {
  const res = {
    statusCode: 200,
    body: undefined,
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(payload) {
      res.body = payload;
      return res;
    },
    end() {
      return res;
    },
  };
  return res;
}

/** Two beers on one invoice, stored the way the app stores them. */
const soldTwoBeers = JSON.stringify([
  { id: 'd1', name: 'Beer', price: 1000 },
  { id: 'd1', name: 'Beer', price: 1000 },
]);

const orderRow = (over = {}) => ({
  id: 'o1',
  company_id: 7,
  total_amount: 2000,
  amount_paid: 2000,
  is_active: true,
  voided_at: null,
  items: soldTwoBeers,
  ...over,
});

const req = (db, { body = {}, user, params = { id: 'o1' } } = {}) => ({
  db,
  user: user || { id: 9, role: 'Manager', company_id: 7, username: 'Alice' },
  body,
  params,
  query: {},
});

/** A fake pool covering every statement the two routes issue. */
function fakeDb({ found = [orderRow()], ledger = [], stocked = ['d1'] } = {}) {
  const calls = [];
  const db = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      if (/^\s*SELECT \* FROM orders/i.test(sql)) return { rows: found };
      if (/INSERT INTO inventory_transactions/i.test(sql)) return { rows: [] };
      if (/^\s*UPDATE inventory/i.test(sql)) {
        return {
          rows: [{
            id: 'inv1',
            drink_id: params[2],
            drink_name: 'Beer',
            quantity: 9,
          }],
        };
      }
      if (/FROM inventory WHERE company_id/i.test(sql)) {
        return { rows: stocked.map((id) => ({ drink_id: id })) };
      }
      if (/FROM inventory_transactions/i.test(sql)) return { rows: ledger };
      throw new Error(`unexpected SQL: ${sql}`);
    },
  };
  return { db, calls };
}

describe('what a sale sold', () => {
  test('merges one-entry-per-unit invoices per drink and prices them as billed', () => {
    const lines = orderReturn.soldLines(soldTwoBeers);
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({
      drinkId: 'd1',
      drinkName: 'Beer',
      quantity: 2,
      unitPrice: 1000,
      amount: 2000,
    });
  });

  test('accepts lines that carry a quantity instead', () => {
    const lines = orderReturn.soldLines([{ drink_id: 'd2', drink_name: 'Water', quantity: 3, price: 500 }]);
    expect(lines[0]).toMatchObject({ drinkId: 'd2', quantity: 3, unitPrice: 500 });
  });

  test('follows the price the customer paid, never a default', () => {
    const lines = orderReturn.soldLines([{ id: 'd1', name: 'Beer', pricePerUnit: 800 }]);
    expect(lines[0].unitPrice).toBe(800);
  });

  test('keeps two products apart and ignores junk entries', () => {
    const lines = orderReturn.soldLines([
      { id: 'd1', name: 'Beer', price: 1000 },
      { id: 'd2', name: 'Water', price: 500 },
      null,
      'nope',
      {},
    ]);
    expect(lines.map((l) => l.drinkName)).toEqual(['Beer', 'Water']);
  });
});

describe('what is left to return', () => {
  test('the ledger already returned reduces the ceiling', () => {
    const lines = orderReturn.returnableLines(soldTwoBeers, [
      { drink_id: 'd1', drink_name: 'Beer', quantity: 1, reason: 'return' },
    ]);
    expect(lines[0]).toMatchObject({ sold: 2, returned: 1, remaining: 1 });
    expect(lines[0].amount).toBe(1000);
  });

  test('remaining never goes below zero, whatever the ledger says', () => {
    const lines = orderReturn.returnableLines(soldTwoBeers, [
      { drink_id: 'd1', drink_name: 'Beer', quantity: 5, reason: 'return' },
    ]);
    expect(lines[0].remaining).toBe(0);
  });

  test('movements that are not returns are not counted', () => {
    const lines = orderReturn.returnableLines(soldTwoBeers, [
      { drink_id: 'd1', drink_name: 'Beer', quantity: 1, reason: 'sale' },
      { drink_id: 'd1', drink_name: 'Beer', quantity: 1, reason: 'void' },
    ]);
    expect(lines[0].remaining).toBe(2);
  });
});

describe('validateReturn', () => {
  const ask = (lines, { reason = 'flat beer', ledger = [] } = {}) =>
    orderReturn.validateReturn({
      order: orderRow(),
      lines,
      reason,
      alreadyReturned: ledger,
    });

  test('returns one of two beers and refunds what was paid', () => {
    const result = ask([{ drink_id: 'd1', quantity: 1 }]);
    expect(result.ok).toBe(true);
    expect(result.lines[0]).toMatchObject({ drinkName: 'Beer', quantity: 1, unitPrice: 1000 });
    expect(result.totalUnits).toBe(1);
    expect(result.totalAmount).toBe(1000);
  });

  test('a reason is required and is trimmed', () => {
    expect(ask([{ drink_id: 'd1', quantity: 1 }], { reason: '   ' }).ok).toBe(false);
    expect(ask([{ drink_id: 'd1', quantity: 1 }], { reason: 'x'.repeat(201) }).ok).toBe(false);
    expect(ask([{ drink_id: 'd1', quantity: 1 }], { reason: '  flat  ' }).reason).toBe('flat');
  });

  test('nothing chosen is a client mistake, and so are impossible quantities', () => {
    expect(ask([]).ok).toBe(false);
    for (const quantity of [0, -1, 1.5, 'x', null]) {
      const result = ask([{ drink_id: 'd1', quantity }]);
      expect(result.ok).toBe(false);
      expect(result.code).toBe('invalid');
    }
  });

  test('a drink that is not on the invoice cannot be returned', () => {
    const result = ask([{ drink_id: 'd9', quantity: 1 }]);
    expect(result.ok).toBe(false);
    expect(result.code).toBe('invalid');
    expect(result.reason).toMatch(/not on this invoice/);
  });

  test('the same drink twice in one request is refused', () => {
    const result = ask([
      { drink_id: 'd1', quantity: 1 },
      { drink_id: 'd1', quantity: 1 },
    ]);
    expect(result.ok).toBe(false);
    expect(result.reason).toMatch(/appears twice/);
  });

  test('two sold, one already returned, leaves exactly one', () => {
    const ledger = [{ drink_id: 'd1', drink_name: 'Beer', quantity: 1, reason: 'return' }];
    const tooMany = ask([{ drink_id: 'd1', quantity: 2 }], { ledger });
    expect(tooMany.ok).toBe(false);
    expect(tooMany.code).toBe('conflict');
    expect(tooMany.reason).toMatch(/Only 1 of Beer is left to return/);

    expect(ask([{ drink_id: 'd1', quantity: 1 }], { ledger }).ok).toBe(true);
  });

  test('a fully returned order has nothing left', () => {
    const result = ask([{ drink_id: 'd1', quantity: 1 }], {
      ledger: [{ drink_id: 'd1', drink_name: 'Beer', quantity: 2, reason: 'return' }],
    });
    expect(result.ok).toBe(false);
    expect(result.code).toBe('conflict');
    expect(result.reason).toMatch(/already been returned/);
  });

  test('a voided or cancelled sale is refused before anything moves', () => {
    for (const order of [
      orderRow({ voided_at: '2026-10-10T09:00:00Z', is_active: false }),
      orderRow({ is_active: false }),
    ]) {
      const result = orderReturn.validateReturn({
        order,
        lines: [{ drink_id: 'd1', quantity: 1 }],
        reason: 'flat',
      });
      expect(result.ok).toBe(false);
      expect(result.code).toBe('conflict');
    }
  });

  test('a request keyed on an id the invoice does not carry is refused', () => {
    const result = orderReturn.validateReturn({
      order: orderRow({ items: JSON.stringify([{ name: 'Beer', price: 1000 }]) }),
      lines: [{ drink_id: 'd1', quantity: 1 }],
      reason: 'flat',
    });
    expect(result.ok).toBe(false);
    expect(result.code).toBe('invalid');
  });
});

describe('summariseReturns', () => {
  test('two lines of one return read as one return, three units', () => {
    const summary = orderReturn.summariseReturns([
      { order_id: 'o1', quantity: 1, selling_price_at_sale: 1000, reason: 'return' },
      { order_id: 'o1', quantity: 2, selling_price_at_sale: 500, reason: 'return' },
    ]);
    expect(summary).toEqual({ returnCount: 1, returnUnits: 3, returnValue: 2000 });
  });

  test('sales, restocks and voids are not returns', () => {
    const summary = orderReturn.summariseReturns([
      { order_id: 'o1', quantity: 2, selling_price_at_sale: 1000, reason: 'sale' },
      { order_id: 'o1', quantity: 5, reason: 'restock' },
      { order_id: 'o1', quantity: 2, reason: 'void' },
      { quantity: 1, reason: 'return' },
    ]);
    expect(summary.returnCount).toBe(1);
    expect(summary.returnUnits).toBe(1);
    expect(summary.returnValue).toBe(0);
  });
});

describe('POST /orders/:id/returns', () => {
  const handler = routeHandler('post', '/orders/:id/returns');

  test('a manager gets the stock back and one ledger row per drink', async () => {
    const { db, calls } = fakeDb();
    const res = fakeRes();

    await handler(
      req(db, { body: { reason: 'flat beer', items: [{ drink_id: 'd1', quantity: 1 }] } }),
      res
    );

    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({
      success: true,
      totalUnits: 1,
      totalAmount: 1000,
      returnedBy: 'Alice',
    });
    expect(res.body.returned[0]).toMatchObject({ drinkName: 'Beer', remaining: 9 });

    const ledgerInsert = calls.find((c) => /INSERT INTO inventory_transactions/i.test(c.sql));
    expect(ledgerInsert.sql).toMatch(/'in','return'/);
    expect(ledgerInsert.params).toEqual([7, 'd1', 'Beer', 1, 'o1', 9, 1000]);

    const stockUpdate = calls.find((c) => /^\s*UPDATE inventory/i.test(c.sql));
    expect(stockUpdate.params).toEqual([1, 7, 'd1']);

    // The movement is recorded once — that ledger row IS the audit row.
    expect(calls.filter((c) => /INSERT INTO inventory_transactions/i.test(c.sql))).toHaveLength(1);
  });

  test('staff may not hand money back', async () => {
    const { db, calls } = fakeDb();
    const res = fakeRes();
    await handler(
      req(db, {
        user: { id: 4, role: 'Staff', company_id: 7, username: 'Bob' },
        body: { reason: 'flat', items: [{ drink_id: 'd1', quantity: 1 }] },
      }),
      res
    );
    expect(res.statusCode).toBe(403);
    expect(calls).toHaveLength(0);
  });

  test('an unknown order is a 404 and nothing else runs', async () => {
    const { db, calls } = fakeDb({ found: [] });
    const res = fakeRes();
    await handler(
      req(db, { body: { reason: 'flat', items: [{ drink_id: 'd1', quantity: 1 }] } }),
      res
    );
    expect(res.statusCode).toBe(404);
    expect(calls.some((c) => /INSERT INTO inventory_transactions/i.test(c.sql))).toBe(false);
  });

  test('a missing reason is a 400 with no stock movement', async () => {
    const { db, calls } = fakeDb();
    const res = fakeRes();
    await handler(req(db, { body: { items: [{ drink_id: 'd1', quantity: 1 }] } }), res);
    expect(res.statusCode).toBe(400);
    expect(calls.some((c) => /^\s*UPDATE inventory/i.test(c.sql))).toBe(false);
  });

  test('a second return of the same unit is a 409, read from the ledger', async () => {
    const { db, calls } = fakeDb({
      ledger: [{ drink_id: 'd1', drink_name: 'Beer', quantity: 2, reason: 'return' }],
    });
    const res = fakeRes();
    await handler(
      req(db, { body: { reason: 'again', items: [{ drink_id: 'd1', quantity: 1 }] } }),
      res
    );
    expect(res.statusCode).toBe(409);
    expect(calls.some((c) => /INSERT INTO inventory_transactions/i.test(c.sql))).toBe(false);
  });

  test('a drink that is not stocked cannot be put back', async () => {
    const { db, calls } = fakeDb({ stocked: [] });
    const res = fakeRes();
    await handler(
      req(db, { body: { reason: 'flat', items: [{ drink_id: 'd1', quantity: 1 }] } }),
      res
    );
    expect(res.statusCode).toBe(409);
    expect(res.body.error).toBe('not_stocked');
    expect(calls.some((c) => /INSERT INTO inventory_transactions/i.test(c.sql))).toBe(false);
  });
});

describe('GET /orders/:id/returns', () => {
  const handler = routeHandler('get', '/orders/:id/returns');

  test('hands the dialog the sold / returned / remaining counts', async () => {
    const { db } = fakeDb({
      ledger: [{
        drink_id: 'd1', drink_name: 'Beer', quantity: 1, reason: 'return',
        selling_price_at_sale: 1000, date: '2026-10-10T09:00:00Z', performed_by: '9',
      }],
    });
    const res = fakeRes();
    await handler(
      { db, user: { id: 9, role: 'Manager', company_id: 7 }, params: { id: 'o1' }, query: {} },
      res
    );

    expect(res.statusCode).toBe(200);
    expect(res.body.lines[0]).toMatchObject({ sold: 2, returned: 1, remaining: 1 });
    expect(res.body.summary).toMatchObject({ returnCount: 1, returnUnits: 1, returnValue: 1000 });
    expect(res.body.isVoided).toBe(false);
  });

  test('an unknown order is a 404', async () => {
    const { db } = fakeDb({ found: [] });
    const res = fakeRes();
    await handler({ db, user: { id: 9, company_id: 7 }, params: { id: 'nope' }, query: {} }, res);
    expect(res.statusCode).toBe(404);
  });
});

describe('the whole story', () => {
  const post = routeHandler('post', '/orders/:id/returns');
  const get = routeHandler('get', '/orders/:id/returns');

  test('10 on the shelf, 2 sold, 1 handed back → 9, and the sale stays as billed', async () => {
    // The sale already took the two beers off the shelf: 10 → 8.
    const state = { stock: 8, ledger: [] };
    const db = {
      query: async (sql, params) => {
        if (/^\s*SELECT \* FROM orders/i.test(sql)) {
          return { rows: [{ ...orderRow(), items: soldTwoBeers }] };
        }
        if (/INSERT INTO inventory_transactions/i.test(sql)) {
          state.ledger.push({
            drink_id: params[1],
            drink_name: params[2],
            quantity: params[3],
            order_id: params[4],
            reason: 'return',
            selling_price_at_sale: params[6],
          });
          return { rows: [] };
        }
        if (/^\s*UPDATE inventory/i.test(sql)) {
          state.stock += params[0];
          return {
            rows: [{
              id: 'inv1', drink_id: params[2], drink_name: 'Beer', quantity: state.stock,
            }],
          };
        }
        if (/FROM inventory_transactions/i.test(sql)) return { rows: state.ledger };
        if (/FROM inventory/i.test(sql)) return { rows: [{ drink_id: 'd1' }] };
        throw new Error(`unexpected SQL: ${sql}`);
      },
    };

    // The manager hands one beer back: the sale stays, the shelf gets it back.
    const res = fakeRes();
    await post(
      req(db, { body: { reason: 'flat beer', items: [{ drink_id: 'd1', quantity: 1 }] } }),
      res
    );
    expect(res.statusCode).toBe(200);
    expect(state.stock).toBe(9);
    expect(res.body.totalAmount).toBe(1000);

    // One is still returnable, and only one.
    const left = fakeRes();
    await get({ db, user: { id: 9, company_id: 7 }, params: { id: 'o1' }, query: {} }, left);
    expect(left.body.lines[0]).toMatchObject({ sold: 2, returned: 1, remaining: 1 });

    // Asking for both now is refused, and the shelf does not move.
    const both = fakeRes();
    await post(
      req(db, { body: { reason: 'both', items: [{ drink_id: 'd1', quantity: 2 }] } }),
      both
    );
    expect(both.statusCode).toBe(409);
    expect(state.stock).toBe(9);

    // The cash-up reconciles: 2000 invoiced, 1000 refunded, 1000 kept.
    const report = summariseShift({
      shift: { opening_float: 0 },
      orders: [{ total_amount: 2000, amount_paid: 2000 }],
      returns: orderReturn.summariseReturns(state.ledger),
    });
    expect(report.sales).toBe(2000);
    expect(report.orderCount).toBe(1);
    expect(report.returnCount).toBe(1);
    expect(report.returnUnits).toBe(1);
    expect(report.returnValue).toBe(1000);
    expect(report.netSales).toBe(1000);
    expect(report.expectedCash).toBe(1000);
  });
});

describe('the Returns line of the Z-report', () => {
  test('the sale stays as billed, the refund comes off the cash and the net', () => {
    const report = summariseShift({
      shift: { opening_float: 0 },
      orders: [{ total_amount: 2000, amount_paid: 2000 }],
      returns: orderReturn.summariseReturns([
        { order_id: 'o1', quantity: 1, selling_price_at_sale: 1000, reason: 'return' },
      ]),
    });

    expect(report.sales).toBe(2000);
    expect(report.collected).toBe(2000);
    expect(report.returnCount).toBe(1);
    expect(report.returnUnits).toBe(1);
    expect(report.returnValue).toBe(1000);
    expect(report.netSales).toBe(1000);
    // The drawer is missing the 1000 that was handed back — that is the point.
    expect(report.expectedCash).toBe(1000);
  });

  test('a shift with no returns is unchanged by the new line', () => {
    const report = summariseShift({
      shift: { opening_float: 5000 },
      orders: [{ total_amount: 2000, amount_paid: 1000 }],
    });
    expect(report.returnCount).toBe(0);
    expect(report.returnValue).toBe(0);
    expect(report.netSales).toBe(2000);
    expect(report.expectedCash).toBe(6000);
    expect(report.onCredit).toBe(1000);
  });
});
