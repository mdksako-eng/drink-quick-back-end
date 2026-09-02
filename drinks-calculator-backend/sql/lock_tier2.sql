-- ============================================================
-- TIER-2 LOCKDOWN: business data tables
-- ============================================================
-- The Flutter app now reads/writes ALL business data through the
-- session-authenticated backend (/api/data/*). The anon key no longer
-- needs any access to these tables.
--
-- Effect:
--   * RLS enabled with NO policies => anon/authenticated keys get 0 rows
--     for every operation (SELECT/INSERT/UPDATE/DELETE all blocked).
--   * The backend connects as `postgres` (table owner / superuser) and
--     BYPASSES RLS, so the app keeps working through /api/data/*.
--
-- Known behavior change: Supabase Realtime subscriptions made with the
-- anon key will no longer receive events for these tables (the events
-- are RLS-filtered). The app's listeners trigger refetches; without
-- events users may need to refresh to see other devices' changes.
--
-- Rollback: see sql/revert_tier2.js or re-grant/re-create policies.
-- ============================================================

ALTER TABLE public.companies              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drinks                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_transactions   ENABLE ROW LEVEL SECURITY;
-- 🔐 Join-approval table (owner verification codes) — backend-only
ALTER TABLE public.company_join_requests  ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policies (they would re-open access if re-enabled).
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('companies','drinks','orders','inventory',
                        'inventory_transactions','settings','payment_transactions',
                        'company_join_requests')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                   pol.policyname, pol.schemaname, pol.tablename);
    RAISE NOTICE 'Dropped policy % on %', pol.policyname, pol.tablename;
  END LOOP;
END $$;

-- Belt & braces: revoke direct privileges from the client roles as well.
REVOKE ALL ON public.companies, public.drinks, public.orders,
  public.inventory, public.inventory_transactions, public.settings,
  public.payment_transactions, public.company_join_requests
  FROM anon, authenticated;

-- ============================================================
-- VERIFICATION (run after applying):
--   SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public'
--     AND tablename IN ('companies','drinks','orders','inventory',
--       'inventory_transactions','settings','payment_transactions');
--   -- every row should show rowsecurity = true
--
-- And probe with the anon key:
--   GET {SUPABASE_URL}/rest/v1/companies?select=id   -> []
--   GET {SUPABASE_URL}/rest/v1/drinks?select=id      -> []
-- ============================================================
