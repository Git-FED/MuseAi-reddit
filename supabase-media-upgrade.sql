-- MuseAi media upgrade
-- Run once in the Supabase SQL Editor after supabase-setup.sql.
-- Adds post attachments and the public media bucket used by the composer.
-- Safe to re-run.

-- 1. Store attachment metadata on each post.
alter table public.museai_posts
  add column if not exists attachments jsonb not null default '[]'::jsonb;

-- Guard the shape and count without breaking older rows.
alter table public.museai_posts
  drop constraint if exists museai_posts_attachments_shape;
alter table public.museai_posts
  add constraint museai_posts_attachments_shape
  check (jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 10);

-- 2. Public bucket for post images and files.
-- Images are compressed in the browser before upload; files keep their format.
insert into storage.buckets (id, name, public, file_size_limit)
values ('museai-media', 'museai-media', true, 26214400)
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit;

-- 3. Storage policies.
-- Anyone can read media referenced by a public post.
drop policy if exists "museai_media_public_read" on storage.objects;
create policy "museai_media_public_read"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'museai-media');

-- Signed-in members can upload only inside their own user-id folder.
drop policy if exists "museai_media_insert_own" on storage.objects;
create policy "museai_media_insert_own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'museai-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Authors can replace or delete their own uploads (used when publishing fails).
drop policy if exists "museai_media_update_own" on storage.objects;
create policy "museai_media_update_own"
  on storage.objects for update to authenticated
  using (bucket_id = 'museai-media' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'museai-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "museai_media_delete_own" on storage.objects;
create policy "museai_media_delete_own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'museai-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- 4. Refresh PostgREST's schema cache so the attachments column is visible.
notify pgrst, 'reload schema';
