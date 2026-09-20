// ============================================================
// DATA ROUTES — session-authenticated, company-scoped CRUD.
// Replaces the app's direct Supabase REST access (anon key).
// Responses mirror PostgREST shapes (bare arrays, 201/204) so
// the Flutter client keeps its existing parsing.
// ============================================================
const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { getSessionUser } = require('../middleware/sessionAuth');

const MANAGER_ROLES = ['Manager', 'Administrator', 'Admin'];

// Secrets that must never leave the server for non-managers.
const COMPANY_SECRET_COLUMNS = [
  'mtn_api_key', 'mtn_secret_key', 'orange_api_key', 'orange_secret_key',
  'mtn_api_key_encrypted', 'mtn_secret_key_encrypted',
  'orange_api_key_encrypted', 'orange_secret_key_encrypted',
];

// Return a company row with secret columns removed.
function stripSecrets(company) {
  const out = { ...company };
  for (const col of COMPANY_SECRET_COLUMNS) delete out[col];
  return out;
}

// Columns clients may write, per table (whitelist — column names are
// interpolated into SQL, so nothing outside these lists is accepted).
const WRITABLE = {
  // NOTE: current_stock is intentionally NOT writable on drinks —
  // inventory.quantity is the single source of truth for stock.
  // GET /drinks derives current_stock from the inventory table via JOIN.
  drinks: ['id', 'name', 'price', 'category', 'image_url', 'company_id', 'created_by',
    'is_active', 'minimum_level', 'purchase_price', 'unit', 'barcode', 'units_per_pack',
    'unit_kind', 'production_date', 'expiry_date', 'created_at', 'updated_at'],
  orders: ['id', 'company_id', 'items', 'total_amount', 'amount_paid', 'balance',
    'receipt_number', 'date', 'is_active', 'customer_name', 'staff_name', 'created_by', 'created_at'],
  inventory: ['id', 'company_id', 'drink_id', 'drink_name', 'quantity', 'min_stock_level',
    'category', 'unit', 'purchase_price', 'last_restocked', 'created_at'],
  inventory_transactions: ['id', 'company_id', 'drink_id', 'drink_name', 'quantity',
    'type', 'reason', 'order_id', 'performed_by', 'date', 'purchase_price_at_sale', 'selling_price_at_sale'],
  forecast_events: ['id', 'company_id', 'name', 'event_date', 'multiplier', 'created_by', 'created_at'],
  payment_transactions: ['order_id', 'company_id', 'customer_phone', 'amount',
    'payment_method', 'transaction_id', 'status', 'reference', 'error_message', 'created_at'],
  company_payment_settings: ['name', 'email', 'phone', 'address', 'currency_symbol',
    // Company branding: the shop logo the app uploads (public Storage URL).
    'logo_url',
    'currency_position', 'decimal_separator', 'thousands_separator', 'decimal_places',
    'business_payments_enabled', 'mtn_enabled', 'orange_enabled', 'mtn_merchant_phone',
    'orange_merchant_phone', 'mtn_merchant_id', 'orange_merchant_id', 'mtn_sandbox_mode',
    'orange_sandbox_mode', 'mtn_api_key_encrypted', 'mtn_secret_key_encrypted',
    'orange_api_key_encrypted', 'orange_secret_key_encrypted', 'updated_at'],
};

// ---------- auth + company scoping ----------
router.use(async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    const token = authHeader && authHeader.startsWith('Bearer ')
      ? authHeader.split(' ')[1]
      : null;
    const user = await getSessionUser(req.db, token);
    if (!user) {
      return res.status(401).json({ message: 'Authentication required: invalid or expired session' });
    }
    req.user = user;
    next();
  } catch (error) {
    next(error);
  }
});

// Resolve which company this request operates on.
// Users belong to a company; Administrators may pass ?company_id= explicitly.
function resolveCompanyId(req, res) {
  if (req.user.company_id != null) return req.user.company_id;
  const override = req.query.company_id || (req.body && req.body.company_id);
  if (override != null && MANAGER_ROLES.includes(req.user.role)) {
    return parseInt(override, 10);
  }
  res.status(400).json({ message: 'No company associated with this account' });
  return null;
}

// Pick only whitelisted columns out of a client body.
function pickWritable(table, body) {
  const allowed = WRITABLE[table] || [];
  const out = {};
  for (const key of allowed) {
    if (body[key] !== undefined) out[key] = body[key];
  }
  return out;
}

// Plaintext payment secrets must NEVER leave the server — not even to
// managers (they manage keys through the write-only payment-settings PATCH,
// which only accepts the *_encrypted columns).
// ============================================================
// 🏢 COMPANY
// ============================================================
// ============================================================
// 🍺 DRINKS
// ============================================================
router.get('/drinks', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    // inventory.quantity is the single source of truth for stock:
    // derive current_stock from inventory, falling back to the legacy
    // drinks.current_stock only for drinks with no inventory row.
    const result = await req.db.query(
      `SELECT d.*, COALESCE(i.quantity, d.current_stock, 0) AS current_stock
         FROM drinks d
         LEFT JOIN inventory i ON i.drink_id = d.id AND i.company_id = d.company_id
        WHERE d.company_id = $1 AND d.is_active = true
        ORDER BY d.name ASC`,
      [companyId]
    );
    res.json(result.rows);
  } catch (error) {
    console.error('GET /drinks error:', error.message);
    res.status(500).json({ message: 'Failed to load drinks' });
  }
});

router.post('/drinks', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const body = pickWritable('drinks', { ...req.body, company_id: companyId });
    const cols = Object.keys(body);
    const sql = `INSERT INTO drinks (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')}) RETURNING *`;
    const result = await req.db.query(sql, cols.map(c => body[c]));
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('POST /drinks error:', error.message);
    res.status(500).json({ message: 'Failed to save drink' });
  }
});

router.patch('/drinks/:id', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const updates = pickWritable('drinks', req.body);
    const cols = Object.keys(updates);
    // current_stock-only updates are expected (the app optimistically syncs
    // stock on drinks) — inventory is the source of truth, so just no-op.
    if (cols.length === 0) return res.status(204).end();
    const sql = `UPDATE drinks SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(', ')} WHERE id = $${cols.length + 1} AND company_id = $${cols.length + 2}`;
    await req.db.query(sql, [...cols.map(c => updates[c]), req.params.id, companyId]);
    res.status(204).end();
  } catch (error) {
    console.error('PATCH /drinks/:id error:', error.message);
    res.status(500).json({ message: 'Failed to update drink' });
  }
});

router.delete('/drinks/:id', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    await req.db.query('DELETE FROM drinks WHERE id = $1 AND company_id = $2', [req.params.id, companyId]);
    res.status(204).end();
  } catch (error) {
    console.error('DELETE /drinks/:id error:', error.message);
    res.status(500).json({ message: 'Failed to delete drink' });
  }
});

// ============================================================
// 📋 ORDERS
// ============================================================
router.get('/orders', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    // staff_name is returned explicitly so the app can attribute a sale to the
    // staff member who took it (manager dashboard → "Sales by Staff").
    // Orders stored before the staff_name column existed, or saved without a
    // staff name, fall back to the username of the user who created them.
    let result;
    try {
      result = await req.db.query(
        `SELECT o.*,
                COALESCE(NULLIF(o.staff_name, ''), u.username, '') AS staff_name
         FROM orders o
         LEFT JOIN users u ON u.id = o.created_by
         WHERE o.company_id = $1
         ORDER BY o.created_at DESC`,
        [companyId]
      );
    } catch (joinErr) {
      // staff_name column (or orders.created_by) not migrated yet — the
      // dashboard simply shows no staff breakdown instead of failing.
      console.log('⚠️ GET /orders staff_name join skipped:', joinErr.message);
      result = await req.db.query(
        'SELECT * FROM orders WHERE company_id = $1 ORDER BY created_at DESC',
        [companyId]
      );
    }
    res.json(result.rows);
  } catch (error) {
    console.error('GET /orders error:', error.message);
    res.status(500).json({ message: 'Failed to load orders' });
  }
});

router.post('/orders', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const body = pickWritable('orders', { ...req.body, company_id: companyId });
    if (body.items !== undefined && typeof body.items !== 'string') {
      body.items = JSON.stringify(body.items);
    }
    const insertOrder = (payload) => {
      const cols = Object.keys(payload);
      const sql = `INSERT INTO orders (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')}) RETURNING *`;
      return req.db.query(sql, cols.map(c => payload[c]));
    };

    let result;
    try {
      result = await insertOrder(body);
    } catch (insertErr) {
      // orders.staff_name not migrated yet (or an older schema): save the
      // sale without the staff attribution instead of failing the order.
      if (body.staff_name !== undefined && /staff_name/i.test(insertErr.message || '')) {
        console.log('⚠️ POST /orders retry without staff_name:', insertErr.message);
        const { staff_name, ...withoutStaffName } = body;
        result = await insertOrder(withoutStaffName);
      } else {
        throw insertErr;
      }
    }
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('POST /orders error:', error.message);
    res.status(500).json({ message: 'Failed to save order' });
  }
});

router.patch('/orders/:id', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const updates = pickWritable('orders', req.body);
    const cols = Object.keys(updates);
    if (cols.length === 0) return res.status(400).json({ message: 'No valid fields to update' });
    const sql = `UPDATE orders SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(', ')} WHERE id = $${cols.length + 1} AND company_id = $${cols.length + 2}`;
    await req.db.query(sql, [...cols.map(c => updates[c]), req.params.id, companyId]);
    res.status(204).end();
  } catch (error) {
    console.error('PATCH /orders/:id error:', error.message);
    res.status(500).json({ message: 'Failed to update order' });
  }
});

// ============================================================
// 📅 FORECAST EVENTS (company-wide demand-boost events)
// ============================================================
router.get('/events', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const result = await req.db.query(
      `SELECT id, company_id, name, event_date, multiplier, created_by, created_at
       FROM forecast_events
       WHERE company_id = $1
       ORDER BY event_date ASC`,
      [companyId]
    );
    res.json(result.rows);
  } catch (error) {
    console.error('GET /events error:', error.message);
    res.status(500).json({ message: 'Failed to load forecast events' });
  }
});

router.post('/events', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const body = pickWritable('forecast_events', {
      ...req.body,
      company_id: companyId,
    });
    if (!body.name || !body.event_date) {
      return res.status(400).json({ message: 'Event name and date are required' });
    }
    const cols = Object.keys(body);
    const sql = `INSERT INTO forecast_events (${cols.join(', ')}) VALUES (${cols
      .map((c, i) => `$${i + 1}`)
      .join(', ')}) RETURNING *`;
    const result = await req.db.query(sql, cols.map(c => body[c]));
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('POST /events error:', error.message);
    res.status(500).json({ message: 'Failed to save forecast event' });
  }
});

router.delete('/events/:id', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    await req.db.query(
      'DELETE FROM forecast_events WHERE id = $1 AND company_id = $2',
      [req.params.id, companyId]
    );
    res.status(204).end();
  } catch (error) {
    console.error('DELETE /events/:id error:', error.message);
    res.status(500).json({ message: 'Failed to delete forecast event' });
  }
});

// ============================================================
// 📦 INVENTORY
// ============================================================
router.get('/inventory', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const result = await req.db.query(
      'SELECT * FROM inventory WHERE company_id = $1', [companyId]);
    res.json(result.rows);
  } catch (error) {
    console.error('GET /inventory error:', error.message);
    res.status(500).json({ message: 'Failed to load inventory' });
  }
});

router.post('/inventory', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const body = pickWritable('inventory', { ...req.body, company_id: companyId });
    if (!body.id) body.id = crypto.randomUUID(); // id is a NOT NULL text PK with no DB default
    const cols = Object.keys(body);
    const sql = `INSERT INTO inventory (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')}) RETURNING *`;
    const result = await req.db.query(sql, cols.map(c => body[c]));
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('POST /inventory error:', error.message);
    res.status(500).json({ message: 'Failed to save inventory' });
  }
});

router.patch('/inventory/:id', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const updates = pickWritable('inventory', req.body);
    const cols = Object.keys(updates);
    if (cols.length === 0) return res.status(400).json({ message: 'No valid fields to update' });
    const sql = `UPDATE inventory SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(', ')} WHERE id = $${cols.length + 1} AND company_id = $${cols.length + 2}`;
    await req.db.query(sql, [...cols.map(c => updates[c]), req.params.id, companyId]);
    res.status(204).end();
  } catch (error) {
    console.error('PATCH /inventory/:id error:', error.message);
    res.status(500).json({ message: 'Failed to update inventory' });
  }
});

// Upsert by (drink_id, company_id) — mirrors the app's check-then-write flow.
router.post('/inventory/upsert', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const body = pickWritable('inventory', { ...req.body, company_id: companyId });
    if (!body.drink_id) return res.status(400).json({ message: 'drink_id is required' });
    if (!body.id) body.id = crypto.randomUUID(); // id is a NOT NULL text PK with no DB default
    const cols = Object.keys(body);
    const updates = cols.filter(c => c !== 'id' && c !== 'created_at');
    const sql = `INSERT INTO inventory (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')})
      ON CONFLICT (drink_id, company_id) DO UPDATE SET ${updates.map(c => `${c} = EXCLUDED.${c}`).join(', ')}
      RETURNING *`;
    const result = await req.db.query(sql, cols.map(c => body[c]));
    res.status(201).json(result.rows[0]);
  } catch (error) {
    if (error.message && error.message.includes('no unique or exclusion constraint')) {
      // No DB unique constraint on (drink_id, company_id) — fall back to check-then-write.
      try {
        const existing = await req.db.query(
          'SELECT id FROM inventory WHERE drink_id = $1 AND company_id = $2',
          [req.body.drink_id, req.user.company_id]
        );
        const body = pickWritable('inventory', { ...req.body, company_id: req.user.company_id });
        if (existing.rows.length > 0) {
          const cols = Object.keys(body);
          const sql = `UPDATE inventory SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(', ')} WHERE drink_id = $${cols.length + 1} AND company_id = $${cols.length + 2}`;
          await req.db.query(sql, [...cols.map(c => body[c]), req.body.drink_id, req.user.company_id]);
        } else {
          const cols = Object.keys(body);
          const sql = `INSERT INTO inventory (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')})`;
          await req.db.query(sql, cols.map(c => body[c]));
        }
        return res.status(201).end();
      } catch (inner) {
        console.error('POST /inventory/upsert fallback error:', inner.message);
        return res.status(500).json({ message: 'Failed to save inventory' });
      }
    }
    console.error('POST /inventory/upsert error:', error.message);
    res.status(500).json({ message: 'Failed to save inventory' });
  }
});

// ============================================================
// 🔒 ATOMIC STOCK MOVEMENTS
// ============================================================
// Both endpoints move stock with a SINGLE conditional UPDATE, so the
// check-and-write happens inside one row lock. Two staff selling the last item
// at the same moment therefore cannot both succeed, and quantity can never go
// negative (no "last case sold twice" race).
async function applyStockDelta({ db, companyId, userId, drinkId, delta, body }) {
  const result = await db.query(
    `UPDATE inventory
        SET quantity = quantity + $1
      WHERE company_id = $2 AND drink_id = $3 AND quantity + $1 >= 0
      RETURNING id, drink_id, drink_name, quantity`,
    [delta, companyId, drinkId]
  );

  if (result.rows.length === 0) {
    // Either the drink is not stocked yet, or the guard rejected the move.
    const current = await db.query(
      'SELECT quantity, drink_name FROM inventory WHERE company_id = $1 AND drink_id = $2',
      [companyId, drinkId]
    );
    return {
      ok: false,
      notStocked: current.rows.length === 0,
      available: current.rows.length > 0 ? Number(current.rows[0].quantity) : 0,
      drinkName: current.rows.length > 0 ? current.rows[0].drink_name : null,
    };
  }

  const row = result.rows[0];

  // 📄 Audit trail: every movement is recorded as stock-in / stock-out.
  try {
    const txn = buildMovementTransaction({
      companyId,
      userId,
      drinkId,
      drinkName: row.drink_name,
      quantity: Math.abs(delta),
      type: delta < 0 ? 'out' : 'in',
      body,
    });
    const cols = Object.keys(txn);
    await db.query(
      `INSERT INTO inventory_transactions (${cols.join(', ')})
       VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')})`,
      cols.map(c => txn[c])
    );
  } catch (txnErr) {
    // Never fail the stock movement because the audit row could not be written.
    console.error('⚠️ inventory transaction log skipped:', txnErr.message);
  }

  return { ok: true, remaining: Number(row.quantity), drinkName: row.drink_name };
}

function buildMovementTransaction({ companyId, userId, drinkId, drinkName, quantity, type, body }) {
  const txn = {
    id: crypto.randomUUID(),
    company_id: companyId,
    drink_id: drinkId,
    drink_name: drinkName || '',
    quantity,
    type,
    reason: body && body.reason ? String(body.reason) : (type === 'out' ? 'sale' : 'restock'),
    order_id: body && body.order_id != null ? String(body.order_id) : null,
    performed_by: body && body.performed_by
      ? String(body.performed_by)
      : (userId != null ? String(userId) : null),
    date: new Date().toISOString(),
  };
  if (body && body.selling_price_at_sale !== undefined) {
    txn.selling_price_at_sale = body.selling_price_at_sale;
  }
  return txn;
}

// 🛒 Sell (or waste) stock — refuses to go negative.
router.post('/inventory/sell', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const { drink_id, quantity } = req.body || {};
    const qty = parseInt(quantity, 10);
    if (!drink_id) return res.status(400).json({ message: 'drink_id is required' });
    if (!Number.isFinite(qty) || qty <= 0) {
      return res.status(400).json({ message: 'quantity must be a positive integer' });
    }

    const outcome = await applyStockDelta({
      db: req.db,
      companyId,
      userId: req.user && req.user.id,
      drinkId: String(drink_id),
      delta: -qty,
      body: req.body,
    });

    if (!outcome.ok) {
      return res.status(409).json({
        success: false,
        error: 'insufficient_stock',
        available: outcome.available,
        drinkName: outcome.drinkName,
        message: outcome.notStocked
          ? 'This drink is not stocked yet'
          : `Only ${outcome.available} left in stock`,
      });
    }

    res.json({ success: true, remaining: outcome.remaining, drinkName: outcome.drinkName });
  } catch (error) {
    console.error('POST /inventory/sell error:', error.message);
    res.status(500).json({ message: 'Failed to sell stock' });
  }
});

// 📥📤 Stock-in / stock-out adjustment. Manager stock edits become recorded
// movements (so they stay legal and auditable) instead of blind overwrites.
router.post('/inventory/adjust', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const { drink_id, delta, type } = req.body || {};
    const amount = parseInt(delta, 10);
    if (!drink_id) return res.status(400).json({ message: 'drink_id is required' });
    if (!Number.isFinite(amount) || amount === 0) {
      return res.status(400).json({ message: 'delta must be a non-zero integer' });
    }
    // `type` only clarifies the intent ('in' | 'out'); the sign of delta wins.
    const signed = type === 'out' && amount > 0 ? -amount : amount;

    const outcome = await applyStockDelta({
      db: req.db,
      companyId,
      userId: req.user && req.user.id,
      drinkId: String(drink_id),
      delta: signed,
      body: req.body,
    });

    if (!outcome.ok) {
      return res.status(409).json({
        success: false,
        error: outcome.notStocked ? 'not_stocked' : 'insufficient_stock',
        available: outcome.available,
        message: outcome.notStocked
          ? 'This drink is not stocked yet'
          : `Only ${outcome.available} left — cannot remove ${Math.abs(signed)}`,
      });
    }

    res.json({ success: true, remaining: outcome.remaining, drinkName: outcome.drinkName });
  } catch (error) {
    console.error('POST /inventory/adjust error:', error.message);
    res.status(500).json({ message: 'Failed to adjust stock' });
  }
});

// ============================================================
// 📊 INVENTORY TRANSACTIONS
// ============================================================
router.get('/inventory-transactions', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const result = await req.db.query(
      'SELECT * FROM inventory_transactions WHERE company_id = $1 ORDER BY date DESC',
      [companyId]
    );
    res.json(result.rows);
  } catch (error) {
    console.error('GET /inventory-transactions error:', error.message);
    res.status(500).json({ message: 'Failed to load transactions' });
  }
});

router.post('/inventory-transactions', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const body = pickWritable('inventory_transactions', { ...req.body, company_id: companyId });
    const cols = Object.keys(body);
    const sql = `INSERT INTO inventory_transactions (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')}) RETURNING *`;
    const result = await req.db.query(sql, cols.map(c => body[c]));
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('POST /inventory-transactions error:', error.message);
    res.status(500).json({ message: 'Failed to save transaction' });
  }
});

// ============================================================
// ⚙️ SETTINGS (per-user; identity always comes from the session)
// ============================================================
router.get('/settings', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const result = await req.db.query(
      'SELECT * FROM settings WHERE user_id = $1 AND company_id = $2',
      [req.user.id, companyId]
    );
    res.json(result.rows);
  } catch (error) {
    console.error('GET /settings error:', error.message);
    res.status(500).json({ message: 'Failed to load settings' });
  }
});

router.put('/settings', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const allowed = ['theme_mode', 'primary_color', 'compact_mode', 'show_notifications',
      'auto_sync', 'company_name', 'company_email', 'company_phone', 'company_address',
      'business_payments', 'mtn_enabled', 'orange_enabled'];
    const body = {};
    for (const key of allowed) {
      if (req.body[key] !== undefined) body[key] = req.body[key];
    }
    const existing = await req.db.query(
      'SELECT id FROM settings WHERE user_id = $1 AND company_id = $2',
      [req.user.id, companyId]
    );
    if (existing.rows.length > 0) {
      const cols = Object.keys(body);
      if (cols.length === 0) return res.status(204).end();
      const sql = `UPDATE settings SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(', ')}, updated_at = NOW() WHERE user_id = $${cols.length + 1} AND company_id = $${cols.length + 2}`;
      await req.db.query(sql, [...cols.map(c => body[c]), req.user.id, companyId]);
      res.status(204).end();
    } else {
      const cols = ['user_id', 'company_id', ...Object.keys(body)];
      const values = [req.user.id, companyId, ...Object.values(body)];
      const sql = `INSERT INTO settings (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')})`;
      await req.db.query(sql, values);
      res.status(201).end();
    }
  } catch (error) {
    console.error('PUT /settings error:', error.message);
    res.status(500).json({ message: 'Failed to save settings' });
  }
});

// ============================================================
// 🏢 COMPANY (non-secret profile fields)
// ============================================================
router.get('/company', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    // Only safe, non-secret fields are returned to the client.
    const result = await req.db.query(
      `SELECT id, name, email, phone, address, currency_symbol, currency_position,
              decimal_separator, thousands_separator, decimal_places,
              business_payments_enabled, mtn_enabled, orange_enabled,
              mtn_merchant_phone, orange_merchant_phone, mtn_merchant_id,
              orange_merchant_id, mtn_sandbox_mode, orange_sandbox_mode
       FROM companies WHERE id = $1`,
      [companyId]
    );
    res.json(result.rows);
  } catch (error) {
    console.error('GET /company error:', error.message);
    res.status(500).json({ message: 'Failed to load company' });
  }
});

// ============================================================
// 💳 PAYMENT TRANSACTIONS (server-side; keys never reach the client)
// ============================================================
router.post('/payment-transactions', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const body = pickWritable('payment_transactions', { ...req.body, company_id: companyId });
    const cols = Object.keys(body);
    if (cols.length === 0) return res.status(400).json({ message: 'No valid fields' });
    const sql = `INSERT INTO payment_transactions (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')}) RETURNING *`;
    const result = await req.db.query(sql, cols.map(c => body[c]));
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('POST /payment-transactions error:', error.message);
    res.status(500).json({ message: 'Failed to save transaction' });
  }
});

router.patch('/payment-transactions/order/:orderId', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const allowed = ['status', 'error_message', 'confirmed_at', 'updated_at'];
    const body = {};
    for (const key of allowed) {
      if (req.body[key] !== undefined) body[key] = req.body[key];
    }
    const cols = Object.keys(body);
    if (cols.length === 0) return res.status(400).json({ message: 'No valid fields' });
    const sql = `UPDATE payment_transactions SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(', ')} WHERE order_id = $${cols.length + 1} AND company_id = $${cols.length + 2}`;
    const result = await req.db.query(sql, [...Object.values(body), req.params.orderId, companyId]);
    if (result.rowCount === 0) return res.status(404).json({ message: 'Transaction not found' });
    res.status(204).end();
  } catch (error) {
    console.error('PATCH /payment-transactions error:', error.message);
    res.status(500).json({ message: 'Failed to update transaction' });
  }
});

router.get('/payment-transactions/order/:orderId', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const result = await req.db.query(
      'SELECT * FROM payment_transactions WHERE order_id = $1 AND company_id = $2',
      [req.params.orderId, companyId]
    );
    res.json(result.rows);
  } catch (error) {
    console.error('GET /payment-transactions/order error:', error.message);
    res.status(500).json({ message: 'Failed to load transaction' });
  }
});

// ============================================================
// 💳 PAYMENT TRANSACTIONS
// ============================================================
router.get('/payment-transactions', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const orderId = req.query.order_id;
    if (orderId) {
      const result = await req.db.query(
        'SELECT * FROM payment_transactions WHERE order_id = $1 AND company_id = $2 ORDER BY created_at DESC LIMIT 1',
        [orderId, companyId]
      );
      return res.json(result.rows);
    }
    const result = await req.db.query(
      'SELECT * FROM payment_transactions WHERE company_id = $1 ORDER BY created_at DESC',
      [companyId]
    );
    res.json(result.rows);
  } catch (error) {
    console.error('GET /payment-transactions error:', error.message);
    res.status(500).json({ message: 'Failed to load transactions' });
  }
});

router.post('/payment-transactions', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const allowed = ['order_id', 'customer_phone', 'amount', 'payment_method',
      'transaction_id', 'status', 'reference', 'error_message'];
    const body = {};
    for (const key of allowed) {
      if (req.body[key] !== undefined) body[key] = req.body[key];
    }
    const cols = ['company_id', ...Object.keys(body)];
    const values = [companyId, ...Object.values(body)];
    const sql = `INSERT INTO payment_transactions (${cols.join(', ')}) VALUES (${cols.map((c, i) => `$${i + 1}`).join(', ')}) RETURNING *`;
    const result = await req.db.query(sql, values);
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('POST /payment-transactions error:', error.message);
    res.status(500).json({ message: 'Failed to save transaction' });
  }
});

router.patch('/payment-transactions/status', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const { order_id, status, error_message } = req.body;
    if (!order_id || !status) {
      return res.status(400).json({ message: 'order_id and status required' });
    }
    const updates = { status };
    let sql, params;
    if (error_message !== undefined) {
      sql = `UPDATE payment_transactions SET status = $1, error_message = $2, updated_at = NOW()${status === 'completed' ? ', confirmed_at = NOW()' : ''} WHERE order_id = $3 AND company_id = $4`;
      params = [status, error_message, order_id, companyId];
    } else {
      sql = `UPDATE payment_transactions SET status = $1, updated_at = NOW()${status === 'completed' ? ', confirmed_at = NOW()' : ''} WHERE order_id = $2 AND company_id = $3`;
      params = [status, order_id, companyId];
    }
    await req.db.query(sql, params);
    res.status(204).end();
  } catch (error) {
    console.error('PATCH /payment-transactions/status error:', error.message);
    res.status(500).json({ message: 'Failed to update transaction' });
  }
});

// ============================================================
// 🏢 COMPANY (safe fields only — payment API keys never leave the server)
// ============================================================
router.patch('/company', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    if (!['Manager', 'Administrator', 'Admin'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Only managers can update company settings' });
    }
    // 🔒 Secrets (incl. *_encrypted credential columns) can only be written
    // through the dedicated /company/payment-credentials endpoint below.
    const updates = pickWritable('company_payment_settings', req.body);
    for (const k of ['mtn_api_key_encrypted', 'mtn_secret_key_encrypted',
      'orange_api_key_encrypted', 'orange_secret_key_encrypted']) {
      delete updates[k];
    }
    const cols = Object.keys(updates);
    if (cols.length === 0) {
      return res.status(400).json({ message: 'No valid fields to update' });
    }
    updates.updated_at = new Date().toISOString();
    const cols2 = Object.keys(updates);
    const sql = `UPDATE companies SET ${cols2.map((c, i) => `${c} = $${i + 1}`).join(', ')} WHERE id = $${cols2.length + 1} RETURNING *`;
    const result = await req.db.query(sql, [...cols2.map(c => updates[c]), companyId]);
    res.json(stripSecrets(result.rows[0]));
  } catch (error) {
    console.error('PATCH /company error:', error.message);
    res.status(500).json({ message: 'Failed to update company' });
  }
});

// 💳 Dedicated endpoint for payment credentials (manager-only, secrets stripped from response)
router.patch('/company/payment-credentials', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    if (!['Manager', 'Administrator', 'Admin'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Only managers can update payment credentials' });
    }
    const credKeys = ['mtn_api_key_encrypted', 'mtn_secret_key_encrypted',
      'orange_api_key_encrypted', 'orange_secret_key_encrypted'];
    const body = {};
    for (const key of credKeys) {
      if (req.body[key] !== undefined) body[key] = req.body[key];
    }
    const cols = Object.keys(body);
    if (cols.length === 0) {
      return res.status(400).json({ message: 'No credential fields provided' });
    }
    const sql = `UPDATE companies SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(', ')}, updated_at = NOW() WHERE id = $${cols.length + 1}`;
    await req.db.query(sql, [...Object.values(body), companyId]);
    res.json({ success: true });
  } catch (error) {
    console.error('PATCH /company/payment-credentials error:', error.message);
    res.status(500).json({ message: 'Failed to update payment credentials' });
  }
});

// ============================================================
// 🏢 COMPANY PROFILE (secret-stripped — anon keys can no longer read this table)
// ============================================================
router.get('/company', async (req, res) => {
  try {
    const companyId = resolveCompanyId(req, res);
    if (companyId == null) return;
    const result = await req.db.query('SELECT * FROM companies WHERE id = $1', [companyId]);
    if (result.rows.length === 0) return res.status(404).json({ message: 'Company not found' });
    res.json(stripSecrets(result.rows[0]));
  } catch (error) {
    console.error('GET /company error:', error.message);
    res.status(500).json({ message: 'Failed to load company' });
  }
});

// 🏢 COMPANY BY ID (secret-stripped) — used by the app's getCompany()/getCompanyPaymentSettings().
// Staff/Customers may only read their own company; managers/admins may read any.
router.get('/company/:id', async (req, res) => {
  try {
    const requestedId = parseInt(req.params.id, 10);
    if (Number.isNaN(requestedId)) {
      return res.status(400).json({ message: 'Invalid company id' });
    }
    const isManager = ['Manager', 'Administrator', 'Admin'].includes(req.user.role);
    if (!isManager && req.user.company_id != null && req.user.company_id !== requestedId) {
      return res.status(403).json({ message: 'Not authorized to view this company' });
    }
    const result = await req.db.query('SELECT * FROM companies WHERE id = $1', [requestedId]);
    if (result.rows.length === 0) return res.status(404).json({ message: 'Company not found' });
    res.json(stripSecrets(result.rows[0]));
  } catch (error) {
    console.error('GET /company/:id error:', error.message);
    res.status(500).json({ message: 'Failed to load company' });
  }
});

// NOTE: /company/:id/public lives in server.js (unauthenticated, outside this
// router's session check) so customer mode can read the public profile.

module.exports = router;

