-- ============================================================
-- RLS: forecast_events (company demand-boost events)
-- ============================================================
-- WHY: forecast_events was created by the backend WITHOUT row level
-- security, so the anon key shipped inside the app could read (and forge)
-- another company's events through Supabase's REST API.
--
-- The app only ever touches this table through the session-authenticated
-- backend (/api/data/events), and the backend connects as the table owner
-- (postgres), which BYPASSES RLS — so enabling RLS with no policies changes
-- nothing for the app while closing the anon hole.
--
-- APPLY:
--   Option A (fastest): Supabase Dashboard -> SQL Editor -> paste -> Run.
--   Option B (CI/ops):  DATABASE_URL=... node scripts/apply_forecast_rls.js
-- ============================================================

ALTER TABLE public.forecast_events ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policy: a permissive policy would re-open access.
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'forecast_events'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.forecast_events',
                   pol.policyname);
    RAISE NOTICE 'Dropped policy % on forecast_events', pol.policyname;
  END LOOP;
END $$;

-- Belt and braces: revoke direct privileges from the client roles as well.
REVOKE ALL ON public.forecast_events FROM anon, authenticated;

-- ------------------------------------------------------------
-- VERIFY (run after applying)
-- ------------------------------------------------------------
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'forecast_events';
--   -> must be true
-- SELECT policyname FROM pg_policies WHERE tablename = 'forecast_events';
--   -> must return no rows
-- With the anon key (must return [] or a permission error):
--   GET {SUPABASE_URL}/rest/v1/forecast_events?select=id
-- ------------------------------------------------------------