-- MNC Build 2: the "What's happening" screen.
-- Handoff: vault punchlists/mnc-gallery-ad-and-feed-handoff.md; decisions on
-- the MNC punchlist (2026-10-10 11:20 AM, 6:30 PM and 7:15 PM lines).
--
-- Three kinds of item in one feed, newest first, your city first, then your
-- state, then everywhere, up to 100:
--   request    a client asks for a set ("Gel fill, need it by Friday")
--   available  a tech is free now, until a time she picks, with a note
--   photo      a tech's new gallery photo (the existing board_posts rows)
--
-- Who is who: every person is keyed by their phone, '+1XXXXXXXXXX', the same
-- key push uses. Nobody's phone is ever returned by these functions.
--
-- Locked down from day one: RLS is on for every table and there are no
-- read policies for ordinary users. Everything goes through the security
-- definer functions below, which check who is calling. Admins can read the
-- tables directly.
--
-- Pushes go out from inside these functions through _booking_push (server
-- key from Vault), so send-push's strict mode never blocks them.
--
-- Testing guard: wh_settings.near_push_admin_only starts TRUE, so a new
-- request pushes only techs who are admins (Anne). Flip it off at launch:
--   update public.wh_settings set value = 'false' where key = 'near_push_admin_only';
--
-- Built to scale (Anne, 2026-10-11, "what if it's 100,000 a day"): the feed
-- reads your city, your state and everywhere as three small indexed slices,
-- never the whole table; a nightly job marks ended requests, folds raw clicks
-- into daily totals (raw kept 90 days) and calls the wh-cleanup edge function,
-- which deletes a request's photo a week after the request ends.
--
-- Run AFTER sql/build0-guest-lane.sql, sql/admin-flag.sql and
-- sql/stealth-profile.sql. Idempotent. Re-run freely.

begin;

-- ── Helpers ─────────────────────────────────────────────────────────────────

-- The caller's person key, or null for a guest.
create or replace function public.wh_me_key() returns text
language sql stable
set search_path = public
as $$
  select case when length(coalesce(public.current_phone(), '')) >= 10
              then '+1' || right(public.current_phone(), 10) end;
$$;

-- A stored phone as a person key.
create or replace function public.wh_key(p_phone text) returns text
language sql immutable
set search_path = public
as $$
  select case when length(coalesce(public.phone_digits(p_phone), '')) >= 10
              then '+1' || right(public.phone_digits(p_phone), 10) end;
$$;

create table if not exists public.wh_settings (
  key   text primary key,
  value jsonb not null
);
alter table public.wh_settings enable row level security;
insert into public.wh_settings (key, value) values
  ('near_push_admin_only', 'true'),
  ('near_push_daily_cap',  '3'),
  ('reply_daily_cap',      '10'),
  ('quiet_start_hour',     '21'),
  ('quiet_end_hour',       '7')
on conflict (key) do nothing;

create or replace function public.wh_setting(p_key text) returns jsonb
language sql stable security definer
set search_path = public
as $$ select value from public.wh_settings where key = p_key; $$;

-- A US state from the first three digits of a ZIP, for profiles that have a
-- ZIP but no state (6 of 37 techs on 2026-10-11). Standard USPS prefixes.
create or replace function public.wh_state_from_zip(p_zip text) returns text
language sql immutable
set search_path = public
as $$
  select case
    when z is null then null
    when z between 5 and 5 then 'NY'
    when z between 6 and 9 then 'PR'
    when z between 10 and 27 then 'MA'
    when z between 28 and 29 then 'RI'
    when z between 30 and 38 then 'NH'
    when z between 39 and 49 then 'ME'
    when z = 55 then 'MA'
    when z between 50 and 59 then 'VT'
    when z between 60 and 69 then 'CT'
    when z between 70 and 89 then 'NJ'
    when z between 100 and 149 then 'NY'
    when z between 150 and 196 then 'PA'
    when z between 197 and 199 then 'DE'
    when z between 200 and 205 then 'DC'
    when z between 206 and 219 then 'MD'
    when z between 220 and 246 then 'VA'
    when z between 247 and 268 then 'WV'
    when z between 270 and 289 then 'NC'
    when z between 290 and 299 then 'SC'
    when z between 300 and 319 then 'GA'
    when z between 320 and 349 then 'FL'
    when z between 350 and 369 then 'AL'
    when z between 370 and 385 then 'TN'
    when z between 386 and 397 then 'MS'
    when z between 398 and 399 then 'GA'
    when z between 400 and 427 then 'KY'
    when z between 430 and 459 then 'OH'
    when z between 460 and 479 then 'IN'
    when z between 480 and 499 then 'MI'
    when z between 500 and 528 then 'IA'
    when z between 530 and 549 then 'WI'
    when z between 550 and 567 then 'MN'
    when z = 569 then 'DC'
    when z between 570 and 577 then 'SD'
    when z between 580 and 588 then 'ND'
    when z between 590 and 599 then 'MT'
    when z between 600 and 629 then 'IL'
    when z between 630 and 658 then 'MO'
    when z between 660 and 679 then 'KS'
    when z between 680 and 693 then 'NE'
    when z between 700 and 714 then 'LA'
    when z between 716 and 729 then 'AR'
    when z between 730 and 749 then 'OK'
    when z = 885 then 'TX'
    when z between 750 and 799 then 'TX'
    when z between 800 and 816 then 'CO'
    when z between 820 and 831 then 'WY'
    when z between 832 and 838 then 'ID'
    when z between 840 and 847 then 'UT'
    when z between 850 and 865 then 'AZ'
    when z between 870 and 884 then 'NM'
    when z between 889 and 898 then 'NV'
    when z between 900 and 961 then 'CA'
    when z between 967 and 968 then 'HI'
    when z between 970 and 979 then 'OR'
    when z between 980 and 994 then 'WA'
    when z between 995 and 999 then 'AK'
    else null end
  from (select case when coalesce(p_zip, '') ~ '^\s*\d{5}' then substring(btrim(p_zip) from 1 for 3)::int end as z) x;
$$;

-- A stored state, or the one its ZIP implies.
create or replace function public.wh_state(p_state text, p_zip text) returns text
language sql immutable
set search_path = public
as $$
  select coalesce(nullif(upper(btrim(coalesce(p_state, ''))), ''), public.wh_state_from_zip(p_zip), '');
$$;

-- ── Tables ──────────────────────────────────────────────────────────────────

create table if not exists public.wh_requests (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  author_key   text not null,
  author_name  text not null default '',
  author_image text,
  city         text not null default '',
  state        text not null default '',
  body         text not null check (char_length(body) between 1 and 400),
  need_by      date,
  photo_url    text,
  status       text not null default 'open' check (status in ('open', 'found', 'closed', 'removed')),
  expires_at   timestamptz not null,
  removed_note text
);
alter table public.wh_requests add column if not exists closed_at timestamptz;
alter table public.wh_requests add column if not exists photo_cleaned_at timestamptz;
alter table public.wh_requests drop constraint if exists wh_requests_status_check;
alter table public.wh_requests add constraint wh_requests_status_check
  check (status in ('open', 'found', 'closed', 'removed', 'expired'));
create index if not exists wh_requests_open_idx on public.wh_requests (status, expires_at desc);
create index if not exists wh_requests_author_idx on public.wh_requests (author_key, created_at desc);
create index if not exists wh_requests_place_idx on public.wh_requests (lower(btrim(state)), lower(btrim(city)), created_at desc) where status = 'open';
create index if not exists wh_requests_recent_idx on public.wh_requests (created_at desc) where status = 'open';
create index if not exists wh_requests_photo_idx on public.wh_requests (closed_at, expires_at) where photo_url is not null;
create index if not exists board_posts_publish_idx on public.board_posts (publish_at desc);

create table if not exists public.wh_replies (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  request_id uuid not null references public.wh_requests(id) on delete cascade,
  tech_id    uuid not null,
  tech_key   text not null,
  note       text not null default '' check (char_length(note) <= 280),
  show_book  boolean not null default true,
  show_call  boolean not null default true,
  show_text  boolean not null default true,
  removed    boolean not null default false,
  unique (request_id, tech_id)
);
create index if not exists wh_replies_tech_idx on public.wh_replies (tech_key, created_at desc);

-- One row per tech; posting again replaces it.
create table if not exists public.wh_available (
  tech_id    uuid primary key,
  tech_key   text not null,
  created_at timestamptz not null default now(),
  until      timestamptz not null,
  note       text not null default '' check (char_length(note) <= 200),
  removed    boolean not null default false
);

create table if not exists public.wh_reports (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  reporter_key text not null,
  kind         text not null check (kind in ('request', 'reply', 'available', 'photo')),
  target_id    text not null,
  target_key   text,
  snapshot     text,
  reason       text not null default '' check (char_length(reason) <= 500),
  status       text not null default 'open' check (status in ('open', 'done')),
  admin_note   text,
  handled_at   timestamptz
);
create index if not exists wh_reports_status_idx on public.wh_reports (status, created_at desc);

create table if not exists public.wh_blocks (
  blocker_key text not null,
  blocked_key text not null,
  created_at  timestamptz not null default now(),
  primary key (blocker_key, blocked_key)
);

create table if not exists public.wh_bans (
  person_key text primary key,
  created_at timestamptz not null default now(),
  note       text not null default ''
);

create table if not exists public.wh_prefs (
  person_key    text primary key,
  reply_alerts  boolean not null default true,
  near_alerts   boolean not null default true,
  updated_at    timestamptz not null default now()
);

create table if not exists public.wh_near_pushes (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  tech_id    uuid not null,
  request_id uuid not null
);
create index if not exists wh_near_pushes_tech_idx on public.wh_near_pushes (tech_id, created_at desc);

-- Stats (admin-stats "What's happening" panel). The app logs screen opens,
-- tabs, sheet opens and taps (server = false); the functions below log every
-- post, reply, close, report and block themselves (server = true), so those
-- counts cannot be inflated from outside.
create table if not exists public.wh_events (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  event      text not null check (char_length(event) <= 40),
  detail     text check (char_length(detail) <= 60),
  item_id    text check (char_length(item_id) <= 64),
  tech_id    uuid,
  role       text check (role in ('guest', 'client', 'tech', 'admin')),
  session_id text check (char_length(session_id) <= 64),
  server     boolean not null default false
);
create index if not exists wh_events_created_idx on public.wh_events (created_at desc);
create index if not exists wh_events_event_idx on public.wh_events (event, created_at desc);
create index if not exists wh_events_tech_idx on public.wh_events (tech_id, created_at desc) where tech_id is not null;

-- Daily totals. Raw clicks older than 90 days are folded in here and deleted.
create table if not exists public.wh_events_daily (
  day     date not null,
  event   text not null,
  detail  text not null default '',
  role    text not null default '',
  tech_id uuid not null default '00000000-0000-0000-0000-000000000000',
  n       bigint not null,
  primary key (day, event, detail, role, tech_id)
);
alter table public.wh_events_daily enable row level security;
drop policy if exists wh_events_daily_admin_read on public.wh_events_daily;
create policy wh_events_daily_admin_read on public.wh_events_daily for select to authenticated using (public.is_admin());
revoke all on public.wh_events_daily from anon;

create or replace function public.wh_log(p_event text, p_detail text default null, p_item_id text default null, p_tech_id uuid default null)
returns void
language sql security definer
set search_path = public
as $$
  insert into public.wh_events (event, detail, item_id, tech_id, role, server)
  values (p_event, left(p_detail, 60), left(p_item_id, 64), p_tech_id,
          case when public.wh_me_key() is null then 'guest'
               when public.is_admin() then 'admin'
               when (public.wh_my_tech()).id is not null then 'tech'
               else 'client' end,
          true);
$$;

do $$
declare t text;
begin
  foreach t in array array['wh_events','wh_requests','wh_replies','wh_available','wh_reports','wh_blocks','wh_bans','wh_prefs','wh_near_pushes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_admin_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_admin())', t || '_admin_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- The app may add its own events (never server ones).
drop policy if exists wh_events_insert_app on public.wh_events;
create policy wh_events_insert_app on public.wh_events
  for insert to anon, authenticated
  with check (not server);
grant insert on public.wh_events to anon, authenticated;
grant usage, select on sequence public.wh_events_id_seq to anon, authenticated;

-- Is either of two people blocking the other?
create or replace function public.wh_blocked(a text, b text) returns boolean
language sql stable security definer
set search_path = public
as $$
  select a is not null and b is not null and exists (
    select 1 from public.wh_blocks
     where (blocker_key = a and blocked_key = b) or (blocker_key = b and blocked_key = a)
  );
$$;

-- The caller's tech row, if the caller is a tech.
create or replace function public.wh_my_tech() returns public.techs
language sql stable security definer
set search_path = public
as $$
  select t.* from public.techs t
   where public.wh_me_key() is not null
     and public.wh_key(t.phone) = public.wh_me_key()
   order by t.created_at desc
   limit 1;
$$;

-- A tech shows on the boards when she is in view (same rule as techs_public:
-- not stealth unless it is you) and not self-paused.
create or replace function public.wh_tech_in_view(t public.techs) returns boolean
language sql stable security definer
set search_path = public
as $$
  select (not coalesce(t.stealth, false)
          or public.wh_key(t.phone) = public.wh_me_key()
          or public.is_admin())
     and public.is_visible(t);
$$;

-- Hour of day in a time zone.
create or replace function public.wh_quiet_now(p_tz text) returns boolean
language plpgsql stable
set search_path = public
as $$
declare
  h int := extract(hour from (now() at time zone coalesce(nullif(p_tz, ''), 'America/Phoenix')))::int;
  s int := coalesce((public.wh_setting('quiet_start_hour'))::text::int, 21);
  e int := coalesce((public.wh_setting('quiet_end_hour'))::text::int, 7);
begin
  return h >= s or h < e;
exception when others then
  return false;
end $$;

-- ── The feed ────────────────────────────────────────────────────────────────

-- Guests: counts only.
create or replace function public.wh_teaser() returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'requests',  (select count(*) from public.wh_requests r where r.status = 'open' and r.expires_at > now()),
    'available', (select count(*) from public.techs t
                    left join public.wh_available a on a.tech_id = t.id
                   where t.is_available
                     and (a.tech_id is null or (not a.removed and a.until > now()))
                     and not coalesce(t.stealth, false) and public.is_visible(t))
  );
$$;

-- Signed in: the merged feed. p_kind = null for everything, or one of
-- 'request', 'available', 'photo'. City and state are the viewer's own.
create or replace function public.wh_feed(p_city text default null, p_state text default null, p_kind text default null)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  me     text := public.wh_me_key();
  v_city text := lower(btrim(coalesce(p_city, '')));
  v_st   text := lower(btrim(coalesce(p_state, '')));
  v_out  jsonb;
begin
  if me is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if v_st = '' then
    select lower(public.wh_state(u.state, u.zip)) into v_st
      from public.users u where public.wh_key(u.phone) = me
     order by u.created_at desc nulls last limit 1;
    v_st := coalesce(v_st, '');
  end if;

  with items as (
    select 'request'::text as kind, r.id::text as id, r.created_at as at,
           r.city, r.state, r.body, r.photo_url as photo,
           split_part(btrim(r.author_name), ' ', 1) as name, r.author_image as image,
           null::uuid as tech_id, r.need_by, r.expires_at as ends_at,
           (r.author_key = me) as mine,
           (select count(*) from public.wh_replies x where x.request_id = r.id and not x.removed
              and not public.wh_blocked(r.author_key, x.tech_key))::int as replies,
           exists (select 1 from public.wh_replies x
                    where x.request_id = r.id and x.tech_key = me) as replied
      -- Never the whole table: her own open requests, then the newest in her
      -- city, in her state and everywhere, each an indexed slice of 150.
      from (
        (select x.* from public.wh_requests x
          where x.author_key = me and x.status = 'open' and x.expires_at > now())
        union
        (select x.* from public.wh_requests x
          where v_city <> '' and x.status = 'open' and x.expires_at > now()
            and (v_st = '' or lower(btrim(x.state)) = v_st) and lower(btrim(x.city)) = v_city
          order by x.created_at desc limit 150)
        union
        (select x.* from public.wh_requests x
          where v_st <> '' and x.status = 'open' and x.expires_at > now()
            and lower(btrim(x.state)) = v_st
          order by x.created_at desc limit 150)
        union
        (select x.* from public.wh_requests x
          where x.status = 'open' and x.expires_at > now()
          order by x.created_at desc limit 150)
      ) r
     where (p_kind is null or p_kind = 'request')
       and not public.wh_blocked(me, r.author_key)
    union all
    -- Every tech with Open today on, however she turned it on (this
    -- screen, the chip on an older build, the morning prompt). A post from
    -- this screen adds her note and end time.
    select 'available', t.id::text, coalesce(a.created_at, t.avail_set_at, now()),
           t.city, public.wh_state(t.state, t.zip), coalesce(a.note, ''), null,
           t.name, t.image_url,
           t.id, null::date, a.until,
           (public.wh_key(t.phone) = me), 0, false
      from public.techs t
      left join public.wh_available a on a.tech_id = t.id
     where (p_kind is null or p_kind = 'available')
       and t.is_available
       and (a.tech_id is null or (not a.removed and a.until > now()))
       and public.wh_tech_in_view(t)
       and not public.wh_blocked(me, public.wh_key(t.phone))
    union all
    select 'photo', b.id::text, b.publish_at,
           t.city, public.wh_state(t.state, t.zip), b.body, b.image_url,
           t.name, t.image_url,
           t.id, null::date, null::timestamptz,
           (public.wh_key(t.phone) = me), 0, false
      from (select b0.*, row_number() over (partition by b0.tech_uuid order by b0.publish_at desc) as rn
              from (select b1.* from public.board_posts b1
                     where b1.image_url is not null
                       and b1.publish_at <= now() and b1.publish_at > now() - interval '60 days'
                     order by b1.publish_at desc limit 400) b0) b
      join public.techs t on t.id = b.tech_uuid
     where (p_kind is null or p_kind = 'photo')
       and b.rn <= 2
       and public.wh_tech_in_view(t)
       and not public.wh_blocked(me, public.wh_key(t.phone))
  ), ranked as (
    select i.*,
           case when v_city <> '' and lower(btrim(i.city)) = v_city
                     and (v_st = '' or lower(btrim(i.state)) = v_st) then 0
                when v_st <> '' and lower(btrim(i.state)) = v_st then 1
                else 2 end as near
      from items i
     order by near, at desc
     limit 100
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', kind, 'id', id, 'at', at, 'city', city, 'state', state,
           'body', body, 'photo', photo, 'name', name, 'image', image,
           'tech_id', tech_id, 'need_by', need_by, 'ends_at', ends_at,
           'mine', mine, 'replies', replies, 'replied', replied, 'near', near
         ) order by near, at desc), '[]'::jsonb)
    into v_out
    from ranked;
  return v_out;
end $$;

-- ── Requests (2a) ───────────────────────────────────────────────────────────

-- p_tz is the poster's device time zone; a need-by date ends at the end of
-- that day there. No date = 14 days. City and state come from her profile;
-- when the profile has none (client sign-up only asks for a ZIP), the ones
-- she types on the sheet are used and saved back to her profile.
drop function if exists public.wh_post_request(text, date, text, text);
create or replace function public.wh_post_request(
  p_body text, p_need_by date default null, p_photo_url text default null, p_tz text default null,
  p_city text default null, p_state text default null
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me      text := public.wh_me_key();
  u       public.users;
  v_tz    text := coalesce(nullif(btrim(p_tz), ''), 'America/Phoenix');
  v_exp   timestamptz;
  v_row   public.wh_requests;
  v_admin_only boolean := coalesce((public.wh_setting('near_push_admin_only'))::text::boolean, true);
  v_cap   int := coalesce((public.wh_setting('near_push_daily_cap'))::text::int, 3);
  v_pushed int := 0;
  t       record;
begin
  if me is null then
    return jsonb_build_object('ok', false, 'code', 'sign_in');
  end if;
  if exists (select 1 from public.wh_bans where person_key = me) then
    return jsonb_build_object('ok', false, 'code', 'banned');
  end if;
  if coalesce(btrim(p_body), '') = '' then
    return jsonb_build_object('ok', false, 'code', 'empty');
  end if;
  if (select count(*) from public.wh_requests
       where author_key = me and status = 'open' and expires_at > now()) >= 3 then
    return jsonb_build_object('ok', false, 'code', 'too_many');
  end if;

  select * into u from public.users
   where public.wh_key(phone) = me
   order by created_at desc nulls last
   limit 1;
  if coalesce(btrim(u.city), '') = '' then
    if coalesce(btrim(p_city), '') = '' then
      return jsonb_build_object('ok', false, 'code', 'city_needed');
    end if;
    u.city  := left(btrim(p_city), 60);
    u.state := coalesce(nullif(left(upper(btrim(coalesce(p_state, ''))), 2), ''), u.state);
    if u.id is not null then
      update public.users set city = u.city, state = coalesce(u.state, state) where id = u.id;
    end if;
  end if;

  if p_need_by is not null then
    begin
      v_exp := ((p_need_by + 1)::timestamp) at time zone v_tz;
    exception when others then
      v_exp := ((p_need_by + 1)::timestamp) at time zone 'America/Phoenix';
    end;
    if v_exp <= now() then
      return jsonb_build_object('ok', false, 'code', 'date_past');
    end if;
    if v_exp > now() + interval '60 days' then
      v_exp := now() + interval '60 days';
    end if;
  else
    v_exp := now() + interval '14 days';
  end if;

  insert into public.wh_requests (author_key, author_name, author_image, city, state, body, need_by, photo_url, expires_at)
  values (me, coalesce(u.name, ''), u.image_url, btrim(u.city), public.wh_state(u.state, u.zip),
          btrim(p_body), p_need_by, nullif(btrim(coalesce(p_photo_url, '')), ''), v_exp)
  returning * into v_row;

  -- Near-me pushes: same city and state, switch on, not blocked, not in
  -- quiet hours, under the daily cap. While testing, admins only.
  for t in
    select x.id, x.email, x.phone, x.name,
           coalesce(x.avail_reminder_tz, x.booking_timezone, 'America/Phoenix') as tz
      from public.techs x
     where lower(btrim(coalesce(x.city, ''))) = lower(btrim(v_row.city))
       and lower(public.wh_state(x.state, x.zip)) = lower(btrim(v_row.state))
       and public.wh_key(x.phone) is not null
       and public.wh_key(x.phone) <> me
       and coalesce((select p.near_alerts from public.wh_prefs p where p.person_key = public.wh_key(x.phone)), true)
       and not public.wh_blocked(me, public.wh_key(x.phone))
       and (not v_admin_only or exists (
             select 1 from public.users au
              where public.wh_key(au.phone) = public.wh_key(x.phone)
                and (coalesce(au.admin, false) or lower(coalesce(au.role, '')) = 'admin')))
  loop
    if public.wh_quiet_now(t.tz) then continue; end if;
    if (select count(*) from public.wh_near_pushes n
         where n.tech_id = t.id
           and n.created_at > ((date_trunc('day', now() at time zone t.tz)) at time zone t.tz)) >= v_cap then
      continue;
    end if;
    perform public._booking_push(
      public.wh_key(t.phone),
      'New request near you',
      left(split_part(btrim(v_row.author_name), ' ', 1) || ' in ' || v_row.city || ': ' || v_row.body, 140),
      'wh-req-' || v_row.id,
      'wh-near'
    );
    insert into public.wh_near_pushes (tech_id, request_id) values (t.id, v_row.id);
    v_pushed := v_pushed + 1;
  end loop;

  perform public.wh_log('post_request', case when v_row.photo_url is not null then 'photo' when v_row.need_by is not null then 'date' else 'plain' end, v_row.id::text);
  if v_pushed > 0 then perform public.wh_log('push_near', v_pushed::text, v_row.id::text); end if;
  return jsonb_build_object('ok', true, 'id', v_row.id, 'expires_at', v_row.expires_at, 'pushed', v_pushed);
end $$;

-- The client closes her own request: 'found' (Found someone) or 'closed'.
create or replace function public.wh_close_request(p_id uuid, p_status text default 'found')
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me text := public.wh_me_key();
  n  int;
begin
  if p_status not in ('found', 'closed') then
    return jsonb_build_object('ok', false, 'code', 'bad_status');
  end if;
  update public.wh_requests set status = p_status, closed_at = now()
   where id = p_id and author_key = me and status = 'open';
  get diagnostics n = row_count;
  if n = 1 then perform public.wh_log('close_request', p_status, p_id::text); end if;
  return jsonb_build_object('ok', n = 1);
end $$;

-- The caller's own requests, open and recent, for "My requests".
create or replace function public.wh_my_requests() returns jsonb
language sql stable security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'at', r.created_at, 'body', r.body, 'need_by', r.need_by,
           'photo', r.photo_url, 'status', case when r.status in ('open', 'expired') and r.expires_at <= now() then 'expired' else r.status end,
           'ends_at', r.expires_at,
           'replies', (select count(*) from public.wh_replies x where x.request_id = r.id and not x.removed
                         and not public.wh_blocked(r.author_key, x.tech_key))
         ) order by r.created_at desc), '[]'::jsonb)
    from public.wh_requests r
   where r.author_key = public.wh_me_key()
     and r.created_at > now() - interval '30 days'
     and r.status <> 'removed';
$$;

-- ── Available now (2a) ──────────────────────────────────────────────────────

-- A tech posts that she is free until p_until with a note. Turns Open today
-- on, so the Gallery glow, counts, reset cron and reminder keep working.
create or replace function public.wh_post_available(p_until timestamptz, p_note text default '')
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me text := public.wh_me_key();
  t  public.techs := public.wh_my_tech();
begin
  if t.id is null then
    return jsonb_build_object('ok', false, 'code', 'not_tech');
  end if;
  if exists (select 1 from public.wh_bans where person_key = me) then
    return jsonb_build_object('ok', false, 'code', 'banned');
  end if;
  if p_until is null or p_until <= now() then
    return jsonb_build_object('ok', false, 'code', 'time_past');
  end if;
  if p_until > now() + interval '24 hours' then
    p_until := now() + interval '24 hours';
  end if;
  if exists (select 1 from public.wh_available where tech_id = t.id and removed and until > now()) then
    return jsonb_build_object('ok', false, 'code', 'removed');
  end if;

  insert into public.wh_available (tech_id, tech_key, created_at, until, note, removed)
  values (t.id, me, now(), p_until, left(btrim(coalesce(p_note, '')), 200), false)
  on conflict (tech_id) do update
    set tech_key = excluded.tech_key, created_at = now(), until = excluded.until,
        note = excluded.note, removed = false;

  update public.techs set is_available = true where id = t.id and not coalesce(is_available, false);

  perform public.wh_log('post_available', case when btrim(coalesce(p_note, '')) <> '' then 'note' else 'plain' end, null, t.id);
  return jsonb_build_object('ok', true, 'until', p_until);
end $$;

-- She is not free any more: clears the post and turns Open today off.
create or replace function public.wh_clear_available() returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  t public.techs := public.wh_my_tech();
begin
  if t.id is null then
    return jsonb_build_object('ok', false, 'code', 'not_tech');
  end if;
  delete from public.wh_available where tech_id = t.id and not removed;
  update public.techs set is_available = false where id = t.id and coalesce(is_available, false);
  perform public.wh_log('clear_available', null, null, t.id);
  return jsonb_build_object('ok', true);
end $$;

-- The caller's own available-now post, if any.
create or replace function public.wh_my_available() returns jsonb
language sql stable security definer
set search_path = public
as $$
  select to_jsonb(x) from (
    select a.until, a.note, a.created_at, t.is_available
      from public.wh_available a
      join public.techs t on t.id = a.tech_id
     where a.tech_id = (public.wh_my_tech()).id
       and not a.removed and a.until > now()
  ) x;
$$;

-- Every 15 minutes: a window that has ended turns Open today off. Turning
-- Open today off any other way (the chip, the midnight reset) hides the
-- post at once because the feed also needs is_available.
create or replace function public.wh_expire_available() returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  n int := 0;
begin
  with gone as (
    delete from public.wh_available a
     where a.until <= now()
     returning a.tech_id, a.removed
  )
  update public.techs t set is_available = false
    from gone where t.id = gone.tech_id and not gone.removed and coalesce(t.is_available, false);
  get diagnostics n = row_count;
  delete from public.wh_available where not removed and tech_id in (
    select id from public.techs where not coalesce(is_available, false));
  return jsonb_build_object('turned_off', n);
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'wh-expire-available') then
    perform cron.unschedule('wh-expire-available');
  end if;
  perform cron.schedule('wh-expire-available', '*/15 * * * *', 'select public.wh_expire_available()');
end $$;

-- ── Interested replies (2b) ─────────────────────────────────────────────────

create or replace function public.wh_reply(
  p_request_id uuid, p_note text default '',
  p_show_book boolean default true, p_show_call boolean default true, p_show_text boolean default true
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me    text := public.wh_me_key();
  t     public.techs := public.wh_my_tech();
  r     public.wh_requests;
  v_cap int := coalesce((public.wh_setting('reply_daily_cap'))::text::int, 10);
  v_tz  text;
begin
  if t.id is null then
    return jsonb_build_object('ok', false, 'code', 'not_tech');
  end if;
  if exists (select 1 from public.wh_bans where person_key = me) then
    return jsonb_build_object('ok', false, 'code', 'banned');
  end if;
  select * into r from public.wh_requests where id = p_request_id;
  if r.id is null or r.status <> 'open' or r.expires_at <= now() then
    return jsonb_build_object('ok', false, 'code', 'closed');
  end if;
  if r.author_key = me then
    return jsonb_build_object('ok', false, 'code', 'own_request');
  end if;
  if public.wh_blocked(me, r.author_key) then
    return jsonb_build_object('ok', false, 'code', 'closed');
  end if;
  if exists (select 1 from public.wh_replies where request_id = r.id and tech_id = t.id) then
    return jsonb_build_object('ok', false, 'code', 'already');
  end if;
  v_tz := coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix');
  if (select count(*) from public.wh_replies
       where tech_key = me
         and created_at > ((date_trunc('day', now() at time zone v_tz)) at time zone v_tz)) >= v_cap then
    return jsonb_build_object('ok', false, 'code', 'daily_cap');
  end if;
  if not (coalesce(p_show_book, false) or coalesce(p_show_call, false) or coalesce(p_show_text, false)) then
    return jsonb_build_object('ok', false, 'code', 'pick_one');
  end if;

  insert into public.wh_replies (request_id, tech_id, tech_key, note, show_book, show_call, show_text)
  values (r.id, t.id, me, left(btrim(coalesce(p_note, '')), 280),
          coalesce(p_show_book, false), coalesce(p_show_call, false), coalesce(p_show_text, false));

  if coalesce((select p.reply_alerts from public.wh_prefs p where p.person_key = r.author_key), true) then
    perform public._booking_push(
      r.author_key,
      coalesce(nullif(btrim(t.name), ''), 'A tech') || ' is interested',
      left(coalesce(nullif(btrim(p_note), ''), 'Tap to see her reply to your request.'), 140),
      'wh-reply-' || r.id,
      'wh-reply'
    );
    perform public.wh_log('push_reply', null, r.id::text, t.id);
  end if;

  perform public.wh_log('reply', concat_ws(',', case when p_show_book then 'book' end, case when p_show_call then 'call' end, case when p_show_text then 'text' end), r.id::text, t.id);
  return jsonb_build_object('ok', true);
end $$;

-- Replies under a request. The client who posted it sees all of them; a tech
-- sees her own; admins see all. Phones are never returned (Call and Text
-- fetch through tech_contact at tap time).
create or replace function public.wh_replies_for(p_request_id uuid) returns jsonb
language sql stable security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'at', x.created_at, 'note', x.note,
           'tech_id', t.id, 'name', t.name, 'image', t.image_url,
           'show_book', x.show_book, 'show_call', x.show_call, 'show_text', x.show_text,
           'booking_link', nullif(btrim(coalesce(t.booking_link, '')), ''),
           'contact_methods', t.contact_methods,
           'mine', x.tech_key = public.wh_me_key()
         ) order by x.created_at), '[]'::jsonb)
    from public.wh_replies x
    join public.wh_requests r on r.id = x.request_id
    join public.techs t on t.id = x.tech_id
   where x.request_id = p_request_id
     and not x.removed
     and public.wh_me_key() is not null
     and (r.author_key = public.wh_me_key() or x.tech_key = public.wh_me_key() or public.is_admin())
     and not public.wh_blocked(r.author_key, x.tech_key);
$$;

-- ── Switches ────────────────────────────────────────────────────────────────

create or replace function public.wh_my_prefs() returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'reply_alerts', coalesce((select reply_alerts from public.wh_prefs where person_key = public.wh_me_key()), true),
    'near_alerts',  coalesce((select near_alerts  from public.wh_prefs where person_key = public.wh_me_key()), true)
  );
$$;

create or replace function public.wh_set_pref(p_name text, p_on boolean) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me text := public.wh_me_key();
begin
  if me is null then return jsonb_build_object('ok', false, 'code', 'sign_in'); end if;
  if p_name not in ('reply_alerts', 'near_alerts') then
    return jsonb_build_object('ok', false, 'code', 'bad_name');
  end if;
  insert into public.wh_prefs (person_key) values (me) on conflict (person_key) do nothing;
  if p_name = 'reply_alerts' then
    update public.wh_prefs set reply_alerts = coalesce(p_on, true), updated_at = now() where person_key = me;
  else
    update public.wh_prefs set near_alerts = coalesce(p_on, true), updated_at = now() where person_key = me;
  end if;
  return public.wh_my_prefs() || jsonb_build_object('ok', true);
end $$;

-- ── Report and block (2c) ───────────────────────────────────────────────────

-- Who is behind an item, and a short copy of it for the admin.
create or replace function public.wh_item_owner(p_kind text, p_id text, out owner_key text, out snapshot text)
language plpgsql stable security definer
set search_path = public
as $$
begin
  if p_kind = 'request' then
    select r.author_key, r.author_name || ' (' || r.city || '): ' || r.body
      into owner_key, snapshot from public.wh_requests r where r.id::text = p_id;
  elsif p_kind = 'reply' then
    select x.tech_key, t.name || ': ' || x.note
      into owner_key, snapshot from public.wh_replies x join public.techs t on t.id = x.tech_id where x.id::text = p_id;
  elsif p_kind = 'available' then
    select public.wh_key(t.phone), t.name || ' (available): ' || coalesce(a.note, '')
      into owner_key, snapshot from public.techs t left join public.wh_available a on a.tech_id = t.id where t.id::text = p_id;
  elsif p_kind = 'photo' then
    select public.wh_key(t.phone), t.name || ' (photo): ' || coalesce(b.image_url, '')
      into owner_key, snapshot from public.board_posts b join public.techs t on t.id = b.tech_uuid where b.id::text = p_id;
  end if;
end $$;

create or replace function public.wh_report(p_kind text, p_id text, p_reason text default '')
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me text := public.wh_me_key();
  o  record;
begin
  if me is null then return jsonb_build_object('ok', false, 'code', 'sign_in'); end if;
  if p_kind not in ('request', 'reply', 'available', 'photo') then
    return jsonb_build_object('ok', false, 'code', 'bad_kind');
  end if;
  select * into o from public.wh_item_owner(p_kind, p_id);
  if o.owner_key is null then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  if (select count(*) from public.wh_reports where reporter_key = me and created_at > now() - interval '1 day') >= 20 then
    return jsonb_build_object('ok', false, 'code', 'daily_cap');
  end if;
  insert into public.wh_reports (reporter_key, kind, target_id, target_key, snapshot, reason)
  values (me, p_kind, p_id, o.owner_key, left(o.snapshot, 600), left(btrim(coalesce(p_reason, '')), 500));
  perform public.wh_log('report', p_kind, p_id);
  return jsonb_build_object('ok', true);
end $$;

-- Block the person behind an item. Both sides stop seeing each other.
create or replace function public.wh_block(p_kind text, p_id text) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me text := public.wh_me_key();
  o  record;
begin
  if me is null then return jsonb_build_object('ok', false, 'code', 'sign_in'); end if;
  select * into o from public.wh_item_owner(p_kind, p_id);
  if o.owner_key is null or o.owner_key = me then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;
  insert into public.wh_blocks (blocker_key, blocked_key) values (me, o.owner_key)
  on conflict do nothing;
  perform public.wh_log('block', p_kind, p_id);
  return jsonb_build_object('ok', true);
end $$;

-- ── Admin (2c) ──────────────────────────────────────────────────────────────

create or replace function public.admin_wh_reports(p_show_done boolean default false) returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', p.id, 'at', p.created_at, 'kind', p.kind, 'target_id', p.target_id,
             'snapshot', p.snapshot, 'reason', p.reason, 'status', p.status,
             'admin_note', p.admin_note, 'handled_at', p.handled_at,
             'banned', exists (select 1 from public.wh_bans b where b.person_key = p.target_key),
             'reports_on_person', (select count(*) from public.wh_reports q where q.target_key = p.target_key)
           ) order by p.created_at desc), '[]'::jsonb)
      from public.wh_reports p
     where p_show_done or p.status = 'open'
  );
end $$;

-- p_action: 'remove' (take the item down), 'ban' (take it down and stop the
-- person posting), 'dismiss' (nothing wrong). Always closes the report.
create or replace function public.admin_wh_resolve(p_report_id uuid, p_action text, p_note text default '')
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  p public.wh_reports;
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if p_action not in ('remove', 'ban', 'dismiss', 'unban') then
    return jsonb_build_object('ok', false, 'code', 'bad_action');
  end if;
  select * into p from public.wh_reports where id = p_report_id;
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;

  if p_action in ('remove', 'ban') then
    if p.kind = 'request' then
      update public.wh_requests set status = 'removed', removed_note = p_note, closed_at = coalesce(closed_at, now()) where id::text = p.target_id;
    elsif p.kind = 'reply' then
      update public.wh_replies set removed = true where id::text = p.target_id;
    elsif p.kind = 'available' then
      insert into public.wh_available (tech_id, tech_key, until, removed)
      values (p.target_id::uuid, coalesce(p.target_key, ''), now() + interval '1 day', true)
      on conflict (tech_id) do update set removed = true, until = now() + interval '1 day';
      update public.techs set is_available = false where id::text = p.target_id;
    elsif p.kind = 'photo' then
      delete from public.board_posts where id::text = p.target_id;
    end if;
  end if;
  if p_action = 'ban' and p.target_key is not null then
    insert into public.wh_bans (person_key, note) values (p.target_key, coalesce(p_note, ''))
    on conflict (person_key) do update set note = excluded.note;
  end if;
  if p_action = 'unban' and p.target_key is not null then
    delete from public.wh_bans where person_key = p.target_key;
  end if;

  update public.wh_reports
     set status = case when p_action = 'unban' then status else 'done' end,
         admin_note = nullif(btrim(coalesce(p_note, '')), ''), handled_at = now()
   where id = p.id;
  return jsonb_build_object('ok', true);
end $$;

-- ── Admin stats ─────────────────────────────────────────────────────────────
-- Everything the admin-stats panel shows, for the last p_days days (0 = all
-- time). The daily chart always covers the last 30 days.
create or replace function public.admin_wh_stats(p_days int default 30) returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_from timestamptz := case when coalesce(p_days, 0) <= 0 then '-infinity'::timestamptz else now() - make_interval(days => p_days) end;
  -- Raw rows older than this have been folded into wh_events_daily.
  v_raw  timestamptz := coalesce((select min(created_at) from public.wh_events), now());
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return (
  with ev as (
    select event, coalesce(detail, '') as detail, coalesce(role, 'guest') as role, tech_id, 1::bigint as n
      from public.wh_events where created_at >= v_from
    union all
    select event, detail, case when role = '' then 'guest' else role end,
           nullif(tech_id, '00000000-0000-0000-0000-000000000000'::uuid), n
      from public.wh_events_daily
     where day < (v_raw at time zone 'America/Phoenix')::date
       and (v_from = '-infinity'::timestamptz or day >= (v_from at time zone 'America/Phoenix')::date)
  )
  select jsonb_build_object(
    'events', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (
        select event || case when detail <> '' then ':' || detail else '' end as k, sum(n) as n
          from ev group by 1) x),
    'event_totals', (select coalesce(jsonb_object_agg(event, n), '{}'::jsonb) from (
        select event, sum(n) as n from ev group by 1) x),
    'opens_by_role', (select coalesce(jsonb_object_agg(role, n), '{}'::jsonb) from (
        select role, sum(n) as n from ev where event = 'open' group by 1) x),
    'open_sessions', (select count(distinct session_id) from public.wh_events where event = 'open' and created_at >= v_from),
    'daily_opens', (select coalesce(jsonb_object_agg(d, n), '{}'::jsonb) from (
        select to_char(created_at at time zone 'America/Phoenix', 'YYYY-MM-DD') as d, count(*) as n
          from public.wh_events where event = 'open' and created_at >= now() - interval '30 days' group by 1) x),
    'daily_posts', (select coalesce(jsonb_object_agg(d, n), '{}'::jsonb) from (
        select to_char(created_at at time zone 'America/Phoenix', 'YYYY-MM-DD') as d, count(*) as n
          from public.wh_events where server and event in ('post_request', 'post_available', 'reply')
           and created_at >= now() - interval '30 days' group by 1) x),
    'requests', (select jsonb_build_object(
        'posted',     count(*),
        'open',       count(*) filter (where status = 'open' and expires_at > now()),
        'found',      count(*) filter (where status = 'found'),
        'closed',     count(*) filter (where status = 'closed'),
        'removed',    count(*) filter (where status = 'removed'),
        'expired',    count(*) filter (where status = 'expired' or (status = 'open' and expires_at <= now())),
        'with_reply', count(*) filter (where exists (select 1 from public.wh_replies x where x.request_id = r.id)),
        'with_photo', count(*) filter (where photo_url is not null))
        from public.wh_requests r where created_at >= v_from),
    'replies', (select count(*) from public.wh_replies where created_at >= v_from),
    'available_now', (select count(*) from public.techs t left join public.wh_available a on a.tech_id = t.id
                       where t.is_available and (a.tech_id is null or (not a.removed and a.until > now()))),
    'near_pushes', (select count(*) from public.wh_near_pushes where created_at >= v_from),
    'reports_open', (select count(*) from public.wh_reports where status = 'open'),
    'blocks', (select count(*) from public.wh_blocks where created_at >= v_from),
    'cities', (select coalesce(jsonb_object_agg(c, n), '{}'::jsonb) from (
        select initcap(btrim(city)) || coalesce(', ' || nullif(upper(btrim(state)), ''), '') as c, count(*) as n
          from public.wh_requests where created_at >= v_from group by 1 order by 2 desc limit 10) x),
    'top_techs', (select coalesce(jsonb_agg(row_to_json(x) order by x.profile_taps desc, x.contacts desc), '[]'::jsonb) from (
        select t.id, t.name,
               coalesce(sum(e.n) filter (where e.event = 'profile_tap'), 0) as profile_taps,
               coalesce(sum(e.n) filter (where e.event = 'contact'), 0) as contacts,
               coalesce(sum(e.n) filter (where e.event = 'reply'), 0) as replies,
               coalesce(sum(e.n) filter (where e.event = 'post_available'), 0) as available_posts
          from ev e join public.techs t on t.id = e.tech_id
         group by t.id, t.name
         order by 3 desc, 4 desc
         limit 10) x)
  ));
end $$;

-- ── Nightly upkeep ──────────────────────────────────────────────────────────
-- 3:15 AM Phoenix. Marks ended requests, folds raw clicks older than 90 days
-- into daily totals, trims the push cap log, then asks the wh-cleanup edge
-- function to delete photos from requests that ended over a week ago.
create or replace function public.wh_nightly() returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_cut     timestamptz := ((date_trunc('day', now() at time zone 'America/Phoenix') - interval '90 days') at time zone 'America/Phoenix');
  v_expired int;
  v_folded  int;
  k_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53cW5ha29vbmdyb3Jid25ycXpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzNzczMjUsImV4cCI6MjA5ODk1MzMyNX0.TFFMlg9VjB0cyJwbgmVbeatFYQFaF1Ri0nrH0GwhHJs';
begin
  update public.wh_requests set status = 'expired', closed_at = coalesce(closed_at, expires_at)
   where status = 'open' and expires_at <= now();
  get diagnostics v_expired = row_count;

  insert into public.wh_events_daily (day, event, detail, role, tech_id, n)
  select (created_at at time zone 'America/Phoenix')::date, event, coalesce(detail, ''), coalesce(role, ''),
         coalesce(tech_id, '00000000-0000-0000-0000-000000000000'::uuid), count(*)
    from public.wh_events
   where created_at < v_cut
   group by 1, 2, 3, 4, 5
  on conflict (day, event, detail, role, tech_id) do update set n = public.wh_events_daily.n + excluded.n;
  delete from public.wh_events where created_at < v_cut;
  get diagnostics v_folded = row_count;

  delete from public.wh_near_pushes where created_at < now() - interval '3 days';

  perform net.http_post(
    url := 'https://nwqnakoongrorbwnrqzc.supabase.co/functions/v1/wh-cleanup',
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', k_anon, 'Authorization', 'Bearer ' || k_anon),
    body := '{}'::jsonb
  );

  return jsonb_build_object('expired', v_expired, 'clicks_folded', v_folded);
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'wh-nightly') then
    perform cron.unschedule('wh-nightly');
  end if;
  perform cron.schedule('wh-nightly', '15 10 * * *', 'select public.wh_nightly()');
end $$;

-- For the wh-cleanup edge function (service role only): photos from requests
-- that ended more than a week ago, and the stamp once they are deleted.
create or replace function public.wh_photos_to_clean(p_limit int default 500)
returns table (id uuid, photo_url text)
language sql stable security definer
set search_path = public
as $$
  select r.id, r.photo_url
    from public.wh_requests r
   where r.photo_url is not null
     and (   (r.status <> 'open' and coalesce(r.closed_at, r.expires_at) < now() - interval '7 days')
          or (r.expires_at < now() - interval '7 days'))
   order by coalesce(r.closed_at, r.expires_at)
   limit greatest(1, least(coalesce(p_limit, 500), 1000));
$$;

create or replace function public.wh_photos_cleaned(p_ids uuid[]) returns int
language plpgsql security definer
set search_path = public
as $$
declare n int;
begin
  update public.wh_requests set photo_url = null, photo_cleaned_at = now() where id = any(p_ids);
  get diagnostics n = row_count;
  return n;
end $$;

-- ── Grants ──────────────────────────────────────────────────────────────────

revoke all on function public.wh_setting(text) from public, anon, authenticated;
revoke all on function public.wh_item_owner(text, text) from public, anon, authenticated;
revoke all on function public.wh_log(text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.wh_blocked(text, text) from public, anon, authenticated;
revoke all on function public.wh_my_tech() from public, anon, authenticated;
revoke all on function public.wh_tech_in_view(public.techs) from public, anon, authenticated;

grant execute on function public.wh_teaser() to anon, authenticated;

do $$
declare f text;
begin
  foreach f in array array[
    'wh_feed(text, text, text)',
    'wh_post_request(text, date, text, text, text, text)',
    'wh_close_request(uuid, text)',
    'wh_my_requests()',
    'wh_post_available(timestamptz, text)',
    'wh_clear_available()',
    'wh_my_available()',
    'wh_reply(uuid, text, boolean, boolean, boolean)',
    'wh_replies_for(uuid)',
    'wh_my_prefs()',
    'wh_set_pref(text, boolean)',
    'wh_report(text, text, text)',
    'wh_block(text, text)',
    'admin_wh_reports(boolean)',
    'admin_wh_resolve(uuid, text, text)',
    'admin_wh_stats(int)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.wh_expire_available() from public, anon, authenticated;
revoke all on function public.wh_nightly() from public, anon, authenticated;
revoke all on function public.wh_photos_to_clean(int) from public, anon, authenticated;
revoke all on function public.wh_photos_cleaned(uuid[]) from public, anon, authenticated;
grant execute on function public.wh_photos_to_clean(int) to service_role;
grant execute on function public.wh_photos_cleaned(uuid[]) to service_role;

-- ── Request photos ──────────────────────────────────────────────────────────
-- Public read (the link is random); a signed-in person writes only under
-- requests/<their phone digits>/.
insert into storage.buckets (id, name, public)
values ('wh-photos', 'wh-photos', true)
on conflict (id) do update set public = true;

drop policy if exists wh_photos_read on storage.objects;
create policy wh_photos_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'wh-photos');

drop policy if exists wh_photos_insert_own on storage.objects;
create policy wh_photos_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'wh-photos'
    and (storage.foldername(name))[1] = 'requests'
    and (storage.foldername(name))[2] = right(coalesce(public.current_phone(), ''), 10)
    and length(coalesce(public.current_phone(), '')) >= 10
  );

drop policy if exists wh_photos_admin_delete on storage.objects;
create policy wh_photos_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'wh-photos' and public.is_admin());

commit;

-- ── Check ───────────────────────────────────────────────────────────────────
-- select public.wh_teaser();                                   -- {"requests":0,"available":0}
-- select jobname, schedule from cron.job where jobname in ('wh-expire-available', 'wh-nightly');
-- select public.wh_nightly();                                 -- safe to run by hand
-- select * from public.wh_settings order by key;
