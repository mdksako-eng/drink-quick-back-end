-- ============================================================
-- RLS: support_reports (bug reports / complaints filed from the app)
-- ============================================================
-- WHY: a report carries the reporter's username, their company, their own words and a
-- device/app context line — enough to identify a customer and their problems. The anon
-- key shipped inside the app must never be able to read or edit any of it.
--
-- Reports are only ever written through the session-authenticated backend
-- (POST /api/support/reports) and read by an admin through /api/admin/support-reports.
-- The backend connects as the table owner (postgres), which BYPASSES RLS — so enabling
-- RLS with no policies changes nothing for the app while closing the anon hole.
--
-- The server also enables this at boot (idempotent), so a fresh environment is covered
-- without this file; run it by hand to lock down an existing database immediately.
--
-- APPLY:
--   Option A (fastest): Supabase Dashboard -> SQL Editor -> paste -> Run.
--   Option B (CI/ops):  psql "$DATABASE_URL" -f sql/rls_support_reports.sql
-- ============================================================

ALTER TABLE public.support_reports ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policy: a permissive policy would re-open access.
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'support_reports'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.support_reports', pol.policyname);
    RAISE NOTICE 'Dropped policy % on support_reports', pol.policyname;
  END LOOP;
END $$;

-- Belt and braces: revoke direct privileges from the client roles as well.
REVOKE ALL ON public.support_reports FROM anon, authenticated;

-- ------------------------------------------------------------
-- VERIFY (run after applying)
-- ------------------------------------------------------------
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'support_reports';  -> must be true
-- SELECT policyname FROM pg_policies WHERE tablename = 'support_reports'; -> no rows
-- With the anon key (must return [] or a permission error):
--   GET {SUPABASE_URL}/rest/v1/support_reports?select=reference
-- ------------------------------------------------------------
