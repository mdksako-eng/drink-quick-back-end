/**
 * Schema / hardening guards - no database required.
 *
 * Locks in the security posture of the deployed schema so a later refactor
 * cannot silently re-open the anon key:
 *   - forecast_events must be created with RLS enabled and anon revoked.
 *   - the tier-2 lockdown scripts must cover the newer tables.
 *
 * Run with: npm test
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

describe('forecast_events hardening', () => {
  test('server.js enables RLS and revokes the client roles at boot', () => {
    const server = read('server.js');
    expect(server).toContain('ALTER TABLE forecast_events ENABLE ROW LEVEL SECURITY');
    expect(server).toContain('REVOKE ALL ON forecast_events FROM anon, authenticated');
  });

  test('a runnable RLS script exists for forecast_events', () => {
    const sql = read('sql/rls_forecast_events.sql');
    expect(sql).toContain('ALTER TABLE public.forecast_events ENABLE ROW LEVEL SECURITY');
    expect(sql).toContain('REVOKE ALL ON public.forecast_events FROM anon, authenticated');
    expect(fs.existsSync(path.join(root, 'scripts/apply_forecast_rls.js'))).toBe(true);
  });

  test('tier-2 lockdown covers the newer tables', () => {
    expect(read('sql/lock_tier2.sql')).toContain('public.forecast_events');
    expect(read('sql/lock_tier2.js')).toContain('forecast_events');
    expect(read('sql/lock_tier2.js')).toContain('notifications');
  });

  test('the lockdown script tolerates a table that does not exist yet', () => {
    // A fresh database has no notifications table: the script must warn and
    // carry on instead of aborting half-way through the lockdown.
    expect(read('sql/lock_tier2.js')).toContain('SKIPPED');
  });
});

describe('deploy identity', () => {
  test('/health reports a release marker and the process uptime', () => {
    const server = read('server.js');
    expect(server).toContain('const RELEASE =');
    expect(server).toContain('const SERVER_STARTED_AT = new Date()');
    expect(server).toContain('release: RELEASE');
    expect(server).toContain('uptimeSeconds:');
  });

  test('the release marker is a dated, non-empty string', () => {
    const match = read('server.js').match(/const RELEASE = '([^']+)'/);
    expect(match).not.toBeNull();
    expect(match[1].trim().length).toBeGreaterThan(0);
  });

  test('/health advertises the owner self-heal so the app can rely on it', () => {
    expect(read('server.js')).toContain('ownerSelfHeal: true');
  });
});

describe('company ownership self-heal', () => {
  test('login claims ownership only when the company has no owner yet', () => {
    const server = read('server.js');
    // Guarded update: never overwrite an existing owner.
    expect(server).toContain(
      'UPDATE companies SET owner_id = $1 WHERE id = $2 AND owner_id IS NULL'
    );
    // …and only for a Manager.
    expect(server).toContain("ownerId === null && user.role === 'Manager'");
  });
});

describe('notifications are device-only', () => {
  test('the backend exposes no notification routes', () => {
    const routes = read('routes/data.routes.js');
    expect(routes).not.toContain("'/notifications");
    expect(routes).not.toContain('FROM notifications');
    expect(routes).not.toContain('NOTIFICATION_MAX_AGE_DAYS');
  });

  test('the backend no longer creates a notifications table', () => {
    const server = read('server.js');
    expect(server).not.toContain('CREATE TABLE IF NOT EXISTS notifications');
    expect(server).not.toContain('idx_notifications_user');
  });

  test('an opt-in cleanup script exists for the old table', () => {
    expect(
      fs.existsSync(path.join(root, 'sql/drop_notifications_table.sql'))
    ).toBe(true);
  });

  test('the app never calls a notifications endpoint', () => {
    const config = fs.readFileSync(
      path.join(root, '..', 'lib', 'config', 'api_config.dart'),
      'utf8'
    );
    expect(config).not.toContain('dataNotifications');
  });

  test('the notification service keeps its history locally only', () => {
    const service = fs.readFileSync(
      path.join(root, '..', 'lib', 'services', 'notification_service.dart'),
      'utf8'
    );
    expect(service).toContain('SharedPreferences');
    expect(service).not.toContain('syncWithServer');
    expect(service).not.toContain('_pushToServer');
    expect(service).not.toContain('supabase_service');
  });
});

describe('customer accounts hardening', () => {
  test('server.js creates the customer + ledger tables with RLS on', () => {
    const server = read('server.js');
    expect(server).toContain('CREATE TABLE IF NOT EXISTS customers');
    expect(server).toContain('CREATE TABLE IF NOT EXISTS customer_credit_transactions');
    expect(server).toContain('ALTER TABLE customers ENABLE ROW LEVEL SECURITY');
    expect(server).toContain('REVOKE ALL ON customers FROM anon, authenticated');
    expect(server).toContain(
      'ALTER TABLE customer_credit_transactions ENABLE ROW LEVEL SECURITY'
    );
    expect(server).toContain(
      'REVOKE ALL ON customer_credit_transactions FROM anon, authenticated'
    );
  });

  test('a runnable RLS script exists for the customer tables', () => {
    const sql = read('sql/rls_customers.sql');
    expect(sql).toContain('ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY');
    expect(sql).toContain(
      'ALTER TABLE public.customer_credit_transactions ENABLE ROW LEVEL SECURITY'
    );
    expect(sql).toContain('REVOKE ALL ON public.customers FROM anon, authenticated');
  });

  test('only a manager may decide who gets a customer number', () => {
    const routes = read('routes/data.routes.js');
    // The decision route goes through the manager rule, never a bare role check.
    expect(routes).toContain('canDecideCustomer(req.user)');
    expect(routes).toContain('canEnrollCustomer(req.user)');
    expect(routes).toContain('canDecideStatus(customer.status, next)');
    // …and a staff enrolment can never carry a credit limit of its own.
    expect(routes).toContain('? Number(req.body.credit_limit) || 0');
  });

  test('the customer number is generated by the backend', () => {
    const routes = read('routes/data.routes.js');
    expect(routes).toContain('nextCustomerNumber(');
    expect(routes).toContain('canAddLedgerEntry({');
    expect(routes).toContain("code: 'CREDIT_LIMIT'");
  });
});

describe('shift / cash-up hardening', () => {
  test('server.js creates shifts with RLS on and one open shift per person', () => {
    const server = read('server.js');
    expect(server).toContain('CREATE TABLE IF NOT EXISTS shifts');
    expect(server).toContain('ALTER TABLE shifts ENABLE ROW LEVEL SECURITY');
    expect(server).toContain('REVOKE ALL ON shifts FROM anon, authenticated');
    expect(server).toContain('idx_shifts_one_open');
  });

  test('a runnable RLS script exists for shifts', () => {
    const sql = read('sql/rls_shifts.sql');
    expect(sql).toContain('ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY');
    expect(sql).toContain('REVOKE ALL ON public.shifts FROM anon, authenticated');
  });

  test('a staff member can only close their own shift', () => {
    const routes = read('routes/data.routes.js');
    expect(routes).toContain('canCloseShift({ user: req.user, shift })');
    expect(routes).toContain('validateOpeningFloat(req.body.opening_float)');
    expect(routes).toContain(
      'validateClose({ shift, cashCounted: req.body.cash_counted })'
    );
    expect(routes).toContain('openShiftProblem(openShifts.rows)');
  });

  test('the Z-report is frozen onto the row when the shift closes', () => {
    const routes = read('routes/data.routes.js');
    expect(routes).toContain('cash_expected = $2');
    expect(routes).toContain('payment_breakdown = $9');
    expect(routes).toContain("status = 'closed', cash_counted = $1");
  });
});

describe('money / audit evidence hardening', () => {
  // Found live on 2026-10-24: public.refunds, public.audit_log and
  // public.legal_acceptances were the only public tables left with RLS off, so the
  // anon key shipped in the app could read every refund and every sensitive action.
  const LOCKED = ['refunds', 'audit_log', 'legal_acceptances'];

  test('server.js enables RLS and revokes the client roles at boot', () => {
    const server = read('server.js');
    for (const table of LOCKED) {
      expect(server).toContain(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY`);
      expect(server).toContain(`REVOKE ALL ON ${table} FROM anon, authenticated`);
    }
  });

  test('the schema scripts that create them lock them too', () => {
    for (const sql of [read('sql/legal_acceptances.sql'), read('sql/refunds_audit.sql')]) {
      expect(sql).toContain('ENABLE ROW LEVEL SECURITY');
      expect(sql).toContain('FROM anon, authenticated');
    }
  });

  test('the tier-1 RLS script covers them as well', () => {
    const sql = read('sql/enable_rls.sql');
    for (const table of LOCKED) {
      expect(sql).toMatch(new RegExp(`ALTER TABLE\\s+${table}\\s+ENABLE ROW LEVEL SECURITY`));
    }
  });
});

describe('returnable container hardening', () => {
  test('server.js creates the container tables with RLS on and the roles revoked', () => {
    const server = read('server.js');
    expect(server).toContain('CREATE TABLE IF NOT EXISTS container_types');
    expect(server).toContain('CREATE TABLE IF NOT EXISTS container_transactions');
    expect(server).toContain('ALTER TABLE container_types ENABLE ROW LEVEL SECURITY');
    expect(server).toContain('REVOKE ALL ON container_types FROM anon, authenticated');
    expect(server).toContain('ALTER TABLE container_transactions ENABLE ROW LEVEL SECURITY');
    expect(server).toContain(
      'REVOKE ALL ON container_transactions FROM anon, authenticated'
    );
  });

  test('a runnable RLS script exists for the container tables', () => {
    const sql = read('sql/rls_containers.sql');
    expect(sql).toContain('ALTER TABLE public.container_types ENABLE ROW LEVEL SECURITY');
    expect(sql).toContain(
      'ALTER TABLE public.container_transactions ENABLE ROW LEVEL SECURITY'
    );
    expect(sql).toContain(
      'REVOKE ALL ON public.container_transactions FROM anon, authenticated'
    );
  });

  test('the routes enforce the ceiling instead of trusting the client', () => {
    // The pile may never go below zero and staff may not write off: the rule is
    // pure (utils/containerLedger.js, unit tested), the route must actually call it
    // with the customer's CURRENT outstanding count.
    const routes = read('routes/data.routes.js');
    expect(routes).toContain('validateMovement({');
    expect(routes).toContain('outstandingFor(entries, containerType.id)');
    expect(routes).toContain("'/containers/transactions'");
  });
});

describe('purchasing hardening', () => {
  test('server.js creates the buying tables with RLS on and the roles revoked', () => {
    const server = read('server.js');
    for (const table of ['suppliers', 'purchase_orders', 'purchase_order_lines']) {
      expect(server).toContain(`CREATE TABLE IF NOT EXISTS ${table}`);
      expect(server).toContain(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY`);
      expect(server).toContain(`REVOKE ALL ON ${table} FROM anon, authenticated`);
    }
  });

  test('a runnable RLS script exists for the buying tables', () => {
    const sql = read('sql/rls_purchasing.sql');
    for (const table of ['suppliers', 'purchase_orders', 'purchase_order_lines']) {
      expect(sql).toContain(`ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY`);
      expect(sql).toContain(`REVOKE ALL ON public.${table} FROM anon, authenticated`);
    }
  });

  test('receiving goes through the guarded stock path, never a bare UPDATE', () => {
    // Stock must move through applyStockDelta (it refuses to drive a shelf
    // negative and writes the movement); a receive route that updated inventory
    // directly would bypass both.
    const routes = read('routes/data.routes.js');
    expect(routes).toContain("'/purchase-orders/:id/receive'");
    expect(routes).toContain('purchasing.receivingPlan(');
    expect(routes).toContain('applyStockDelta({');
    // …and a manager's money decisions are checked on the writing routes.
    expect(routes).toContain('purchasing.canWriteOrders(req.user)');
  });
});