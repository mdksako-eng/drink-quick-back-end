-- ============================================================
-- RLS: container_types + container_transactions (returnable containers)
-- ============================================================
-- WHY: both tables are created by the backend. They record who is holding the
-- shop's crates and bottles — goods that belong to the shop, standing in
-- somebody else's yard — so the anon key shipped inside the app must never be
-- able to read or forge them.
--
-- The app only touches them through the session-authenticated backend
-- (/api/data/containers …), and the backend connects as the table owner
-- (postgres), which BYPASSES RLS — so enabling RLS with no policies changes
-- nothing for the app while closing the anon hole.
--
-- APPLY:
--   Option A (fastest): Supabase Dashboard -> SQL Editor -> paste -> Run.
--   Option B (CI/ops):  psql "$DATABASE_URL" -f sql/rls_containers.sql
-- ============================================================

ALTER TABLE public.container_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.container_transactions ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policy: a permissive policy would re-open access.
DO $$
DECLARE
  pol record;
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['container_types', 'container_transactions'] LOOP
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
REVOKE ALL ON public.container_types FROM anon, authenticated;
REVOKE ALL ON public.container_transactions FROM anon, authenticated;

-- ------------------------------------------------------------
-- VERIFY (run after applying)
-- ------------------------------------------------------------
-- SELECT relname, relrowsecurity FROM pg_class
--   WHERE relname IN ('container_types', 'container_transactions');
--   -> both must be true
-- SELECT policyname, tablename FROM pg_policies
--   WHERE tablename IN ('container_types', 'container_transactions');
--   -> must return no rows
-- With the anon key (must return [] or a permission error):
--   GET {SUPABASE_URL}/rest/v1/container_transactions?select=id
-- ------------------------------------------------------------
