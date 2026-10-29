-- sql/drop_notchpay_columns.sql
--
-- WHY
--   Notch Pay was removed from the code on 2026-10-28: utils/notchpay.js and
--   utils/paymentChannels.js are deleted, so are the /subscriptions/notchpay-*
--   routes and /payment/notchpay-webhook + /payment/notchpay-return, and no query
--   reads or writes these columns any more (GET/PATCH /payment/company-settings
--   dropped notchpay_sync_id, and server.js no longer creates them at boot).
--   A retired provider's columns are dead weight, so they go.
--
--   Measured on 2026-10-28 (6 companies): notchpay_private_key 0,
--   notchpay_public_key 0, notchpay_webhook_hash 0, notchpay_sync_id 1 — that one
--   value belonged to the rail CamerPay replaced, and nothing reads it now.
--
-- ✅ SAFE TO RUN NOW: the app never sends notchpaySyncId and the backend never
--   selects or updates any notchpay_* column. (The MTN/Orange credential columns
--   are a separate, still-blocked script: sql/drop_dead_payment_columns.sql.)
--
-- KEPT (do not drop): card_enabled and the three payment toggles,
--   business_payments_enabled, and the CamerPay columns campay_enabled,
--   campay_connected_at, campay_token_enc, campay_webhook_secret_enc,
--   campay_webhook_token.
--
-- Run in the Supabase SQL editor. Idempotent.

begin;

alter table public.companies
  drop column if exists notchpay_private_key,
  drop column if exists notchpay_public_key,
  drop column if exists notchpay_sync_id,
  drop column if exists notchpay_webhook_hash;

commit;

-- Verify: expect 0 rows.
--   select column_name from information_schema.columns
--    where table_name = 'companies' and column_name like 'notchpay_%';
