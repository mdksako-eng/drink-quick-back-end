/**
 * Orders route tests — no database required.
 *
 * Covers the "Sales by Staff" plumbing added to the manager dashboard:
 *   • GET /orders attributes a sale to its staff member and falls back to the
 *     username of the user who created the order.
 *   • POST /orders persists staff_name, and still saves the sale if the
 *     orders.staff_name column has not been migrated yet.
 * Run with: npm test
 */
const router = require('../routes/data.routes');

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

const managerReq = (db, body = {}) => ({
  db,
  user: { id: 9, role: 'Manager', company_id: 7 },
  query: {},
  body,
  params: {},
});

describe('GET /orders — staff attribution', () => {
  const handler = routeHandler('get', '/orders');

  test('joins users so every order carries a staff_name', async () => {
    const calls = [];
    const rows = [
      { id: '1', company_id: 7, total_amount: 10, created_by: 3, staff_name: 'Alice' },
    ];
    const db = {
      query: async (sql, params) => {
        calls.push({ sql, params });
        return { rows };
      },
    };

    const res = fakeRes();
    await handler(managerReq(db), res);

    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual(rows);
    expect(calls).toHaveLength(1);
    expect(calls[0].sql).toContain('LEFT JOIN users');
    expect(calls[0].sql).toContain('COALESCE(NULLIF(o.staff_name, \'\'), u.username, \'\') AS staff_name');
    expect(calls[0].sql).toContain('o.created_by');
    expect(calls[0].params).toEqual([7]);
  });

  test('falls back to a plain select when the staff_name join fails', async () => {
    const calls = [];
    const rows = [{ id: '2', company_id: 7, total_amount: 4 }];
    const db = {
      query: async (sql, params) => {
        calls.push({ sql, params });
        if (calls.length === 1) {
          throw new Error('column o.staff_name does not exist');
        }
        return { rows };
      },
    };

    const res = fakeRes();
    await handler(managerReq(db), res);

    // The dashboard must not break — orders still load, just without a breakdown.
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual(rows);
    expect(calls).toHaveLength(2);
    expect(calls[1].sql).toBe(
      'SELECT * FROM orders WHERE company_id = $1 ORDER BY created_at DESC'
    );
    expect(calls[1].params).toEqual([7]);
  });
});

describe('POST /orders — staff_name persistence', () => {
  const handler = routeHandler('post', '/orders');

  const orderBody = {
    id: '100',
    items: [{ id: 'beer', name: 'Beer', price: 2 }],
    total_amount: 2,
    amount_paid: 2,
    balance: 0,
    receipt_number: 'REC-100',
    date: '2026-09-15T10:00:00.000Z',
    is_active: true,
    customer_name: 'Jo',
    staff_name: 'Alice',
  };

  test('stores the staff member who took the order', async () => {
    const calls = [];
    const db = {
      query: async (sql, params) => {
        calls.push({ sql, params });
        return { rows: [{ id: '100', staff_name: 'Alice' }] };
      },
    };

    const res = fakeRes();
    await handler(managerReq(db, orderBody), res);

    expect(res.statusCode).toBe(201);
    expect(calls).toHaveLength(1);
    expect(calls[0].sql).toContain('staff_name');
    expect(calls[0].params).toContain('Alice');
    expect(calls[0].params).toContain(7);
  });

  test('saves the order without staff_name if the column is missing', async () => {
    const calls = [];
    const db = {
      query: async (sql, params) => {
        calls.push({ sql, params });
        if (calls.length === 1) {
          throw new Error('column "staff_name" of relation "orders" does not exist');
        }
        return { rows: [{ id: '100' }] };
      },
    };

    const res = fakeRes();
    await handler(managerReq(db, orderBody), res);

    expect(res.statusCode).toBe(201);
    expect(calls).toHaveLength(2);
    expect(calls[1].sql).not.toContain('staff_name');
    expect(calls[1].params).not.toContain('Alice');
    // The sale itself is never lost.
    expect(calls[1].params).toContain('REC-100');
  });

  test('other insert errors are still reported as a failure', async () => {
    const db = {
      query: async () => {
        throw new Error('duplicate key value violates unique constraint');
      },
    };

    const res = fakeRes();
    await handler(managerReq(db, orderBody), res);

    expect(res.statusCode).toBe(500);
    expect(res.body).toEqual({ message: 'Failed to save order' });
  });
});