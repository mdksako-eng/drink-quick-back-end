/**
 * Atomic stock movement tests — no database required.
 *
 * Guards the "two staff sell the last case at the same time" race: the
 * conditional UPDATE (`quantity + delta >= 0`) is the single source of truth,
 * so only ONE of two concurrent sells can succeed and stock never goes
 * negative. The fake DB below implements those exact SQL semantics.
 * Run with: npm test
 */
const router = require('../routes/data.routes');

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

/** Minimal in-memory inventory that honours the atomic guard in the SQL. */
function fakeDb({ drinkId = 'beer-1', quantity = 1, stocked = true } = {}) {
  const state = { quantity, stocked, transactions: [] };
  return {
    state,
    query: async (sql, params) => {
      if (/UPDATE inventory/i.test(sql) && /quantity \+ \$1 >= 0/i.test(sql)) {
        const [delta] = params;
        if (!state.stocked) return { rows: [] };
        // 🔒 the guard: apply only when the result stays >= 0
        if (state.quantity + delta < 0) return { rows: [] };
        state.quantity += delta;
        return {
          rows: [{
            id: 'inv-1',
            drink_id: drinkId,
            drink_name: 'Craft Beer',
            quantity: state.quantity,
          }],
        };
      }
      if (/SELECT quantity, drink_name FROM inventory/i.test(sql)) {
        return {
          rows: state.stocked
            ? [{ quantity: state.quantity, drink_name: 'Craft Beer' }]
            : [],
        };
      }
      if (/INSERT INTO inventory_transactions/i.test(sql)) {
        state.transactions.push(params);
        return { rows: [] };
      }
      throw new Error('Unexpected SQL in fake db: ' + sql);
    },
  };
}

const reqFor = (db, body) => ({
  db,
  user: { id: 7, role: 'Staff', company_id: 3 },
  query: {},
  params: {},
  headers: {},
  body,
});

describe('POST /inventory/sell — race condition guard', () => {
  const handler = routeHandler('post', '/inventory/sell');

  test('two simultaneous sales of the last item: only one succeeds', async () => {
    const db = fakeDb({ quantity: 1 });

    const sell = async () => {
      const res = fakeRes();
      await handler(reqFor(db, { drink_id: 'beer-1', quantity: 1 }), res);
      return res;
    };

    const [first, second] = await Promise.all([sell(), sell()]);

    const statuses = [first.statusCode, second.statusCode].sort();
    expect(statuses).toEqual([200, 409]); // exactly one sale wins
    expect(db.state.quantity).toBe(0);    // never negative
  });

  test('rejection reports how many are actually available', async () => {
    const db = fakeDb({ quantity: 0 });
    const res = fakeRes();
    await handler(reqFor(db, { drink_id: 'beer-1', quantity: 1 }), res);

    expect(res.statusCode).toBe(409);
    expect(res.body.error).toBe('insufficient_stock');
    expect(res.body.available).toBe(0);
    expect(db.state.quantity).toBe(0);
  });

  test('a successful sale records a stock-out movement', async () => {
    const db = fakeDb({ quantity: 5 });
    const res = fakeRes();
    await handler(
      reqFor(db, { drink_id: 'beer-1', quantity: 2, reason: 'sale', order_id: 'ord-9' }),
      res
    );

    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({
      success: true,
      remaining: 3,
      drinkName: 'Craft Beer',
    });
    expect(db.state.transactions).toHaveLength(1);
    expect(db.state.transactions[0]).toContain(2);
    expect(db.state.transactions[0]).toContain('out');
    expect(db.state.transactions[0]).toContain('ord-9');
  });

  test('rejects malformed requests', async () => {
    const db = fakeDb({ quantity: 5 });

    const missing = fakeRes();
    await handler(reqFor(db, { quantity: 1 }), missing);
    expect(missing.statusCode).toBe(400);

    const negative = fakeRes();
    await handler(reqFor(db, { drink_id: 'beer-1', quantity: -2 }), negative);
    expect(negative.statusCode).toBe(400);

    expect(db.state.quantity).toBe(5);
  });
});

describe('POST /inventory/adjust — legal stock-in / stock-out edits', () => {
  const handler = routeHandler('post', '/inventory/adjust');

  test('stock-in increases quantity and is logged as a movement', async () => {
    const db = fakeDb({ quantity: 4 });
    const res = fakeRes();
    await handler(
      reqFor(db, { drink_id: 'beer-1', delta: 6, type: 'in', reason: 'restock' }),
      res
    );

    expect(res.statusCode).toBe(200);
    expect(db.state.quantity).toBe(10);
    expect(db.state.transactions[0]).toContain('in');
  });

  test('stock-out cannot take the balance below zero', async () => {
    const db = fakeDb({ quantity: 3 });
    const res = fakeRes();
    await handler(
      reqFor(db, { drink_id: 'beer-1', delta: 5, type: 'out', reason: 'waste' }),
      res
    );

    expect(res.statusCode).toBe(409);
    expect(res.body.available).toBe(3);
    expect(db.state.quantity).toBe(3); // refused, not illegal
  });

  test('a zero delta is rejected', async () => {
    const db = fakeDb({ quantity: 3 });
    const res = fakeRes();
    await handler(reqFor(db, { drink_id: 'beer-1', delta: 0 }), res);
    expect(res.statusCode).toBe(400);
  });
});