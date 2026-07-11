create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  country text not null,
  created_at timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,20}$'),
  constraint profiles_country_format check (country ~ '^[A-Z]{2}$')
);

create table if not exists public.sends (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid references public.profiles(id) on delete set null,
  artwork jsonb not null,
  note text not null,
  target_country text not null,
  direct boolean not null default false,
  status text not null default 'queued',
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  read_at timestamptz,
  constraint sends_note_length check (char_length(note) <= 1000),
  constraint sends_target_country_format check (target_country ~ '^[A-Z]{2}$'),
  constraint sends_status_check check (status in ('queued', 'delivered', 'read'))
);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  send_id uuid not null references public.sends(id) on delete cascade,
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  reply_note text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  constraint friend_requests_reply_length check (char_length(reply_note) <= 500),
  constraint friend_requests_status_check check (status in ('pending', 'accepted', 'declined')),
  constraint friend_requests_not_self check (from_id <> to_id)
);

create table if not exists public.friendships (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  constraint friendships_order check (user_a < user_b)
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  send_id uuid not null references public.sends(id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now()
);

create or replace function public.normalize_profile_username()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.username := lower(trim(new.username));
  new.country := upper(trim(new.country));
  return new;
end;
$$;

drop trigger if exists normalize_profile_username_trigger on public.profiles;
create trigger normalize_profile_username_trigger
before insert or update on public.profiles
for each row execute function public.normalize_profile_username();

alter table public.profiles enable row level security;
alter table public.sends enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
on public.profiles for select
to authenticated
using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles for insert
to authenticated
with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists "sends_select_participants" on public.sends;
create policy "sends_select_participants"
on public.sends for select
to authenticated
using (sender_id = auth.uid() or recipient_id = auth.uid());

drop policy if exists "friend_requests_select_participants" on public.friend_requests;
create policy "friend_requests_select_participants"
on public.friend_requests for select
to authenticated
using (from_id = auth.uid() or to_id = auth.uid());

drop policy if exists "friendships_select_own" on public.friendships;
create policy "friendships_select_own"
on public.friendships for select
to authenticated
using (user_a = auth.uid() or user_b = auth.uid());

drop policy if exists "blocks_select_own" on public.blocks;
create policy "blocks_select_own"
on public.blocks for select
to authenticated
using (blocker_id = auth.uid());

drop policy if exists "blocks_insert_own" on public.blocks;
create policy "blocks_insert_own"
on public.blocks for insert
to authenticated
with check (blocker_id = auth.uid());

drop policy if exists "blocks_delete_own" on public.blocks;
create policy "blocks_delete_own"
on public.blocks for delete
to authenticated
using (blocker_id = auth.uid());

drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own"
on public.reports for insert
to authenticated
with check (reporter_id = auth.uid());

create or replace function public.send_with_sender_json(p_send public.sends)
returns json
language sql
stable
set search_path = public
as $$
  select json_build_object(
    'id', p_send.id,
    'sender_id', p_send.sender_id,
    'recipient_id', p_send.recipient_id,
    'artwork', p_send.artwork,
    'note', p_send.note,
    'target_country', p_send.target_country,
    'direct', p_send.direct,
    'status', p_send.status,
    'created_at', p_send.created_at,
    'delivered_at', p_send.delivered_at,
    'read_at', p_send.read_at,
    'sender', json_build_object('id', pr.id, 'username', pr.username, 'country', pr.country)
  )
  from public.profiles pr
  where pr.id = p_send.sender_id;
$$;

create or replace function public.ensure_profile()
returns public.profiles
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.profiles;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  if v_profile.id is null then
    raise exception 'Create your profile first.';
  end if;
  return v_profile;
end;
$$;

create or replace function public.send_painting(
  p_artwork jsonb,
  p_note text,
  p_target_country text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender public.profiles;
  v_recipient uuid;
  v_send public.sends;
  v_today date := (now() at time zone 'utc')::date;
begin
  v_sender := public.ensure_profile();
  p_target_country := upper(trim(p_target_country));
  p_note := trim(p_note);

  if p_note = '' or char_length(p_note) > 1000 then
    raise exception 'Note must be between 1 and 1000 characters.';
  end if;
  if p_target_country !~ '^[A-Z]{2}$' then
    raise exception 'Choose a valid target country.';
  end if;
  if p_artwork is null or not (p_artwork ? 'id') or not (p_artwork ? 'image_id') then
    raise exception 'Choose a painting before sending.';
  end if;

  if (
    select count(*)
    from public.sends
    where sender_id = v_sender.id
      and direct = false
      and (created_at at time zone 'utc')::date = v_today
  ) >= 3 then
    raise exception 'You have already sent 3 paintings today.';
  end if;

  select p.id into v_recipient
  from public.profiles p
  where p.country = p_target_country
    and p.id <> v_sender.id
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = p.id and b.blocked_id = v_sender.id)
         or (b.blocker_id = v_sender.id and b.blocked_id = p.id)
    )
    and not exists (
      select 1 from public.sends s
      where s.direct = false
        and s.recipient_id = p.id
        and (s.delivered_at at time zone 'utc')::date = v_today
    )
  order by random()
  limit 1;

  insert into public.sends (
    sender_id, recipient_id, artwork, note, target_country, direct, status, delivered_at
  )
  values (
    v_sender.id,
    v_recipient,
    p_artwork,
    p_note,
    p_target_country,
    false,
    case when v_recipient is null then 'queued' else 'delivered' end,
    case when v_recipient is null then null else now() end
  )
  returning * into v_send;

  return row_to_json(v_send);
end;
$$;

create or replace function public.claim_daily()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles;
  v_send public.sends;
  v_today date := (now() at time zone 'utc')::date;
begin
  v_profile := public.ensure_profile();

  select * into v_send
  from public.sends
  where direct = false
    and recipient_id = v_profile.id
    and (delivered_at at time zone 'utc')::date = v_today
  order by delivered_at asc
  limit 1;
  if v_send.id is not null then
    return public.send_with_sender_json(v_send);
  end if;

  select * into v_send
  from public.sends
  where direct = false
    and recipient_id = v_profile.id
    and status = 'delivered'
    and read_at is null
  order by delivered_at asc
  limit 1
  for update skip locked;
  if v_send.id is not null then
    update public.sends
    set delivered_at = now()
    where id = v_send.id
    returning * into v_send;
    return public.send_with_sender_json(v_send);
  end if;

  select * into v_send
  from public.sends s
  where s.direct = false
    and s.sender_id <> v_profile.id
    and s.target_country = v_profile.country
    and s.recipient_id is distinct from v_profile.id
    and (
      s.status = 'queued'
      or (s.status = 'delivered' and s.read_at is null and s.delivered_at < now() - interval '3 days')
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = v_profile.id and b.blocked_id = s.sender_id)
         or (b.blocker_id = s.sender_id and b.blocked_id = v_profile.id)
    )
  order by s.created_at asc
  limit 1
  for update skip locked;

  if v_send.id is null then
    return null;
  end if;

  update public.sends
  set recipient_id = v_profile.id,
      status = 'delivered',
      delivered_at = now()
  where id = v_send.id
  returning * into v_send;

  return public.send_with_sender_json(v_send);
end;
$$;

create or replace function public.mark_read(p_send_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.sends
  set read_at = coalesce(read_at, now()),
      status = 'read'
  where id = p_send_id
    and recipient_id = auth.uid();

  if not found then
    raise exception 'Only the recipient can mark this painting as read.';
  end if;
end;
$$;

create or replace function public.request_friend(p_send_id uuid, p_reply_note text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_send public.sends;
  v_request public.friend_requests;
  v_from uuid := auth.uid();
  v_a uuid;
  v_b uuid;
begin
  p_reply_note := trim(p_reply_note);

  select * into v_send
  from public.sends
  where id = p_send_id
    and recipient_id = v_from
    and read_at is not null;

  if v_send.id is null then
    raise exception 'Read the painting before requesting friendship.';
  end if;
  if p_reply_note = '' or char_length(p_reply_note) > 500 then
    raise exception 'Reply note must be between 1 and 500 characters.';
  end if;

  v_a := least(v_from, v_send.sender_id);
  v_b := greatest(v_from, v_send.sender_id);

  if exists (select 1 from public.friendships where user_a = v_a and user_b = v_b) then
    raise exception 'You are already friends.';
  end if;
  if exists (
    select 1 from public.friend_requests
    where status = 'pending'
      and ((from_id = v_from and to_id = v_send.sender_id) or (from_id = v_send.sender_id and to_id = v_from))
  ) then
    raise exception 'A friendship request is already pending.';
  end if;
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = v_from and b.blocked_id = v_send.sender_id)
       or (b.blocker_id = v_send.sender_id and b.blocked_id = v_from)
  ) then
    raise exception 'Friend requests are unavailable for this sender.';
  end if;

  insert into public.friend_requests (send_id, from_id, to_id, reply_note)
  values (p_send_id, v_from, v_send.sender_id, p_reply_note)
  returning * into v_request;

  return row_to_json(v_request);
end;
$$;

create or replace function public.respond_friend(p_request_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.friend_requests;
begin
  select * into v_request
  from public.friend_requests
  where id = p_request_id
    and to_id = auth.uid()
    and status = 'pending'
  for update;

  if v_request.id is null then
    raise exception 'Friend request not found.';
  end if;

  update public.friend_requests
  set status = case when p_accept then 'accepted' else 'declined' end
  where id = p_request_id;

  if p_accept then
    insert into public.friendships (user_a, user_b)
    values (least(v_request.from_id, v_request.to_id), greatest(v_request.from_id, v_request.to_id))
    on conflict do nothing;
  end if;
end;
$$;

create or replace function public.send_to_friend(
  p_artwork jsonb,
  p_note text,
  p_friend_id uuid
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender public.profiles;
  v_friend public.profiles;
  v_send public.sends;
begin
  v_sender := public.ensure_profile();
  select * into v_friend from public.profiles where id = p_friend_id;
  p_note := trim(p_note);

  if v_friend.id is null then
    raise exception 'Friend not found.';
  end if;
  if p_note = '' or char_length(p_note) > 1000 then
    raise exception 'Note must be between 1 and 1000 characters.';
  end if;
  if not exists (
    select 1 from public.friendships
    where user_a = least(v_sender.id, p_friend_id)
      and user_b = greatest(v_sender.id, p_friend_id)
  ) then
    raise exception 'You can only send directly to friends.';
  end if;
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = v_sender.id and b.blocked_id = p_friend_id)
       or (b.blocker_id = p_friend_id and b.blocked_id = v_sender.id)
  ) then
    raise exception 'Direct sends are unavailable for this friend.';
  end if;

  insert into public.sends (
    sender_id, recipient_id, artwork, note, target_country, direct, status, delivered_at
  )
  values (v_sender.id, p_friend_id, p_artwork, p_note, v_friend.country, true, 'delivered', now())
  returning * into v_send;

  return row_to_json(v_send);
end;
$$;

create or replace function public.get_journal()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  perform public.ensure_profile();

  return json_build_object(
    'sent', coalesce((
      select json_agg(json_build_object(
        'id', s.id,
        'artwork', s.artwork,
        'note', s.note,
        'target_country', s.target_country,
        'direct', s.direct,
        'status', s.status,
        'created_at', s.created_at,
        'delivered_at', s.delivered_at,
        'read_at', s.read_at,
        'recipient_id', s.recipient_id,
        'friend_request', (
          select row_to_json(fr) from public.friend_requests fr where fr.send_id = s.id limit 1
        )
      ) order by s.created_at desc)
      from public.sends s
      where s.sender_id = v_uid
    ), '[]'::json),
    'received', coalesce((
      select json_agg(json_build_object(
        'id', s.id,
        'sender_id', s.sender_id,
        'recipient_id', s.recipient_id,
        'sender', json_build_object('id', p.id, 'username', p.username, 'country', p.country),
        'artwork', s.artwork,
        'note', s.note,
        'target_country', s.target_country,
        'direct', s.direct,
        'status', s.status,
        'created_at', s.created_at,
        'delivered_at', s.delivered_at,
        'read_at', s.read_at,
        'friend_request', (
          select row_to_json(fr) from public.friend_requests fr where fr.send_id = s.id limit 1
        )
      ) order by coalesce(s.delivered_at, s.created_at) desc)
      from public.sends s
      join public.profiles p on p.id = s.sender_id
      where s.recipient_id = v_uid
        and (s.read_at is not null or s.status = 'delivered')
    ), '[]'::json),
    'friend_requests', json_build_object(
      'incoming', coalesce((
        select json_agg(json_build_object(
          'id', fr.id,
          'send_id', fr.send_id,
          'from_id', fr.from_id,
          'from_profile', json_build_object('id', p.id, 'username', p.username, 'country', p.country),
          'reply_note', fr.reply_note,
          'status', fr.status,
          'created_at', fr.created_at,
          'artwork', s.artwork
        ) order by fr.created_at desc)
        from public.friend_requests fr
        join public.profiles p on p.id = fr.from_id
        join public.sends s on s.id = fr.send_id
        where fr.to_id = v_uid
      ), '[]'::json),
      'outgoing', coalesce((
        select json_agg(json_build_object(
          'id', fr.id,
          'send_id', fr.send_id,
          'to_id', fr.to_id,
          'to_profile', json_build_object('id', p.id, 'username', p.username, 'country', p.country),
          'reply_note', fr.reply_note,
          'status', fr.status,
          'created_at', fr.created_at,
          'artwork', s.artwork
        ) order by fr.created_at desc)
        from public.friend_requests fr
        join public.profiles p on p.id = fr.to_id
        join public.sends s on s.id = fr.send_id
        where fr.from_id = v_uid
      ), '[]'::json)
    ),
    'friends', coalesce((
      select json_agg(json_build_object(
        'id', p.id,
        'username', p.username,
        'country', p.country,
        'created_at', f.created_at
      ) order by p.username)
      from public.friendships f
      join public.profiles p on p.id = case when f.user_a = v_uid then f.user_b else f.user_a end
      where f.user_a = v_uid or f.user_b = v_uid
    ), '[]'::json)
  );
end;
$$;

revoke all on function public.send_painting(jsonb, text, text) from public;
revoke all on function public.claim_daily() from public;
revoke all on function public.mark_read(uuid) from public;
revoke all on function public.request_friend(uuid, text) from public;
revoke all on function public.respond_friend(uuid, boolean) from public;
revoke all on function public.send_to_friend(jsonb, text, uuid) from public;
revoke all on function public.get_journal() from public;
revoke all on function public.ensure_profile() from public;
grant execute on function public.ensure_profile() to authenticated;

revoke all on function public.send_painting(jsonb, text, text) from anon;
revoke all on function public.claim_daily() from anon;
revoke all on function public.mark_read(uuid) from anon;
revoke all on function public.request_friend(uuid, text) from anon;
revoke all on function public.respond_friend(uuid, boolean) from anon;
revoke all on function public.send_to_friend(jsonb, text, uuid) from anon;
revoke all on function public.get_journal() from anon;

grant execute on function public.send_painting(jsonb, text, text) to authenticated;
grant execute on function public.claim_daily() to authenticated;
grant execute on function public.mark_read(uuid) to authenticated;
grant execute on function public.request_friend(uuid, text) to authenticated;
grant execute on function public.respond_friend(uuid, boolean) to authenticated;
grant execute on function public.send_to_friend(jsonb, text, uuid) to authenticated;
grant execute on function public.get_journal() to authenticated;

create index if not exists sends_daily_slot_idx on public.sends (recipient_id, direct, delivered_at);
create index if not exists sends_pool_idx on public.sends (target_country, direct, status, created_at);
create index if not exists sends_sender_created_idx on public.sends (sender_id, direct, created_at);
create index if not exists friend_requests_participants_idx on public.friend_requests (from_id, to_id, status);
