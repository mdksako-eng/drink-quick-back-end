-- ============================================================
-- RLS: customers + customer_credit_transactions (customer numbers / tabs)
-- ============================================================
-- WHY: both tables are created by the backend. They hold money-related data
-- (who owes what, and who took the payment), so the anon key shipped inside the
-- app must never be able to read or forge them.
--
-- The app only touches them through the session-authenticated backend
-- (/api/data/customers …), and the backend connects as the table owner
-- (postgres), which BYPASSES RLS — so enabling RLS with no policies changes
-- nothing for the app while closing the anon hole.
--
-- APPLY:
--   Option A (fastest): Supabase Dashboard -> SQL Editor -> paste -> Run.
--   Option B (CI/ops):  psql "$DATABASE_URL" -f sql/rls_customers.sql
-- ============================================================

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_credit_transactions ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policy: a permissive policy would re-open access.
DO $$
DECLARE
  pol record;
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['customers', 'customer_credit_transactions'] LOOP
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
REVOKE ALL ON public.customers FROM anon, authenticated;
REVOKE ALL ON public.customer_credit_transactions FROM anon, authenticated;

-- ------------------------------------------------------------
-- VERIFY (run after applying)
-- ------------------------------------------------------------
-- SELECT relname, relrowsecurity FROM pg_class
--   WHERE relname IN ('customers', 'customer_credit_transactions');
--   -> both must be true
-- SELECT policyname, tablename FROM pg_policies
--   WHERE tablename IN ('customers', 'customer_credit_transactions');
--   -> must return no rows
-- With the anon key (must return [] or a permission error):
--   GET {SUPABASE_URL}/rest/v1/customers?select=id
-- ------------------------------------------------------------