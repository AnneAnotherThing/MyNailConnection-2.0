-- MNC What's happening: "willing to travel" radius for near-me pushes
-- (Build 1, Anne, 2026-10-13: her Surprise request reached Surprise techs
-- only; Peoria and Glendale saw it on the board under "In AZ" but got no ping).
--
-- What changes:
--   0. Clients choose too. wh_requests gains max_miles (10, 25, 50, or null
--      for anywhere in her state): how far she would travel. It caps the push
--      on top of the tech's radius; it does not change who sees the board.
--   1. Requests get a point. wh_requests gains lat, lng and from_device. The
--      app sends the client's device location when she allows it; otherwise
--      the request sits at the center of her ZIP (zip_centroids, loaded by
--      sql/zip-centroids-data.sql), or failing that the center of her city.
--      The city text stays as it was, for display and the ring chips. A client
--      with no city but a known ZIP gets her city filled from the ZIP.
--   2. Techs get a radius. wh_prefs gains near_radius_miles (10, 25, 50, or 0
--      for anywhere in her state; default 25). wh_set_radius writes it,
--      wh_my_prefs reports it.
--   3. The push loop matches by distance. A tech's point is her geocoded
--      address, else the center of her ZIP, else the center of her city. When
--      both sides have a point: within her radius. Radius 0: same state. When
--      either side has no point: same city and state, as before. Quiet hours,
--      snooze, the admin-only switch and the push body are unchanged.
--
-- Order: run THIS file first, then sql/zip-centroids-data.sql (40,979 rows).
-- Until the data file runs, every request and tech falls back to the city
-- match, so nothing breaks in between.
--
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query.
-- Proof this is the new copy: wh_post_request has "p_lat double precision".

begin;

-- ── 1. ZIP centroids ─────────────────────────────────────────────────────────

create table if not exists public.zip_centroids (
  zip   text primary key,
  lat   double precision not null,
  lng   double precision not null,
  city  text not null default '',
  state text not null default ''
);
alter table public.zip_centroids enable row level security;
revoke all on public.zip_centroids from anon, authenticated;
create index if not exists zip_centroids_place_idx on public.zip_centroids (state, lower(city));

-- ── 2. Columns ───────────────────────────────────────────────────────────────

alter table public.wh_requests add column if not exists lat double precision;
alter table public.wh_requests add column if not exists lng double precision;
alter table public.wh_requests add column if not exists from_device boolean not null default false;
-- How far the client would travel (Anne, 2026-10-13): 10, 25 or 50 miles,
-- or null for anywhere in her state. Caps the push on top of the tech's radius.
alter table public.wh_requests add column if not exists max_miles int;
alter table public.wh_requests drop constraint if exists wh_requests_max_miles_check;
alter table public.wh_requests add constraint wh_requests_max_miles_check
  check (max_miles is null or max_miles in (10, 25, 50));

alter table public.wh_prefs add column if not exists near_radius_miles int not null default 25;
alter table public.wh_prefs drop constraint if exists wh_prefs_near_radius_check;
alter table public.wh_prefs add constraint wh_prefs_near_radius_check
  check (near_radius_miles in (0, 10, 25, 50));

-- ── 3. Helpers ───────────────────────────────────────────────────────────────

-- Great-circle miles between two points. Null when either point is missing.
create or replace function public.wh_miles(lat1 double precision, lng1 double precision,
                                           lat2 double precision, lng2 double precision)
returns double precision
language sql immutable
set search_path = public
as $$
  select case
    when lat1 is null or lng1 is null or lat2 is null or lng2 is null then null
    else 3958.8 * 2 * asin(least(1.0, sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2) +
           cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))))
  end;
$$;

-- The centroid row for a ZIP (first five digits), or an all-null row.
create or replace function public.wh_zip_point(p_zip text) returns public.zip_centroids
language sql stable
set search_path = public
as $$
  select z.* from public.zip_centroids z
   where z.zip = left(regexp_replace(coalesce(p_zip, ''), '\D', '', 'g'), 5)
   limit 1;
$$;

-- Where someone is: her stored coordinates, else her ZIP's center, else the
-- center of her city (the average of that city's ZIPs). Nulls when nothing fits.
create or replace function public.wh_point(p_lat double precision, p_lng double precision,
                                           p_zip text, p_city text, p_state text,
                                           out lat double precision, out lng double precision)
language plpgsql stable
set search_path = public
as $$
declare
  z public.zip_centroids;
begin
  if p_lat is not null and p_lng is not null then
    lat := p_lat; lng := p_lng; return;
  end if;
  z := public.wh_zip_point(p_zip);
  if z.zip is not null then
    lat := z.lat; lng := z.lng; return;
  end if;
  if coalesce(btrim(p_city), '') <> '' and coalesce(btrim(p_state), '') <> '' then
    select avg(c.lat), avg(c.lng) into lat, lng
      from public.zip_centroids c
     where c.state = upper(btrim(p_state)) and lower(c.city) = lower(btrim(p_city));
  end if;
end $$;

revoke all on function public.wh_miles(double precision, double precision, double precision, double precision) from public, anon, authenticated;
revoke all on function public.wh_zip_point(text) from public, anon, authenticated;
revoke all on function public.wh_point(double precision, double precision, text, text, text) from public, anon, authenticated;

-- ── 4. Prefs ─────────────────────────────────────────────────────────────────

create or replace function public.wh_my_prefs() returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'reply_alerts', coalesce((select reply_alerts from public.wh_prefs where person_key = public.wh_me_key()), true),
    'near_alerts',  coalesce((select near_alerts  from public.wh_prefs where person_key = public.wh_me_key()), true),
    'near_radius_miles', coalesce((select near_radius_miles from public.wh_prefs where person_key = public.wh_me_key()), 25),
    'near_snoozed_until', (select near_snoozed_until from public.wh_prefs
                            where person_key = public.wh_me_key() and near_snoozed_until > now())
  );
$$;

-- How far a client can be for a push: 10, 25 or 50 miles, or 0 for anywhere
-- in her state.
create or replace function public.wh_set_radius(p_miles int) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me text := public.wh_me_key();
begin
  if me is null then return jsonb_build_object('ok', false, 'code', 'sign_in'); end if;
  if p_miles is null or p_miles not in (0, 10, 25, 50) then
    return jsonb_build_object('ok', false, 'code', 'bad_miles');
  end if;
  insert into public.wh_prefs (person_key) values (me) on conflict (person_key) do nothing;
  update public.wh_prefs set near_radius_miles = p_miles, updated_at = now() where person_key = me;
  perform public.wh_log('near_radius', p_miles::text);
  return public.wh_my_prefs() || jsonb_build_object('ok', true);
end $$;

revoke all on function public.wh_set_radius(int) from public, anon;
grant execute on function public.wh_set_radius(int) to authenticated;

-- ── 5. Posting a request ─────────────────────────────────────────────────────

-- The old six-argument shape goes first: with both shapes present PostgREST
-- cannot pick one and every post fails with 300. The new shape defaults the
-- two extra arguments, so phones on 3.0.7 keep posting (ZIP center).
drop function if exists public.wh_post_request(text, date, text, text, text, text);

create or replace function public.wh_post_request(
  p_body text, p_need_by date default null, p_photo_url text default null, p_tz text default null,
  p_city text default null, p_state text default null,
  p_lat double precision default null, p_lng double precision default null,
  p_max_miles int default null
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me      text := public.wh_me_key();
  u       public.users;
  z       public.zip_centroids;
  v_tz    text := coalesce(nullif(btrim(p_tz), ''), 'America/Phoenix');
  v_exp   timestamptz;
  v_lat   double precision;
  v_lng   double precision;
  v_dev   boolean := false;
  v_max   int := case when p_max_miles in (10, 25, 50) then p_max_miles else null end;
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
  z := public.wh_zip_point(u.zip);

  -- City is required. Hers on file, else the one she typed, else the city her
  -- ZIP sits in. Whatever fills it is saved to her profile.
  if coalesce(btrim(u.city), '') = '' then
    if coalesce(btrim(p_city), '') <> '' then
      u.city  := left(btrim(p_city), 60);
      u.state := coalesce(nullif(left(upper(btrim(coalesce(p_state, ''))), 2), ''), u.state);
    elsif z.zip is not null then
      u.city  := z.city;
      u.state := coalesce(nullif(upper(btrim(coalesce(u.state, ''))), ''), z.state);
    else
      return jsonb_build_object('ok', false, 'code', 'city_needed');
    end if;
    if u.id is not null then
      update public.users set city = u.city, state = coalesce(u.state, state) where id = u.id;
    end if;
  end if;

  -- Where the request is: her device if the app sent it, else her ZIP's
  -- center, else the center of her city.
  if p_lat is not null and p_lng is not null
     and p_lat between -90 and 90 and p_lng between -180 and 180 then
    v_lat := p_lat; v_lng := p_lng; v_dev := true;
  else
    select pt.lat, pt.lng into v_lat, v_lng
      from public.wh_point(null, null, u.zip, u.city, public.wh_state(u.state, u.zip)) pt;
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

  insert into public.wh_requests (author_key, author_name, author_image, city, state, body, need_by, photo_url, expires_at,
                                  lat, lng, from_device, max_miles)
  values (me, coalesce(u.name, ''), u.image_url, btrim(u.city), public.wh_state(u.state, u.zip),
          btrim(p_body), p_need_by, nullif(btrim(coalesce(p_photo_url, '')), ''), v_exp,
          v_lat, v_lng, v_dev, v_max)
  returning * into v_row;

  -- Near-me pushes. With a distance between the two points: inside the tech's
  -- radius (or her state when her radius is 0) AND inside the client's own
  -- limit, if she set one. Without a distance (one side has no point): same
  -- city and state, or same state when her radius is 0. Switch on, not
  -- snoozed, not blocked, not in quiet hours. While testing, admins only.
  for t in
    select x.id, x.email, x.phone, x.name,
           coalesce(x.avail_reminder_tz, x.booking_timezone, 'America/Phoenix') as tz
      from public.techs x
      left join public.wh_prefs p on p.person_key = public.wh_key(x.phone)
      cross join lateral (
        select q.lat, q.lng, public.wh_miles(v_row.lat, v_row.lng, q.lat, q.lng) as d,
               coalesce(p.near_radius_miles, 25) as r,
               lower(public.wh_state(x.state, x.zip)) = lower(btrim(v_row.state)) as same_state,
               lower(btrim(coalesce(x.city, ''))) = lower(btrim(v_row.city)) as same_city
          from public.wh_point(x.lat, x.lng, x.zip, x.city, public.wh_state(x.state, x.zip)) q
      ) pt
     where public.wh_key(x.phone) is not null
       and public.wh_key(x.phone) <> me
       and coalesce(p.near_alerts, true)
       and coalesce(p.near_snoozed_until, now() - interval '1 second') <= now()
       and not public.wh_blocked(me, public.wh_key(x.phone))
       and (not v_admin_only or exists (
             select 1 from public.users au
              where public.wh_key(au.phone) = public.wh_key(x.phone)
                and (coalesce(au.admin, false) or lower(coalesce(au.role, '')) = 'admin')))
       and (
         (pt.d is not null
            and (v_row.max_miles is null or pt.d <= v_row.max_miles)
            and ((pt.r > 0 and pt.d <= pt.r) or (pt.r = 0 and pt.same_state)))
         or
         (pt.d is null
            and ((pt.r > 0 and pt.same_city and pt.same_state) or (pt.r = 0 and pt.same_state)))
       )
  loop
    if public.wh_quiet_now(t.tz) then continue; end if;
    -- Daily cap, only when the setting is above 0 (off since 2026-10-11).
    if v_cap > 0 and (select count(*) from public.wh_near_pushes n
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
  return jsonb_build_object('ok', true, 'id', v_row.id, 'expires_at', v_row.expires_at, 'pushed', v_pushed,
                            'placed', v_row.lat is not null, 'from_device', v_dev, 'max_miles', v_max);
end $$;

revoke all on function public.wh_post_request(text, date, text, text, text, text, double precision, double precision, int) from public, anon;
grant execute on function public.wh_post_request(text, date, text, text, text, text, double precision, double precision, int) to authenticated;

-- ── 6. Admin preview: who would hear a request posted from a ZIP ─────────────
-- Read only, no push. For testing the radius without posting as a client.
-- p_max_miles is the client's own limit (10, 25, 50) or null for none.
create or replace function public.admin_wh_near_preview(p_zip text, p_max_miles int default null) returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  z public.zip_centroids;
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  z := public.wh_zip_point(p_zip);
  if z.zip is null then return jsonb_build_object('ok', false, 'code', 'no_zip'); end if;
  return jsonb_build_object('ok', true, 'zip', z.zip, 'city', z.city, 'state', z.state, 'max_miles', p_max_miles,
    'techs', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'name', x.name, 'city', x.city, 'state', public.wh_state(x.state, x.zip),
               'placed', pt.lat is not null,
               'miles', round(pt.d::numeric, 1),
               'radius', pt.r,
               'alerts', coalesce(p.near_alerts, true),
               'hears', (coalesce(p.near_alerts, true) and (
                 (pt.d is not null
                    and (p_max_miles is null or pt.d <= p_max_miles)
                    and ((pt.r > 0 and pt.d <= pt.r) or (pt.r = 0 and pt.same_state)))
                 or
                 (pt.d is null
                    and ((pt.r > 0 and pt.same_city and pt.same_state) or (pt.r = 0 and pt.same_state)))))
             ) order by pt.d nulls last), '[]'::jsonb)
        from public.techs x
        left join public.wh_prefs p on p.person_key = public.wh_key(x.phone)
        cross join lateral (
          select q.lat, q.lng, public.wh_miles(z.lat, z.lng, q.lat, q.lng) as d,
                 coalesce(p.near_radius_miles, 25) as r,
                 lower(public.wh_state(x.state, x.zip)) = lower(z.state) as same_state,
                 lower(btrim(coalesce(x.city, ''))) = lower(z.city) as same_city
            from public.wh_point(x.lat, x.lng, x.zip, x.city, public.wh_state(x.state, x.zip)) q
        ) pt
       where public.wh_key(x.phone) is not null
    ));
end $$;

revoke all on function public.admin_wh_near_preview(text, int) from public, anon;
grant execute on function public.admin_wh_near_preview(text, int) to authenticated;

commit;

-- Checks (SQL editor, as the project owner):
--   select column_name from information_schema.columns
--    where table_name = 'wh_requests' and column_name in ('lat', 'lng', 'from_device');   -- three rows
--   select column_name from information_schema.columns
--    where table_name = 'wh_prefs' and column_name = 'near_radius_miles';                 -- one row
--   select count(*) from public.zip_centroids;      -- 0 until sql/zip-centroids-data.sql runs, then 40979
--   select public.wh_miles(33.63, -112.33, 33.53, -112.18);                               -- about 11
-- Then in the app as 2314 (Surprise, ZIP 85379): bell > How far. Post from
-- 0100 with a Glendale ZIP (85301, about 12 miles): a push at 25, none at 10.
