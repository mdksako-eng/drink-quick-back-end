-- ============================================================
-- RLS: shifts (cash-up / Z-report)
-- ============================================================
-- WHY: a shift holds the till's float, the counted cash and the variance — the
-- exact numbers an owner uses to see whether money went missing. The anon key
-- shipped inside the app must never be able to read or edit them.
--
-- The app only touches shifts through the session-authenticated backend
-- (/api/data/shifts …), and the backend connects as the table owner (postgres),
-- which BYPASSES RLS — so enabling RLS with no policies changes nothing for the
-- app while closing the anon hole.
--
-- APPLY:
--   Option A (fastest): Supabase Dashboard -> SQL Editor -> paste -> Run.
--   Option B (CI/ops):  psql "$DATABASE_URL" -f sql/rls_shifts.sql
-- ============================================================

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policy: a permissive policy would re-open access.
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'shifts'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.shifts', pol.policyname);
    RAISE NOTICE 'Dropped policy % on shifts', pol.policyname;
  END LOOP;
END $$;

-- Belt and braces: revoke direct privileges from the client roles as well.
REVOKE ALL ON public.shifts FROM anon, authenticated;

-- ------------------------------------------------------------
-- VERIFY (run after applying)
-- ------------------------------------------------------------
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'shifts';  -> must be true
-- SELECT policyname FROM pg_policies WHERE tablename = 'shifts'; -> no rows
-- With the anon key (must return [] or a permission error):
--   GET {SUPABASE_URL}/rest/v1/shifts?select=id
-- ------------------------------------------------------------