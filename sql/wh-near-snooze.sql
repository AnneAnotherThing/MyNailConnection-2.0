-- MNC What's happening: no daily cap on near-me pushes, plus "Snooze for today"
-- (Anne, 2026-10-11: "if there's someone in Surprise and all the Surprise
-- techs get it, and the second, and the third, NO ONE will get any subsequent").
--
-- What changes:
--   1. near_push_daily_cap becomes 0, and wh_post_request only applies the cap
--      when it is above 0. Every tech in the city hears every request, outside
--      quiet hours, unless she snoozed.
--   2. wh_prefs gets near_snoozed_until. wh_snooze_near(tz, on) sets it to the
--      end of her local day, or clears it. wh_my_prefs reports it.
--   3. The post loop skips a tech while her snooze is running.
--
-- Same functions as in sql/build2-whats-happening.sql, copied here to run alone.
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query.
-- Proof this is the new copy: wh_post_request says "v_cap > 0 and".

begin;

insert into public.wh_settings (key, value) values ('near_push_daily_cap', '0')
on conflict (key) do update set value = excluded.value;

alter table public.wh_prefs add column if not exists near_snoozed_until timestamptz;

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

  -- Near-me pushes: same city and state, switch on, not snoozed, not blocked,
  -- not in quiet hours. While testing, admins only.
  for t in
    select x.id, x.email, x.phone, x.name,
           coalesce(x.avail_reminder_tz, x.booking_timezone, 'America/Phoenix') as tz
      from public.techs x
     where lower(btrim(coalesce(x.city, ''))) = lower(btrim(v_row.city))
       and lower(public.wh_state(x.state, x.zip)) = lower(btrim(v_row.state))
       and public.wh_key(x.phone) is not null
       and public.wh_key(x.phone) <> me
       and coalesce((select p.near_alerts from public.wh_prefs p where p.person_key = public.wh_key(x.phone)), true)
       and coalesce((select p.near_snoozed_until from public.wh_prefs p where p.person_key = public.wh_key(x.phone)), now() - interval '1 second') <= now()
       and not public.wh_blocked(me, public.wh_key(x.phone))
       and (not v_admin_only or exists (
             select 1 from public.users au
              where public.wh_key(au.phone) = public.wh_key(x.phone)
                and (coalesce(au.admin, false) or lower(coalesce(au.role, '')) = 'admin')))
  loop
    if public.wh_quiet_now(t.tz) then continue; end if;
    -- Daily cap, only when the setting is above 0. Anne turned it off on
    -- 2026-10-11: with a cap, every tech in a city burns her three on the same
    -- three requests and the fourth reaches nobody. Snooze is the valve now.
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
  return jsonb_build_object('ok', true, 'id', v_row.id, 'expires_at', v_row.expires_at, 'pushed', v_pushed);
end $$;

create or replace function public.wh_my_prefs() returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'reply_alerts', coalesce((select reply_alerts from public.wh_prefs where person_key = public.wh_me_key()), true),
    'near_alerts',  coalesce((select near_alerts  from public.wh_prefs where person_key = public.wh_me_key()), true),
    'near_snoozed_until', (select near_snoozed_until from public.wh_prefs
                            where person_key = public.wh_me_key() and near_snoozed_until > now())
  );
$$;

create or replace function public.wh_snooze_near(p_tz text default 'America/Phoenix', p_on boolean default true) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me   text := public.wh_me_key();
  v_tz text := coalesce(nullif(btrim(p_tz), ''), 'America/Phoenix');
  v_until timestamptz;
begin
  if me is null then return jsonb_build_object('ok', false, 'code', 'sign_in'); end if;
  begin
    v_until := (date_trunc('day', now() at time zone v_tz) + interval '1 day') at time zone v_tz;
  exception when others then
    v_until := (date_trunc('day', now() at time zone 'America/Phoenix') + interval '1 day') at time zone 'America/Phoenix';
  end;
  insert into public.wh_prefs (person_key) values (me) on conflict (person_key) do nothing;
  update public.wh_prefs
     set near_snoozed_until = case when coalesce(p_on, true) then v_until else null end,
         updated_at = now()
   where person_key = me;
  perform public.wh_log('near_snooze', case when coalesce(p_on, true) then 'on' else 'off' end);
  return public.wh_my_prefs() || jsonb_build_object('ok', true);
end $$;

revoke all on function public.wh_snooze_near(text, boolean) from public, anon;
grant execute on function public.wh_snooze_near(text, boolean) to authenticated;

commit;

-- Checks (SQL editor, as the project owner):
--   select value from public.wh_settings where key = 'near_push_daily_cap';   -- 0
--   select column_name from information_schema.columns
--    where table_name = 'wh_prefs' and column_name = 'near_snoozed_until';     -- one row
-- Then in the app as 2314: bell > Snooze for today. The sheet should say
-- "Snoozed for today" and a request posted as 0100 should push nothing to 2314.
