/**
 * Cancelling a sale — the rollback lane, and the shift window that must not
 * count it. No database required.
 *
 * The app writes the order row before it commits the stock. When that commit is
 * refused the sale never happened, so the row has to stop counting as a sale
 * WITHOUT pretending the stock came back (nothing, or only some lines, ever left
 * the shelf). This covers:
 *   • POST /orders/:id/cancel records who/why, marks the row inactive and moves
 *     no stock at all,
 *   • its guards: unknown order (404), already voided (409), blank reason (400),
 *   • the company scoping of the update, and
 *   • the shift summary, which excludes inactive rows from the sales and reports
 *     them as corrections instead — the double count a rollback used to cause.
 *
 * Run with: npm test
 */
const router = require('../routes/data.routes');
const orderVoid = require('../utils/orderVoid');
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

const cancelReq = (db, { body = {}, user, params = { id: 'o1' } } = {}) => ({
  db,
  user: user || { id: 9, role: 'Manager', company_id: 7, username: 'Alice' },
  body,
  params,
  query: {},
});

const orderRow = (over = {}) => ({
  id: 'o1',
  company_id: 7,
  total_amount: 50,
  amount_paid: 50,
  is_active: true,
  voided_at: null,
  created_by: 9,
  ...over,
});

function dbFor(found) {
  const calls = [];
  const db = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      if (/^\s*SELECT \* FROM orders/i.test(sql)) return { rows: found };
      if (/^\s*UPDATE orders/i.test(sql)) {
        // Mirror what `RETURNING *` would hand back, so the assertions below test
        // the route's parameter wiring instead of the fake.
        const [id, companyId, by, byName, reason] = params;
        return {
          rows: [{
            ...(found[0] || {}),
            id,
            company_id: companyId,
            is_active: false,
            voided_at: '2026-10-10T09:00:00Z',
            voided_by: by,
            voided_by_name: byName,
            void_reason: reason,
          }],
        };
      }
      throw new Error(`unexpected SQL: ${sql}`);
    },
  };
  return { db, calls };
}

describe('POST /orders/:id/cancel', () => {
  const handler = routeHandler('post', '/orders/:id/cancel');

  test('marks the sale inactive, records who/why, and moves no stock', async () => {
    const { db, calls } = dbFor([orderRow()]);
    const res = fakeRes();

    await handler(cancelReq(db, { body: { reason: 'stock could not be committed' } }), res);

    expect(res.statusCode).toBe(200);
    expect(res.body.stockMoved).toBe(0);
    expect(res.body.voided_by_name).toBe('Alice');
    expect(res.body.is_active).toBe(false);
    expect(res.body.voided_at).toBeTruthy();
    expect(res.body.void_reason).toBe('stock could not be committed');

    const update = calls.find((c) => /^\s*UPDATE orders/i.test(c.sql));
    expect(update.sql).toMatch(/is_active = false/);
    expect(update.sql).toMatch(/voided_at = CURRENT_TIMESTAMP/);
    expect(update.sql).toMatch(/void_reason = \$5/);
    expect(update.params).toEqual(['o1', 7, 9, 'Alice', 'stock could not be committed']);

    // The whole point: no inventory transaction, no stock movement at all.
    expect(calls.some((c) => /inventory_transactions/i.test(c.sql))).toBe(false);
  });

  test('is scoped to the session company, never to an id sent by the client', async () => {
    const { db, calls } = dbFor([orderRow()]);
    await handler(
      cancelReq(db, { body: { reason: 'rolled back', company_id: 999 } }),
      fakeRes()
    );
    const update = calls.find((c) => /^\s*UPDATE orders/i.test(c.sql));
    expect(update.sql).toMatch(/company_id = \$2/);
    expect(update.params[1]).toBe(7);
  });

  test('a cashier can cancel their own refused sale', async () => {
    const { db } = dbFor([orderRow()]);
    const res = fakeRes();
    await handler(
      cancelReq(db, {
        body: { reason: 'payment failed' },
        user: { id: 4, role: 'Staff', company_id: 7, username: 'Bob' },
      }),
      res
    );
    expect(res.statusCode).toBe(200);
    expect(res.body.voided_by_name).toBe('Bob');
  });

  test('refuses an unknown order', async () => {
    const { db } = dbFor([]);
    const res = fakeRes();
    await handler(cancelReq(db, { body: { reason: 'why not' } }), res);
    expect(res.statusCode).toBe(404);
  });

  test('refuses a row that is already voided', async () => {
    const { db } = dbFor([orderRow({ voided_at: '2026-09-27T11:00:00Z' })]);
    const res = fakeRes();
    await handler(cancelReq(db, { body: { reason: 'again' } }), res);
    expect(res.statusCode).toBe(409);
  });

  test('a reason is required — a correction without one is not a correction', async () => {
    for (const body of [{}, { reason: '' }, { reason: '   ' }]) {
      const { db, calls } = dbFor([orderRow()]);
      const res = fakeRes();
      await handler(cancelReq(db, { body }), res);
      expect(res.statusCode).toBe(400);
      expect(calls.some((c) => /^\s*UPDATE orders/i.test(c.sql))).toBe(false);
    }
  });

  test('a 200-char reason is accepted, 201 is not', async () => {
    const ok = fakeRes();
    await handler(
      cancelReq(dbFor([orderRow()]).db, { body: { reason: 'x'.repeat(200) } }),
      ok
    );
    expect(ok.statusCode).toBe(200);

    const tooLong = fakeRes();
    await handler(
      cancelReq(dbFor([orderRow()]).db, { body: { reason: 'x'.repeat(201) } }),
      tooLong
    );
    expect(tooLong.statusCode).toBe(400);
  });
});

describe('GET /shifts/:id/summary — what counts as a sale', () => {
  const handler = routeHandler('get', '/shifts/:id/summary');

  test('sales exclude inactive rows and list them as corrections', async () => {
    const calls = [];
    const db = {
      query: async (sql, params) => {
        calls.push({ sql, params });
        if (/FROM shifts/i.test(sql)) {
          return {
            rows: [{
              id: 3, company_id: 7, opening_float: 0,
              cash_payouts: 0, status: 'open', cash_counted: null,
            }],
          };
        }
        // The sales query — what the real DB returns for its filter.
        if (/voided_at IS NULL/.test(sql)) {
          return { rows: [{ total_amount: 100, amount_paid: 100 }] };
        }
        // The corrections query: the rolled-back sale, inactive with no void.
        return { rows: [{ total_amount: 50, voided_at: null, is_active: false }] };
      },
    };
    const res = fakeRes();

    await handler(
      { db, user: { id: 9, role: 'Manager', company_id: 7 }, params: { id: '3' }, query: {} },
      res
    );

    const sql = calls.map((c) => c.sql);
    expect(sql.find((s) => /voided_at IS NULL/.test(s))).toMatch(/is_active = true/);
    expect(
      sql.find((s) => /voided_at IS NOT NULL OR is_active = false/.test(s))
    ).toBeTruthy();

    // 100 of sales — the cancelled 50 is not revenue, but it stays visible.
    expect(res.body.sales).toBe(100);
    expect(res.body.expectedCash).toBe(100);
    expect(res.body.orderCount).toBe(1);
    expect(res.body.voidCount).toBe(1);
    expect(res.body.voidValue).toBe(50);
  });
});

describe('the shift window — a rolled-back sale is never revenue', () => {
  test('money: 100 sold + a 50 sale rolled back = 100 takings, 50 corrected', () => {
    const report = summariseShift({
      shift: { opening_float: 0 },
      orders: [{ total_amount: 100, amount_paid: 100 }],
      voids: orderVoid.summariseVoids([
        { total_amount: 50, is_active: false, voided_at: null },
      ]),
    });

    expect(report.sales).toBe(100);
    expect(report.collected).toBe(100);
    expect(report.expectedCash).toBe(100);
    expect(report.voidCount).toBe(1);
    expect(report.voidValue).toBe(50);
  });
});
