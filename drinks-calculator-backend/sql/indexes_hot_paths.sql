-- sql/indexes_hot_paths.sql
-- Indexes for the queries every screen runs.
--
-- WHY: reports and history filter by company and sort by date. Without an index
-- each one scans and sorts the whole table, and because a report holds a pool
-- connection for its duration, a few managers opening the dashboard at once can
-- starve the tills (pool max is 10). These are the four hot paths.
--
-- The backend also runs these at boot (idempotent, failures logged not fatal), so
-- running this by hand is only needed to put them in place before a deploy.
CREATE INDEX IF NOT EXISTS idx_orders_company_date
  ON orders (company_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_payment_tx_company_created
  ON payment_transactions (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_tx_company_date
  ON inventory_transactions (company_id, date DESC);

-- GET /drinks filters exactly on this pair.
CREATE INDEX IF NOT EXISTS idx_drinks_company_active
  ON drinks (company_id, is_active);
