-- sql/drop_dead_payment_columns.sql
--
-- WHY
--   Payment settings used to be configured per provider (MTN, Orange, then Notch
--   Pay). CamerPay is the only rail now: the app no longer shows those fields, so
--   the columns that held them are dead weight — and the plaintext *_api_key /
--   *_secret_key pairs are a liability sitting in the database.
--
--   Measured on 2026-10-28 (6 companies):
--     mtn_api_key / mtn_api_key_encrypted        6 / 6 non-null
--     mtn_secret_key / mtn_merchant_id           6 / 6
--     orange_api_key / orange_secret_key         6 / 6
--     campay_token_enc / campay_webhook_token    0 / 0   (kept — see below)
--   So the MTN/Orange values are real rows, not empty strings: they are dropped
--   on purpose. The feature they belonged to no longer exists.
--
--   The notchpay_* columns used to live here too. They moved to
--   sql/drop_notchpay_columns.sql, which is ready to run today.
--
-- ✅ READY — but run it only AFTER this code is deployed.
--   The backend must stop reading these columns first: until the deploy lands,
--   `GET /payment/company-settings` still SELECTs them and the drop would make it
--   fail. Once the new build is live (verify `GET /health` reports the new
--   RELEASE), the columns are unreferenced and this script is safe.
--
--   Step 1 is done in code: the app no longer sends any of these keys
--   (lib/screens/storage_settings_screen.dart, lib/utils/payment_helper.dart),
--   `PATCH /payment/company-settings` accepts only the four switches, and every
--   backend read is gone (payment.routes.js, data.routes.js, server.js). The old
--   `/company/payment-credentials` endpoint is deleted with them.
--   Locked by tests/payment_credentials_removed.test.js: it fails if one of these
--   column names reappears anywhere in the backend code.
--
-- KEPT (do not drop): mtn_enabled, orange_enabled, card_enabled,
--   business_payments_enabled (the three toggles + the master switch), and the
--   CamerPay columns campay_enabled, campay_connected_at, campay_token_enc,
--   campay_webhook_secret_enc, campay_webhook_token.
--
-- Run in the Supabase SQL editor. Idempotent.

begin;

-- MTN credentials (the toggle mtn_enabled stays)
alter table public.companies
  drop column if exists mtn_api_key,
  drop column if exists mtn_api_key_encrypted,
  drop column if exists mtn_secret_key,
  drop column if exists mtn_secret_key_encrypted,
  drop column if exists mtn_merchant_id,
  drop column if exists mtn_merchant_phone,
  drop column if exists mtn_sandbox_mode;

-- Orange credentials (the toggle orange_enabled stays)
alter table public.companies
  drop column if exists orange_api_key,
  drop column if exists orange_api_key_encrypted,
  drop column if exists orange_secret_key,
  drop column if exists orange_secret_key_encrypted,
  drop column if exists orange_merchant_id,
  drop column if exists orange_merchant_phone,
  drop column if exists orange_sandbox_mode;

commit;

-- Verify: expect 0 rows.
--   select column_name from information_schema.columns
--    where table_name = 'companies'
--      and (column_name like 'mtn_%' and column_name not in ('mtn_enabled')
--        or column_name like 'orange_%' and column_name not in ('orange_enabled'));
