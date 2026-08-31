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