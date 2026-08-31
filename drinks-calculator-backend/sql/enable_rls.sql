-- ============================================================
-- 🔒 DRINK QUICK — SUPABASE ROW LEVEL SECURITY (RLS)
-- ============================================================
-- HOW TO APPLY:
--   1. Open the Supabase Dashboard → your project
--   2. SQL Editor → paste this file → Run
--   3. Verify with the CHECK queries at the bottom
--
-- WHAT THIS DOES (Tier 1 — SAFE, no app changes needed):
--   Enables RLS on the tables the Flutter app NEVER touches directly
--   with the anon key (all user/session/approval data flows through
--   the Node backend, which uses the postgres connection and is not
--   affected by RLS). After running this:
--     • The anon key can NO LONGER read users, sessions, login
--       requests, or approval logs.
--     • Nobody can read plaintext passwords (or anything else) from
--       those tables using the public key in the app.
--
-- Do NOT run Tier 2 until you read the notes — the app currently
-- reads/writes drinks, orders & inventory directly with the anon key,
-- so fully locking those tables would break the app.
-- ============================================================

-- ------------------------------------------------------------
-- TIER 1 — LOCK DOWN SENSITIVE / BACKEND-ONLY TABLES
-- ------------------------------------------------------------

ALTER TABLE users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE login_requests     ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_logs      ENABLE ROW LEVEL SECURITY;

-- We found pre-existing policies granting the PUBLIC role
-- (i.e. the anon key used by the app) full access to these tables.
-- We must DROP them, otherwise RLS alone changes nothing.
DROP POLICY IF EXISTS "Users can view all users"         ON public.users;
DROP POLICY IF EXISTS "Users can update own profile"     ON public.users;
DROP POLICY IF EXISTS "Users can view sessions"          ON public.user_sessions;
DROP POLICY IF EXISTS "Users can insert sessions"        ON public.user_sessions;
DROP POLICY IF EXISTS "Users can update sessions"        ON public.user_sessions;
DROP POLICY IF EXISTS "Users can delete sessions"        ON public.user_sessions;
DROP POLICY IF EXISTS "Users can view requests"          ON public.login_requests;
DROP POLICY IF EXISTS "Users can create requests"        ON public.login_requests;
DROP POLICY IF EXISTS "Users can update requests"        ON public.login_requests;
DROP POLICY IF EXISTS "Users can view approval logs"     ON public.approval_logs;
DROP POLICY IF EXISTS "Users can insert approval logs"   ON public.approval_logs;

-- With RLS enabled and zero policies, the supabase anon key (shipped
-- inside the app) can no longer SELECT/INSERT/UPDATE/DELETE these
-- tables at all. The Node backend (postgres connection role) is
-- unaffected.

-- ------------------------------------------------------------
-- VERIFY TIER 1  (should ALL return t = true)
-- ------------------------------------------------------------
SELECT relname AS table_name, relrowsecurity AS rls_enabled
FROM pg_class
WHERE relname IN ('users','user_sessions','login_requests','approval_logs')
ORDER BY relname;

-- With RLS on and zero anon policies, this now returns:
--   []
-- (same command earlier returned 12 user rows!)
SELECT id, username, email, password FROM users LIMIT 5;

-- ------------------------------------------------------------
-- ROLLBACK (if you ever need to undo Tier 1)
-- ------------------------------------------------------------
-- ALTER TABLE users          DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE user_sessions  DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE login_requests DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE approval_logs  DISABLE ROW LEVEL SECURITY;

-- ============================================================
-- TIER 2 — REVIEW CAREFULLY BEFORE RUNNING
-- ============================================================
-- The Flutter app currently performs direct anon-key CRUD on:
--   drinks, orders, inventory, settings, inventory_transactions
-- and reads companies via getCompany() (lib/services/supabase_service.dart).
--
-- If you enable RLS on those tables you MUST add policies that
-- reproduce exactly what the app does today, otherwise the app stops
-- working. This is the long-term architecture fix:
--
-- 1) Route ALL reads/writes through the Node backend (service role /
--    postgres connection) and revoke anon access entirely, OR
-- 2) Move the app to Supabase Auth + use auth.uid() role policies.
--
-- Neither option is a drop-in change — plan it as a separate task.
--
-- ⚠️  companies table: it stores payment secrets (mtn_api_key,
--    orange_secret_key, ...). getCompany() reads it with `select=*`,
--    so those secrets are ALSO exposed to anyone with the anon key.
--    Fix: stop returning secret columns in getCompany() / move that
--    call to the backend, then enable RLS here with an anon policy
--    that only exposes non-sensitive columns.
-- ============================================================