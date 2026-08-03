-- ========================================================================
-- MINIMUM NOTICE FOR BOOKINGS (2026-08-03, per Anne in the launch lap)
-- ========================================================================
-- "If they have auto-confirm on, we need to give them an option to not
-- book up to X hours out." Clients can no longer grab a slot starting
-- sooner than X hours from now. The setting lives on the tech row and
-- is enforced server-side in get_open_slots, so no client can bypass it.
-- 0 (default) = same-day, up-to-the-minute booking allowed.
--
-- Run in the Supabase SQL editor. Idempotent, safe to re-run.
-- ========================================================================

alter table public.techs add column if not exists booking_min_notice_hours int not null default 0
  check (booking_min_notice_hours between 0 and 72);

-- get_open_slots v3: min-notice aware (v2 shipped in booking-tier1).
create or replace function public.get_open_slots(
  p_tech_id    uuid,
  p_service_id uuid,
  p_day        date
) returns table (slot_start timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_tz      text;
  v_enabled boolean;
  v_buffer  int;
  v_notice  int;
  v_dur     int;
begin
  select coalesce(booking_timezone, 'America/Phoenix'),
         coalesce(booking_enabled, false),
         coalesce(booking_buffer_minutes, 0),
         coalesce(booking_min_notice_hours, 0)
    into v_tz, v_enabled, v_buffer, v_notice
    from techs where id = p_tech_id;
  if not found or not v_enabled then return; end if;

  -- Whole day blocked? Nothing to offer.
  if exists (
    select 1 from tech_time_off t
     where t.tech_id = p_tech_id
       and p_day between t.start_date and t.end_date
  ) then return; end if;

  select duration_minutes into v_dur
    from tech_services
   where id = p_service_id and tech_id = p_tech_id and active;
  if not found then return; end if;

  return query
  with windows as (
    select a.start_time, a.end_time
      from tech_availability a
     where a.tech_id = p_tech_id
       and a.day_of_week = extract(dow from p_day)::smallint
  ),
  grid as (
    select gs as slot_local
      from windows w
     cross join lateral generate_series(
       p_day + w.start_time,
       p_day + w.end_time - make_interval(mins => v_dur),
       interval '30 minutes'
     ) gs
  ),
  stamped as (
    select (g.slot_local at time zone v_tz) as s from grid g
  )
  select s
    from stamped
   -- v3: the earliest bookable moment is now + the tech's minimum
   -- notice. With notice 0 this is identical to v2's `s > now()`.
   where s > now() + make_interval(hours => v_notice)
     and not exists (
       select 1 from bookings b
        where b.tech_id = p_tech_id
          and b.status in ('pending','confirmed')
          -- buffer padding on both sides of existing appointments
          and b.starts_at - make_interval(mins => v_buffer) < s + make_interval(mins => v_dur)
          and b.ends_at   + make_interval(mins => v_buffer) > s
     )
   order by s;
end $$;

grant execute on function public.get_open_slots(uuid, uuid, date) to anon, authenticated;

-- Sanity: confirm the column + function version.
-- select booking_min_notice_hours from public.techs limit 3;
