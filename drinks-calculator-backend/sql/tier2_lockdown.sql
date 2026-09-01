-- ============================================================
-- TIER 2 DB HARDENING
-- The app no longer touches Supabase REST directly (all data flows
-- through the session-authenticated backend), so the anon key no
-- longer needs broad table access.
--
-- 1) companies: full lockdown — payment credential columns
--    (mtn_api_key, orange_secret_key, ...) must never be readable
--    by the anon key. Backend uses the postgres role (RLS bypassed).
-- 2) Business tables: anon keeps SELECT (Supabase Realtime streams
--    inventory/order changes to the app using it) but loses all
--    write privileges.
-- Run in Supabase SQL Editor or via scripts/apply_tier2_rls.js
-- ============================================================

-- ---------- 1) COMPANIES: full lockdown ----------
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Drop every policy (anon created broad "public view" policies)
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'companies'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.companies', pol.policyname);
  END LOOP;
END $$;

REVOKE ALL ON public.companies FROM anon;
REVOKE ALL ON public.companies FROM authenticated;

-- ---------- 2) BUSINESS TABLES: revoke anon writes ----------
-- SELECT stays granted so Supabase Realtime (inventory/order change
-- streams) keeps working. All mutations now require the backend.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON
  public.drinks,
  public.orders,
  public.inventory,
  public.inventory_transactions,
  public.settings,
  public.payment_transactions
FROM anon;

-- ============================================================
-- VERIFY (run after applying):
--   SELECT relname, relrowsecurity FROM pg_class
--    WHERE relnamespace = 'public'::regnamespace
--      AND relname IN ('companies','drinks','orders');
--   -- companies must show relrowsecurity = true
--
-- Anon checks (expect empty array / permission errors):
--   GET  /rest/v1/companies?select=*        -> []
--   POST /rest/v1/orders  (with anon key)   -> permission denied
-- Backend checks (must still work):
--   GET /api/data/drinks  (with session)    -> 200 with rows
-- ============================================================
