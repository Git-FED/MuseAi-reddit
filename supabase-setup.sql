-- MuseAi community profile/post setup
-- Run or re-run this idempotent script in Supabase SQL Editor for the page's project.
-- The existing public.profiles table is retained; profile rows remain owned by auth.uid().

-- Allow signed-in members to create/update only their own profile record.
alter table public.profiles enable row level security;
drop policy if exists "museai_profiles_insert_own" on public.profiles;
create policy "museai_profiles_insert_own"
  on public.profiles for insert to authenticated
  with check (auth.uid() = id);
drop policy if exists "museai_profiles_update_own" on public.profiles;
create policy "museai_profiles_update_own"
  on public.profiles for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

grant select on public.profiles to anon, authenticated;
grant insert, update on public.profiles to authenticated;

-- Durable feed posts, linked to the signed-in author.
create table if not exists public.museai_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 240),
  body text not null default '',
  flair text not null default 'discussion',
  thumb text not null default '✨',
  thumb_bg text not null default '#ede9fe',
  score integer not null default 1,
  comments integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.museai_posts
  add column if not exists view_count integer not null default 0;
alter table public.museai_posts
  drop constraint if exists museai_posts_view_count_nonnegative;
alter table public.museai_posts
  add constraint museai_posts_view_count_nonnegative check (view_count >= 0);

create index if not exists museai_posts_created_at_idx
  on public.museai_posts (created_at desc);
create index if not exists museai_posts_author_created_idx
  on public.museai_posts (author_id, created_at desc);

alter table public.museai_posts enable row level security;
drop policy if exists "museai_posts_public_read" on public.museai_posts;
create policy "museai_posts_public_read"
  on public.museai_posts for select to anon, authenticated
  using (true);
drop policy if exists "museai_posts_insert_own" on public.museai_posts;
create policy "museai_posts_insert_own"
  on public.museai_posts for insert to authenticated
  with check (auth.uid() = author_id);
drop policy if exists "museai_posts_update_own" on public.museai_posts;
create policy "museai_posts_update_own"
  on public.museai_posts for update to authenticated
  using (auth.uid() = author_id)
  with check (auth.uid() = author_id);
drop policy if exists "museai_posts_delete_own" on public.museai_posts;
create policy "museai_posts_delete_own"
  on public.museai_posts for delete to authenticated
  using (auth.uid() = author_id);

grant select on public.museai_posts to anon, authenticated;
grant insert, update, delete on public.museai_posts to authenticated;

-- A post view is recorded only when the frontend explicitly opens a post.
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

-- Activity-derived counts. The page stores a random browser ID, not personal details.
-- Members are explicit Join or Sign Up actions.
-- Subscribers are distinct people who have published at least one post.
create table if not exists public.museai_visitor_presence (
  visitor_id uuid primary key,
  last_active_at timestamptz not null default now(),
  user_id uuid
);

create index if not exists museai_visitor_presence_last_active_idx
  on public.museai_visitor_presence (last_active_at desc);

create table if not exists public.museai_member_actions (
  actor_key text primary key,
  visitor_id uuid not null,
  user_id uuid,
  first_action_at timestamptz not null default now()
);

create unique index if not exists museai_member_actions_user_id_idx
  on public.museai_member_actions (user_id)
  where user_id is not null;
create index if not exists museai_member_actions_visitor_id_idx
  on public.museai_member_actions (visitor_id);

alter table public.museai_visitor_presence enable row level security;
alter table public.museai_member_actions enable row level security;
revoke all on table public.museai_visitor_presence, public.museai_member_actions
  from public, anon, authenticated;

-- Called for real page interactions and explicit membership actions. The tables
-- stay private; browsers can write only through this validated RPC.
create or replace function public.record_museai_activity(
  p_visitor_id uuid,
  p_member_action boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if p_visitor_id is null then
    raise exception 'visitor ID is required';
  end if;

  insert into public.museai_visitor_presence as presence (visitor_id, last_active_at, user_id)
  values (p_visitor_id, now(), v_user_id)
  on conflict (visitor_id) do update
    set last_active_at = now(),
        user_id = coalesce(excluded.user_id, presence.user_id);

  if coalesce(p_member_action, false) then
    if v_user_id is null then
      insert into public.museai_member_actions (actor_key, visitor_id, user_id)
      values ('visitor:' || p_visitor_id::text, p_visitor_id, null)
      on conflict (actor_key) do nothing;
    else
      -- Merge this browser's earlier anonymous action into the signed-in identity.
      delete from public.museai_member_actions
      where visitor_id = p_visitor_id and user_id is null;

      insert into public.museai_member_actions as member_action (actor_key, visitor_id, user_id)
      values ('user:' || v_user_id::text, p_visitor_id, v_user_id)
      on conflict (actor_key) do update
        set visitor_id = excluded.visitor_id;
    end if;
  end if;

  -- Keep the rolling-presence table bounded; old rows cannot affect the one-hour count.
  delete from public.museai_visitor_presence
  where last_active_at < now() - interval '90 days';
end;
$$;

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

revoke all on function public.record_museai_activity(uuid, boolean) from public, anon, authenticated;
revoke all on function public.get_museai_community_counts() from public, anon, authenticated;
grant execute on function public.record_museai_activity(uuid, boolean) to anon, authenticated;
grant execute on function public.get_museai_community_counts() to anon, authenticated;

-- Durable post votes. Identity is a signed-in user when available, otherwise
-- the page's persistent random browser ID; raw actor IDs are never readable.
create table if not exists public.museai_post_votes (
  post_id uuid not null references public.museai_posts(id) on delete cascade,
  actor_key text not null,
  visitor_id uuid not null,
  user_id uuid,
  vote smallint not null check (vote in (-1, 1)),
  updated_at timestamptz not null default now(),
  primary key (post_id, actor_key)
);

create unique index if not exists museai_post_votes_post_user_idx
  on public.museai_post_votes (post_id, user_id)
  where user_id is not null;
create index if not exists museai_post_votes_post_idx
  on public.museai_post_votes (post_id);

alter table public.museai_post_votes enable row level security;
revoke all on table public.museai_post_votes from public, anon, authenticated;

-- Comments are public to read, but can be created only through the validated RPC.
create table if not exists public.museai_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.museai_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists museai_comments_post_created_idx
  on public.museai_comments (post_id, created_at asc);
create index if not exists museai_comments_author_created_idx
  on public.museai_comments (author_id, created_at desc);

alter table public.museai_comments enable row level security;
drop policy if exists "museai_comments_public_read" on public.museai_comments;
create policy "museai_comments_public_read"
  on public.museai_comments for select to anon, authenticated
  using (true);
revoke all on table public.museai_comments from public, anon, authenticated;
grant select (id, post_id, author_id, body, created_at)
  on public.museai_comments to anon, authenticated;

-- Replace any old/demo comment totals with the durable comment rows.
update public.museai_posts as post
set comments = (select count(*)::integer
                 from public.museai_comments as comment
                 where comment.post_id = post.id);

create or replace function public.set_museai_post_vote(
  p_visitor_id uuid,
  p_post_id uuid,
  p_vote smallint
)
returns table (current_vote smallint, score integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_actor_key text;
  v_existing smallint;
  v_score integer;
begin
  if p_visitor_id is null then raise exception 'Visitor ID is required'; end if;
  if p_vote is null or p_vote not in (-1, 1) then raise exception 'Vote must be -1 or 1'; end if;
  perform 1 from public.museai_posts where id = p_post_id for update;
  if not found then raise exception 'Post not found'; end if;

  perform public.record_museai_activity(p_visitor_id, false);
  v_actor_key := case when v_user_id is null
    then 'visitor:' || p_visitor_id::text
    else 'user:' || v_user_id::text end;

  -- When a visitor signs in, fold that browser's anonymous vote into their
  -- account identity before applying this vote.
  if v_user_id is not null then
    delete from public.museai_post_votes as old_vote
    where old_vote.post_id = p_post_id
      and old_vote.visitor_id = p_visitor_id
      and old_vote.user_id is null;
  end if;

  select existing_vote.vote into v_existing
  from public.museai_post_votes as existing_vote
  where existing_vote.post_id = p_post_id
    and existing_vote.actor_key = v_actor_key
  for update;

  if v_existing = p_vote then
    delete from public.museai_post_votes
    where post_id = p_post_id and actor_key = v_actor_key;
    v_existing := null;
  else
    insert into public.museai_post_votes as stored_vote
      (post_id, actor_key, visitor_id, user_id, vote, updated_at)
    values (p_post_id, v_actor_key, p_visitor_id, v_user_id, p_vote, now())
    on conflict (post_id, actor_key) do update
      set visitor_id = excluded.visitor_id,
          user_id = excluded.user_id,
          vote = excluded.vote,
          updated_at = now();
    v_existing := p_vote;
  end if;

  select coalesce(sum(stored_vote.vote), 0)::integer into v_score
  from public.museai_post_votes as stored_vote
  where stored_vote.post_id = p_post_id;
  update public.museai_posts set score = v_score where id = p_post_id;

  current_vote := v_existing;
  score := v_score;
  return next;
end;
$$;

create or replace function public.get_museai_viewer_votes(
  p_visitor_id uuid,
  p_post_ids uuid[]
)
returns table (post_id uuid, vote smallint)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (stored_vote.post_id)
    stored_vote.post_id, stored_vote.vote
  from public.museai_post_votes as stored_vote
  where stored_vote.post_id = any(coalesce(p_post_ids, array[]::uuid[]))
    and (stored_vote.user_id = auth.uid()
      or (stored_vote.visitor_id = p_visitor_id and stored_vote.user_id is null))
  order by stored_vote.post_id,
           (stored_vote.user_id = auth.uid()) desc nulls last;
$$;

create or replace function public.create_museai_comment(
  p_visitor_id uuid,
  p_post_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_comment_id uuid;
  v_body text := trim(coalesce(p_body, ''));
begin
  if p_visitor_id is null then raise exception 'Visitor ID is required'; end if;
  if v_user_id is null then raise exception 'Sign in to comment'; end if;
  if not exists (select 1 from public.profiles where id = v_user_id) then
    raise exception 'Create your profile before commenting';
  end if;
  if char_length(v_body) < 1 or char_length(v_body) > 1000 then
    raise exception 'Comments must be between 1 and 1000 characters';
  end if;

  insert into public.museai_comments (post_id, author_id, body)
  values (p_post_id, v_user_id, v_body)
  returning id into v_comment_id;

  update public.museai_posts as post
  set comments = coalesce(post.comments, 0) + 1
  where post.id = p_post_id;

  perform public.record_museai_activity(p_visitor_id, false);
  return v_comment_id;
end;
$$;

revoke all on function public.set_museai_post_vote(uuid, uuid, smallint) from public, anon, authenticated;
revoke all on function public.get_museai_viewer_votes(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.create_museai_comment(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.set_museai_post_vote(uuid, uuid, smallint) to anon, authenticated;
grant execute on function public.get_museai_viewer_votes(uuid, uuid[]) to anon, authenticated;
grant execute on function public.create_museai_comment(uuid, uuid, text) to authenticated;
