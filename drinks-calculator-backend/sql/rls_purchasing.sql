-- ============================================================
-- RLS: suppliers + purchase_orders + purchase_order_lines (buying stock)
-- ============================================================
-- WHY: all three tables are created by the backend. They record what the shop
-- pays its suppliers and at what price — commercially sensitive, and the anon key
-- shipped inside the app must never be able to read or forge them.
--
-- The app only touches them through the session-authenticated backend
-- (/api/data/suppliers, /api/data/purchase-orders …), and the backend connects as
-- the table owner (postgres), which BYPASSES RLS — so enabling RLS with no
-- policies changes nothing for the app while closing the anon hole.
--
-- APPLY:
--   Option A (fastest): Supabase Dashboard -> SQL Editor -> paste -> Run.
--   Option B (CI/ops):  psql "$DATABASE_URL" -f sql/rls_purchasing.sql
-- ============================================================

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_lines ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policy: a permissive policy would re-open access.
DO $$
DECLARE
  pol record;
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['suppliers', 'purchase_orders', 'purchase_order_lines'] LOOP
    FOR pol IN
      SELECT policyname FROM pg_policies
      WHERE schemaname = 'public' AND tablename = tbl
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, tbl);
      RAISE NOTICE 'Dropped policy % on %', pol.policyname, tbl;
    END LOOP;
  END LOOP;
END $$;

-- Belt and braces: revoke direct privileges from the client roles as well.
REVOKE ALL ON public.suppliers FROM anon, authenticated;
REVOKE ALL ON public.purchase_orders FROM anon, authenticated;
REVOKE ALL ON public.purchase_order_lines FROM anon, authenticated;

-- ------------------------------------------------------------
-- VERIFY (run after applying)
-- ------------------------------------------------------------
-- SELECT relname, relrowsecurity FROM pg_class
--   WHERE relname IN ('suppliers', 'purchase_orders', 'purchase_order_lines');
--   -> all three must be true
-- SELECT policyname, tablename FROM pg_policies
--   WHERE tablename IN ('suppliers', 'purchase_orders', 'purchase_order_lines');
--   -> must return no rows
-- With the anon key (must return [] or a permission error):
--   GET {SUPABASE_URL}/rest/v1/purchase_orders?select=id
-- ------------------------------------------------------------
