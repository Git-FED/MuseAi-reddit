-- MuseAi community count definitions upgrade
-- Run after supabase-setup.sql (and supabase-media-upgrade.sql if used).
-- Members = people who explicitly joined or signed up.
-- Online = distinct visitors active within the last hour.
-- Subscribers = distinct authors with at least one published post.

create or replace function public.get_museai_community_counts()
returns table (online_count bigint, member_count bigint, subscriber_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (
      select count(distinct coalesce('user:' || presence.user_id::text,
                                     'visitor:' || presence.visitor_id::text))
      from public.museai_visitor_presence as presence
      where presence.last_active_at >= now() - interval '1 hour'
    ) as online_count,
    (
      select count(*)
      from public.museai_member_actions as action
    ) as member_count,
    (
      select count(distinct post.author_id)
      from public.museai_posts as post
    ) as subscriber_count;
$$;

revoke all on function public.get_museai_community_counts() from public, anon, authenticated;
grant execute on function public.get_museai_community_counts() to anon, authenticated;
