-- ============================================================
-- 🧑‍💼 ORDERS — staff attribution for the manager dashboard
-- ============================================================
-- HOW TO APPLY (only needed if the backend hasn't run it for you):
--   1. Open the Supabase Dashboard → your project
--   2. SQL Editor → paste this file → Run
--   3. Verify with the CHECK query at the bottom
--
-- WHY:
--   The manager dashboard's "Sales by Staff" card groups order revenue by
--   the staff member who took the order (Order.staffName). The app sends
--   `staff_name` with every order, but the column must exist in the
--   `orders` table for it to be stored. The Node backend also runs this
--   migration at boot (idempotent), so running it manually is optional.
-- ============================================================

-- 1. Column the app writes to (nullable — older orders have no value).
ALTER TABLE orders ADD COLUMN IF NOT EXISTS staff_name VARCHAR(100);

-- 2. Backfill historical orders from the user who created them, so the
--    dashboard shows a breakdown for sales taken before the column existed.
UPDATE orders o
SET staff_name = u.username
FROM users u
WHERE o.created_by = u.id
  AND (o.staff_name IS NULL OR o.staff_name = '');

-- ------------------------------------------------------------
-- VERIFY (should list every order with a staff name once backfilled)
-- ------------------------------------------------------------
SELECT staff_name, COUNT(*) AS orders, SUM(total_amount) AS revenue
FROM orders
GROUP BY staff_name
ORDER BY revenue DESC;
