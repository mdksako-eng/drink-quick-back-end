-- ============================================================
-- RLS: password_reset_requests (reset emails asked for, and wrong codes tried)
-- ============================================================
-- WHY: every row is "this address asked for a password reset at this time, from
-- this IP". Readable, that is a list of which of your users forgot their password
-- — and a list of addresses that are real, which is the first thing an attacker
-- wants. The anon key shipped inside the app must never be able to read it.
--
-- Rows are only ever written and read by the session-less backend
-- (POST /api/auth/send-reset-code and /api/auth/verify-reset-code). The backend
-- connects as the table owner (postgres), which BYPASSES RLS — so enabling RLS with
-- no policies changes nothing for the app while closing the anon hole.
--
-- The server also creates the table and enables this at boot (idempotent), so a
-- fresh environment is covered without this file; run it by hand to lock down an
-- existing database immediately.
--
-- APPLY:
--   Option A (fastest): Supabase Dashboard -> SQL Editor -> paste -> Run.
--   Option B (CI/ops):  psql "$DATABASE_URL" -f sql/rls_password_reset_requests.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS public.password_reset_requests (
  id SERIAL PRIMARY KEY,
  email TEXT NOT NULL,
  kind VARCHAR(20) NOT NULL DEFAULT 'request',
  ip VARCHAR(60),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_password_reset_email
  ON public.password_reset_requests(email, kind, created_at);

ALTER TABLE public.password_reset_requests ENABLE ROW LEVEL SECURITY;

-- Drop any pre-existing policy: a permissive policy would re-open access.
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'password_reset_requests'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.password_reset_requests', pol.policyname);
    RAISE NOTICE 'Dropped policy % on password_reset_requests', pol.policyname;
  END LOOP;
END $$;

-- Belt and braces: revoke direct privileges from the client roles as well.
REVOKE ALL ON public.password_reset_requests FROM anon, authenticated;

-- ------------------------------------------------------------
-- VERIFY (run after applying)
-- ------------------------------------------------------------
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'password_reset_requests'; -> must be true
-- SELECT policyname FROM pg_policies WHERE tablename = 'password_reset_requests'; -> no rows
-- With the anon key (must return [] or a permission error):
--   GET {SUPABASE_URL}/rest/v1/password_reset_requests?select=email
-- ------------------------------------------------------------
