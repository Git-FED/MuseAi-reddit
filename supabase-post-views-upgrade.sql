-- MuseAi post view-count upgrade
-- Run after supabase-setup.sql. Safe to re-run.

alter table public.museai_posts
  add column if not exists view_count integer not null default 0;

alter table public.museai_posts
  drop constraint if exists museai_posts_view_count_nonnegative;
alter table public.museai_posts
  add constraint museai_posts_view_count_nonnegative check (view_count >= 0);

create or replace function public.increment_museai_post_view(p_post_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_view_count integer;
begin
  update public.museai_posts
  set view_count = view_count + 1
  where id = p_post_id
  returning view_count into v_view_count;
  if v_view_count is null then raise exception 'Post not found'; end if;
  return v_view_count;
end;
$$;

revoke all on function public.increment_museai_post_view(uuid) from public, anon, authenticated;
grant execute on function public.increment_museai_post_view(uuid) to anon, authenticated;
