alter table public.profiles
  add column if not exists lat double precision,
  add column if not exists lng double precision;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_lat_range'
  ) then
    alter table public.profiles
      add constraint profiles_lat_range check (lat is null or lat between -90 and 90);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_lng_range'
  ) then
    alter table public.profiles
      add constraint profiles_lng_range check (lng is null or lng between -180 and 180);
  end if;
end;
$$;

alter table public.sends
  add column if not exists target_lat double precision,
  add column if not exists target_lng double precision;

alter table public.sends alter column target_country drop not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.sends'::regclass and conname = 'sends_target_lat_range'
  ) then
    alter table public.sends
      add constraint sends_target_lat_range check (target_lat is null or target_lat between -90 and 90);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.sends'::regclass and conname = 'sends_target_lng_range'
  ) then
    alter table public.sends
      add constraint sends_target_lng_range check (target_lng is null or target_lng between -180 and 180);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.sends'::regclass and conname = 'sends_target_required'
  ) then
    alter table public.sends
      add constraint sends_target_required check (
        direct = true
        or target_country is not null
        or (target_lat is not null and target_lng is not null)
      );
  end if;
end;
$$;

create or replace function public.haversine_km(
  lat1 double precision,
  lng1 double precision,
  lat2 double precision,
  lng2 double precision
)
returns double precision
language sql
immutable
strict
parallel safe
set search_path = public
as $$
  select 6371.0 * 2.0 * asin(sqrt(least(1.0,
    power(sin(radians(lat2 - lat1) / 2.0), 2)
    + cos(radians(lat1)) * cos(radians(lat2))
      * power(sin(radians(lng2 - lng1) / 2.0), 2)
  )));
$$;

drop function if exists public.send_painting(jsonb, text, text);

create or replace function public.send_painting(
  p_artwork jsonb,
  p_note text,
  p_target_country text default null,
  p_target_lat double precision default null,
  p_target_lng double precision default null
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
  p_target_country := nullif(upper(trim(p_target_country)), '');
  p_note := trim(p_note);

  if p_note = '' or char_length(p_note) > 1000 then
    raise exception 'Note must be between 1 and 1000 characters.';
  end if;
  if p_artwork is null or not (p_artwork ? 'id') or not (p_artwork ? 'image_small') then
    raise exception 'Choose a painting before sending.';
  end if;
  if (p_target_lat is null) <> (p_target_lng is null) then
    raise exception 'Choose a complete map location.';
  end if;
  if (p_target_country is null) = (p_target_lat is null) then
    raise exception 'Choose exactly one target: a country or a map pin.';
  end if;
  if p_target_country is not null and p_target_country !~ '^[A-Z]{2}$' then
    raise exception 'Choose a valid target country.';
  end if;
  if p_target_lat is not null and (p_target_lat < -90 or p_target_lat > 90) then
    raise exception 'Latitude must be between -90 and 90.';
  end if;
  if p_target_lng is not null and (p_target_lng < -180 or p_target_lng > 180) then
    raise exception 'Longitude must be between -180 and 180.';
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

  if p_target_country is not null then
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
  else
    select p.id into v_recipient
    from public.profiles p
    where p.lat is not null
      and p.lng is not null
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
    order by public.haversine_km(p_target_lat, p_target_lng, p.lat, p.lng), p.id
    limit 1;
  end if;

  insert into public.sends (
    sender_id, recipient_id, artwork, note, target_country, target_lat, target_lng,
    direct, status, delivered_at
  )
  values (
    v_sender.id,
    v_recipient,
    p_artwork,
    p_note,
    p_target_country,
    p_target_lat,
    p_target_lng,
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
    and (
      s.target_country = v_profile.country
      or (s.target_country is null and s.target_lat is not null)
    )
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

revoke all on function public.haversine_km(double precision, double precision, double precision, double precision) from public;
revoke all on function public.haversine_km(double precision, double precision, double precision, double precision) from anon;
grant execute on function public.haversine_km(double precision, double precision, double precision, double precision) to authenticated;

revoke all on function public.send_painting(jsonb, text, text, double precision, double precision) from public;
revoke all on function public.send_painting(jsonb, text, text, double precision, double precision) from anon;
grant execute on function public.send_painting(jsonb, text, text, double precision, double precision) to authenticated;

revoke all on function public.claim_daily() from public;
revoke all on function public.claim_daily() from anon;
grant execute on function public.claim_daily() to authenticated;

create index if not exists profiles_location_idx on public.profiles (lat, lng)
where lat is not null and lng is not null;

-- Privacy: profiles now carry exact coordinates. The old policy let any
-- authenticated user select every row (fine for username+country, not for
-- lat/lng). All cross-user profile data flows through security-definer RPCs,
-- so clients only ever need their own row.
drop policy if exists "profiles_select_authenticated" on public.profiles;
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles for select
to authenticated
using (id = auth.uid());

create index if not exists sends_geo_pool_idx
on public.sends (target_lat, direct, status, created_at)
where target_country is null and target_lat is not null;
