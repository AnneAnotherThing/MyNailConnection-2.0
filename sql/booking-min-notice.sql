-- ========================================================================
-- MINIMUM NOTICE FOR BOOKINGS + get_open_slots v4  (2026-08-03, rev 2)
-- ========================================================================
-- REV 2 IS A HEAL: rev 1 of this file was built from the tier-1 version
-- of get_open_slots and silently DROPPED stage D's blocklist and
-- listing_paused checks. This rev is the union of every prior version:
--
--   tier 1   : buffer minutes, time off, 30-min grid
--   stage D  : blocklist (email OR caller's verified phone), pause switch
--   min-notice: techs.booking_min_notice_hours (this feature)
--
-- If you ran rev 1, RUN THIS AGAIN, it restores the blocklist.
-- Run in the Supabase SQL editor. Idempotent, safe to re-run.
-- ========================================================================

alter table public.techs add column if not exists booking_min_notice_hours int not null default 0
  check (booking_min_notice_hours between 0 and 72);

create or replace function public.get_open_slots(
  p_tech_id    uuid,
  p_service_id uuid,
  p_day        date
) returns table (slot_start timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_tz        text;
  v_enabled   boolean;
  v_paused    boolean;
  v_buffer    int;
  v_notice    int;
  v_dur       int;
  v_caller    text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_caller_ph text := coalesce(public.current_phone(), '');
begin
  select coalesce(booking_timezone, 'America/Phoenix'),
         coalesce(booking_enabled, false),
         coalesce(listing_paused, false),
         coalesce(booking_buffer_minutes, 0),
         coalesce(booking_min_notice_hours, 0)
    into v_tz, v_enabled, v_paused, v_buffer, v_notice
    from techs where id = p_tech_id;
  if not found or not v_enabled or v_paused then return; end if;

  -- Blocklist (stage D): a blocked caller sees no openings, ever, and is
  -- never told. Matches stored email or the caller's verified phone.
  if exists (
    select 1 from blocked_clients bc
     where bc.tech_id = p_tech_id
       and (   (v_caller <> ''    and bc.client_email = v_caller)
            or (v_caller_ph <> '' and public.phone_digits(bc.client_email) = v_caller_ph))
  ) then return; end if;

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
   -- min-notice: the earliest bookable moment is now + the tech's floor.
   -- With notice 0 this is identical to the old `s > now()`.
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

-- Sanity: confirm the column exists and the function carries all gates.
-- select booking_min_notice_hours from public.techs limit 3;
-- select prosrc like '%blocked_clients%' as has_blocklist,
--        prosrc like '%listing_paused%'  as has_pause,
--        prosrc like '%booking_min_notice_hours%' as has_notice
--   from pg_proc where proname = 'get_open_slots';
