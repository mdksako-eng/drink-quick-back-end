# Deploying the backend security fixes

This repo's backend (in `drinks-calculator-backend/`) now has:
- **bcrypt password hashing** (register/login/create-staff/reset)
- **login & reset rate limiting**
- **RLS lock-down SQL + one-command apply script** for the sensitive Supabase tables
- **password migration script** (legacy plaintext → bcrypt)

Only two credentials are needed to finish. Once you have the **DATABASE_URL** I can run steps 1–2 right now.

---

## Step 1 — Lock the Supabase tables (RLS)

Option A (I run it for you, ~30s):
1. Give me the `DATABASE_URL` (or add it to `drinks-calculator-backend/.env`).
2. I run: `cd drinks-calculator-backend && npm run rls:apply`

Option B (you run it in the Supabase Dashboard):
1. Supabase → your project → **SQL Editor** → paste the whole contents of `drinks-calculator-backend/sql/enable_rls.sql` → **Run**.
2. Confirm the 4 tables now have `relrowsecurity = true`.

### Step 1b — `forecast_events` (added later)

`forecast_events` was created by the backend **without** row level security, so
the anon key shipped inside the app could read (and forge) another company's
events. The backend now enables RLS on it at boot; to close it on an existing
database immediately:

Option A: `cd drinks-calculator-backend && node scripts/apply_forecast_rls.js`
Option B (Dashboard): paste `drinks-calculator-backend/sql/rls_forecast_events.sql` into the SQL Editor → **Run**.

Verify (with the anon key):
```
GET {SUPABASE_URL}/rest/v1/forecast_events?select=id   → [] or 401
```

### Step 1c — Optional: drop the notifications table

Notifications are **device-only** now: the app keeps the history in
SharedPreferences and never calls the backend for them, so the `notifications`
table is no longer used (the runtime creation of it was removed from
`server.js`). If you do not want to keep the old rows:

```
-- Supabase → SQL Editor
\i drinks-calculator-backend/sql/drop_notifications_table.sql
```
(or paste the file's contents and Run). The app works either way.


---

### Step 1d — Drink pictures (Storage bucket)

The app can upload a drink picture straight from the camera/gallery
(Drink Management → the cloud icon in the image field) and fills the URL for you.
That needs a public bucket plus a small upload policy:

```
-- Supabase → SQL Editor → paste the contents of:
drinks-calculator-backend/sql/storage_drink_images.sql   → Run
```

It creates a **public** `drink-images` bucket (5 MB limit, png/jpg/webp/gif only)
with a read policy for everyone and an insert policy for the app's anon key. There
is deliberately **no** update/delete policy, so an uploader cannot overwrite or
remove a picture. Until it is applied the app shows
*"Storage bucket 'drink-images' is missing"* when you tap upload; you can always
paste any external image URL manually instead.

The same bucket also stores the **company logo** (Settings → Company logo, owner
manager only). That logo is used in the drawer, the invoice PDF and every export.

---

### Step 1e — Are we taking REAL money yet?

Subscription payments run through Notch Pay (and optionally Flutterwave / direct
MoMo). The code supports both modes; what decides is the keys you set. Check the
live service any time:

```
cd drinks-calculator-backend
node scripts/check_payments.js                      # checks the deployed backend
node scripts/check_payments.js http://localhost:5000
```

It prints a ✅/⚠️  checklist and exits non-zero while the platform is still in
**test mode**. The app also shows a *"Test mode"* banner on the subscription
screen so nobody believes a real payment was taken.

To go live (Render → your service → **Environment**):

| Variable | Value |
|---|---|
| `NOTCHPAY_PUBLIC_KEY` | `pk_live_…` |
| `NOTCHPAY_PRIVATE_KEY` | `sk_live_…` |
| `NOTCHPAY_WEBHOOK_SECRET` | your live webhook secret |
| `FLUTTERWAVE_PUBLIC_KEY` / `FLUTTERWAVE_SECRET_KEY` | optional card rail |
| `PLATFORM_MTN_SANDBOX` | `false` (only for direct MTN MoMo credentials) |

Webhook URL to register in the Notch Pay dashboard:

```
https://<your-service>/api/subscriptions/notchpay-webhook
```

Then redeploy and re-run `node scripts/check_payments.js` — it must report
`mode: live` and `Everything ready for real money ✅`.

---

## Step 2 — Hash existing plaintext passwords

After RLS is on: `cd drinks-culator-backend && npm run migrate:passwords`

> This needs `DATABASE_URL` set (you can put it in `drinks-calculator-backend/.env`, which your `.gitignor` hides).

Reminder: anyone who captured the anon key can no longer read the hasheds anyway, but you should still **reset password for the user accounts** that were exposed (especially `mendy`, and all 3, `26`, `32`, `34`, `37`, `38`, `39`, `40`, `8`, `11`, `16`, `4`) or verify they were already changed.

---

## Step 3 — Deploy to Render

The backend you have on Render (`drink-quic-cal-kj1.onrender.com`) is still running the OLD code (plaintext, open /users). Two ways to update it:

**Option A — existing Render service (simplest, no new repo):**
1. Go to Render Dashboard → service `drink-quick-backend` (or whatever hosts drink-quick-cal-kj1).
2. Push your updated code to the repo/service Render is hooked to (or use Render's manual deploy).
   - If Render is linked to a GitHub repo: `git add -A; git commit -m "Harden auth"; git push`
   - Right now this folder is **not a git repo** — you'll need to link it to the repo that feeds Render.
3. In the service → **Environment** → set `ADMIN_PASSWORD` to a strong value.
4. Trigger a deploy (or wait for auto-deploy).

**Option B — new service from the included blueprint:**
1. Create a GitHub repo and push this folder to it (`git init`, add, commit, push).
2. Render Dashboard → **New** → **Blueprint** → connect that repo.
3. It reads `render.yaml` (already included), creates the service, and prompts for `DATABASE_URL`, `ADMIN_PASSWORD`, optional `GROQ_API_KEY`.
4. After deploy, point the Flutter app's `ApiConfig.baseUrl` (or `--dart-define`) at the new URL.

---

## After deploy — verify

curl the API:
```
curl https://your-backend.onrender.com/api/ping      # → pong
curl https://your-backend.onrender.com/api/users     # → must be 401 now, NOT 200
```
Also open the Supabase SQL Editor and run the verification queries inside `enable_rls.sql` (RCK should return `[]`).