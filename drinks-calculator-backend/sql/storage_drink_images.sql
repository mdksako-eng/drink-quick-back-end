-- ============================================================
-- DRINK IMAGES — public Storage bucket + upload policy
-- ============================================================
-- WHAT THIS DOES
--   Creates a PUBLIC bucket called `drink-images` so drink pictures can be
--   hosted on Supabase and referenced by URL from the app (Drink Management →
--   image URL, or the in-app "Upload" button which fills that field for you).
--
--   "Public" only affects READING: a public bucket serves files through
--   /storage/v1/object/public/<bucket>/<path> without a key, which is exactly
--   what a product photo needs.
--
--   Writing is controlled by the policies below. The Flutter app talks to
--   Supabase with the anon key (it does not use Supabase Auth), so the upload
--   policy must target the `anon` role. To keep that safe the policy only
--   allows:
--     * inserts into THIS bucket,
--     * image mime types,
--     * files up to 5 MB.
--   Anyone with the shipped anon key can therefore add a picture — but cannot
--   overwrite or delete anything (no UPDATE/DELETE policy), and cannot touch
--   other buckets.
--
-- APPLY: Supabase Dashboard → SQL Editor → paste → Run
-- Rollback: see the bottom of this file.
-- ============================================================

-- 1) The bucket (idempotent).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'drink-images',
  'drink-images',
  true,
  5242880, -- 5 MB
  array['image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/gif']
)
on conflict (id) do update
  set public = true,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/gif'];

-- 2) Public read (needed by the app's Image.network and by customers).
drop policy if exists "drink images are publicly readable" on storage.objects;
create policy "drink images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'drink-images');

-- 3) Uploads from the app (anon key): images only, this bucket only.
drop policy if exists "drink images can be uploaded" on storage.objects;
create policy "drink images can be uploaded"
  on storage.objects for insert
  to anon, authenticated
  with check (
    bucket_id = 'drink-images'
    and (lower(storage.extension(name)) in ('png', 'jpg', 'jpeg', 'webp', 'gif'))
  );

-- No UPDATE / DELETE policy on purpose: an uploader cannot overwrite or remove
-- files (deleting is an owner/manager job you can add later if you want).

-- ------------------------------------------------------------
-- VERIFY
-- ------------------------------------------------------------
-- select id, public, file_size_limit, allowed_mime_types
--   from storage.buckets where id = 'drink-images';      -- public = true
-- select policyname, cmd, roles from pg_policies
--   where schemaname = 'storage' and tablename = 'objects';
-- Then open in a browser (must show the image):
--   {SUPABASE_URL}/storage/v1/object/public/drink-images/<file-name>
-- ------------------------------------------------------------
-- ROLLBACK
-- ------------------------------------------------------------
-- drop policy if exists "drink images can be uploaded" on storage.objects;
-- drop policy if exists "drink images are publicly readable" on storage.objects;
-- delete from storage.buckets where id = 'drink-images';
