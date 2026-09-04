-- ========================================================================
-- STANDING APPOINTMENTS: close the phone-only authz hole + carry the
-- client's phone so reminders actually send            (2026-09-04)
-- ========================================================================
-- Found by the email-reliance sweep. Two defects, one file, because they
-- live in the same three objects:
--
-- 1. SECURITY: convert_to_standing authorized with
--        if lower(coalesce(b.tech_email,'')) <> v_email and not is_admin()
--    For a phone-only CALLER v_email = ''. For a phone-only TECH
--    b.tech_email coalesces to ''. '' <> '' is false, so the guard never
--    fired: ANY signed-in phone-only user could convert ANY phone-only
--    tech's booking into a standing series, materializing real confirmed
--    bookings onto her calendar. Post-cutover that is nearly everyone
--    against everyone. The fix authorizes by email OR verified phone
--    against the tech row, and fails CLOSED when neither matches.
--
-- 2. REMINDERS: standing_appointments had no client_phone column and
--    _materialize_standing inserted occurrences with client_email only.
--    For a phone-only client both identity fields on the materialized
--    booking were NULL, so push_identity() returned NULL and every
--    day-before / same-day reminder for the series was a silent no-op.
--    Same for the "You have a standing appointment" push on creation.
--
-- Run in the Supabase SQL editor (nwqnakoongrorbwnrqzc). Idempotent.
-- Requires: public.current_phone / phone_digits (phone-auth stage A),
--           public.push_identity (booking-reminders-observability).
-- ========================================================================


-- ── 1. The column ────────────────────────────────────────────────────────
alter table public.standing_appointments
  add column if not exists client_phone text;

-- Backfill from any booking already in each series.
update public.standing_appointments sa
   set client_phone = b.client_phone
  from public.bookings b
 where b.standing_id = sa.id
   and b.client_phone is not null
   and sa.client_phone is null;

-- And forward-fill materialized occurrences that were created without it.
update public.bookings b
   set client_phone = sa.client_phone
  from public.standing_appointments sa
 where b.standing_id = sa.id
   and sa.client_phone is not null
   and b.client_phone is null;


-- ── 2. _materialize_standing: carry client_phone onto occurrences ────────
-- Body identical to booking-standing-migration.sql except the insert.
create or replace function public._materialize_standing(
  p_standing_id uuid,
  p_target      int default 4
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  s record;
  v_tz     text;
  v_buffer int;
  v_dur    int;
  v_local  timestamp;      -- wall clock of the latest occurrence
  cand     timestamptz;
  cand_end timestamptz;
  fut      int;
  created  int := 0;
  skipped  int := 0;
  guard    int := 0;
begin
  select sa.*, coalesce(t.booking_timezone, 'America/Phoenix') as tz,
         coalesce(t.booking_buffer_minutes, 0) as buf
    into s
    from standing_appointments sa
    join techs t on t.id = sa.tech_id
   where sa.id = p_standing_id and sa.active;
  if not found then return jsonb_build_object('created', 0, 'skipped', 0); end if;
  v_tz := s.tz; v_buffer := s.buf;

  select coalesce(duration_minutes, 60) into v_dur
    from tech_services where id = s.service_id;
  if not found then v_dur := 60; end if;

  perform pg_advisory_xact_lock(hashtext('booking:' || s.tech_id::text));

  select count(*) into fut from bookings
   where standing_id = p_standing_id
     and status in ('pending','confirmed')
     and starts_at > now();

  -- start stepping from the latest occurrence on the books (or the anchor)
  select coalesce(max(starts_at), s.anchor_starts_at) at time zone v_tz
    into v_local
    from bookings
   where standing_id = p_standing_id;

  while fut < p_target and guard < 26 loop
    guard := guard + 1;
    v_local := v_local + (s.interval_weeks * interval '1 week');
    cand := v_local at time zone v_tz;
    if cand <= now() then continue; end if;
    cand_end := cand + make_interval(mins => v_dur);

    if exists (
         select 1 from tech_time_off o
          where o.tech_id = s.tech_id
            and (cand at time zone v_tz)::date between o.start_date and o.end_date
       )
       or exists (
         select 1 from bookings x
          where x.tech_id = s.tech_id
            and x.status in ('pending','confirmed')
            and x.starts_at - make_interval(mins => v_buffer) < cand_end
            and x.ends_at   + make_interval(mins => v_buffer) > cand
       )
    then
      skipped := skipped + 1;
    else
      insert into bookings
        (client_id, tech_id, service_id, starts_at, ends_at, status,
         client_name, client_email, client_phone, standing_id,
         booking_date, booking_time)
      values
        (s.client_id, s.tech_id, s.service_id, cand, cand_end, 'confirmed',
         s.client_name, s.client_email, s.client_phone, p_standing_id,
         (cand at time zone v_tz)::date,
         to_char(cand at time zone v_tz, 'HH24:MI'));
      created := created + 1;
      fut := fut + 1;
    end if;
  end loop;

  return jsonb_build_object('created', created, 'skipped', skipped);
end $$;


-- ── 3. convert_to_standing: real authorization + phone carried through ───
create or replace function public.convert_to_standing(
  p_booking_id     uuid,
  p_interval_weeks int
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_phone text := coalesce(public.current_phone(), '');
  b record;
  v_standing uuid;
  r jsonb;
begin
  if p_interval_weeks not between 1 and 8 then
    raise exception 'Interval must be between 1 and 8 weeks.';
  end if;

  select b2.id, b2.client_id, b2.tech_id, b2.service_id, b2.starts_at,
         b2.status, b2.client_name, b2.client_email, b2.client_phone,
         b2.standing_id,
         t.email as tech_email, t.phone as tech_phone, t.name as tech_name
    into b
    from bookings b2
    join techs t on t.id = b2.tech_id
   where b2.id = p_booking_id;
  if not found then raise exception 'Appointment not found.'; end if;

  -- The caller must positively match the tech row (email or verified
  -- phone) or be admin. The old check compared coalesced-to-'' emails,
  -- which PASSED when both sides were phone-only. Fail closed instead.
  if not (
       (v_email <> '' and lower(coalesce(b.tech_email, '')) = v_email)
    or (v_phone <> '' and public.phone_digits(b.tech_phone) = v_phone)
    or public.is_admin()
  ) then
    raise exception 'Only the tech can make an appointment standing.';
  end if;

  if b.status not in ('pending', 'confirmed') then
    raise exception 'Only upcoming appointments can become standing.';
  end if;
  if b.standing_id is not null then
    raise exception 'This appointment is already part of a standing series.';
  end if;

  insert into standing_appointments
    (tech_id, client_id, service_id, interval_weeks, anchor_starts_at,
     client_email, client_name, client_phone)
  values
    (b.tech_id, b.client_id, b.service_id, p_interval_weeks, b.starts_at,
     b.client_email, b.client_name, b.client_phone)
  returning id into v_standing;

  update bookings set standing_id = v_standing where id = p_booking_id;

  r := public._materialize_standing(v_standing, 4);

  -- tell the client (best effort) — addressed by email OR phone now
  begin
    perform public._booking_push(
      public.push_identity(b.client_email, b.client_phone),
      'You have a standing appointment 💅',
      coalesce(b.tech_name, 'Your tech') || ' set you up every ' ||
        case when p_interval_weeks = 1 then 'week' else p_interval_weeks || ' weeks' end ||
        ' at the same time. See them all in My Appointments.',
      'standing-' || v_standing);
  exception when others then null;
  end;

  return jsonb_build_object('standing_id', v_standing) || r;
end $$;

grant execute on function public.convert_to_standing(uuid, int) to authenticated;


-- ── VERIFY ──────────────────────────────────────────────────────────────
-- All three must say present/carried:
select
  case when prosrc like '%phone_digits(b.tech_phone)%' then 'authz phone leg present' else 'MISSING authz phone leg' end as convert_authz,
  case when prosrc like '%push_identity(b.client_email, b.client_phone)%' then 'push phone-aware' else 'MISSING push identity' end as convert_push
  from pg_proc where proname = 'convert_to_standing' and pronamespace = 'public'::regnamespace;
select
  case when prosrc like '%s.client_phone%' then 'occurrences carry client_phone' else 'MISSING client_phone carry' end as materialize
  from pg_proc where proname = '_materialize_standing' and pronamespace = 'public'::regnamespace;
select count(*) as standing_rows_still_missing_phone
  from public.standing_appointments
 where client_phone is null and client_email is null;
