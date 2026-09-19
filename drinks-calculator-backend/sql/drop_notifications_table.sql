-- ============================================================
-- OPTIONAL CLEANUP: drop the notifications table
-- ============================================================
-- Notifications are DEVICE-ONLY now. The app keeps its notification history in
-- SharedPreferences on the device and no longer calls any backend endpoint for
-- them, so this table is dead weight (and it used to hold per-user alert data
-- in the cloud).
--
-- Run this ONLY if you do not want to keep the old rows for reference.
-- The app keeps working either way - it never reads or writes this table.
--
-- APPLY: Supabase Dashboard -> SQL Editor -> paste -> Run
-- ============================================================

DROP TABLE IF EXISTS public.notifications;

-- ------------------------------------------------------------
-- VERIFY (after applying)
-- ------------------------------------------------------------
-- SELECT to_regclass('public.notifications');
--   -> must return NULL
-- With the anon key (must return an error or []):
--   GET {SUPABASE_URL}/rest/v1/notifications?select=id
-- ------------------------------------------------------------
