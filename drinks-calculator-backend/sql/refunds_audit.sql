-- sql/refunds_audit.sql
-- Two tables that make sensitive actions durable.
--
-- 1) refunds — the money moves in the provider's dashboard (CamPay/Notch Pay: no
--    refund API is wired into this backend), so this row IS the company's proof:
--    who refunded, why, how much, and the provider reference that ties it to the
--    statement. It also closes the "money collected but the sale rolled back" hole.
-- 2) audit_log — one row per sensitive action (block / unblock / delete / role
--    change, refunds). Before this, the only trace was a console line that dies with
--    the log rotation.
--
-- The backend also creates both at boot (idempotent), so running this by hand is
-- only needed to have the schema in place before a deploy.
CREATE TABLE IF NOT EXISTS refunds (
  id BIGSERIAL PRIMARY KEY,
  company_id INTEGER NOT NULL,
  order_id TEXT,
  amount NUMERIC(12,2) NOT NULL,
  reason TEXT NOT NULL,
  reference TEXT DEFAULT '',
  method TEXT DEFAULT 'card',
  performed_by INTEGER,
  performed_by_name TEXT DEFAULT '',
  status TEXT NOT NULL DEFAULT 'approved',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS refunds_company_created_idx
  ON refunds (company_id, created_at DESC);

CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  company_id INTEGER,
  actor_id INTEGER,
  actor_name TEXT DEFAULT '',
  action TEXT NOT NULL,
  target TEXT DEFAULT '',
  detail TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS audit_log_company_created_idx
  ON audit_log (company_id, created_at DESC);

-- A refund row names who took money back and why; an audit row names who blocked,
-- deleted or changed a role. Neither may be readable with the anon key shipped in
-- the app. RLS with zero policies means no anon/authenticated access at all; the
-- backend connects as the table owner (postgres) and bypasses RLS, so nothing in
-- the app breaks. The backend also does this at boot.
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON refunds FROM anon, authenticated;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON audit_log FROM anon, authenticated;

-- What did this manager do today?
--   SELECT created_at, action, target, detail
--     FROM audit_log WHERE actor_id = 7 AND created_at > NOW() - INTERVAL '1 day'
--    ORDER BY created_at DESC;
-- What was refunded this month?
--   SELECT created_at, order_id, amount, reason, reference, performed_by_name
--     FROM refunds WHERE company_id = 42 AND created_at > NOW() - INTERVAL '1 month'
--    ORDER BY created_at DESC;
