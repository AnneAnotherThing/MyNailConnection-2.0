-- ============================================================================
-- PHONE-AUTH STAGE D: the blocklist actually blocks phone clients (2026-07-24)
-- ============================================================================
-- The quiet blocklist identified the caller ONLY by the JWT email claim.
-- Phone-identity clients have no email claim, so v_caller was '' and the
-- check was skipped entirely: a blocked phone client saw every open slot
-- and could book. Both enforcement points now also match the caller's
-- verified phone (current_phone) against the stored entry via phone_digits,
-- so entries can be an email OR a bare-digits phone number. The app's
-- blocklist input accepts both as of the same date.
--
-- get_open_slots is the live enforcement point (create_booking validates
-- the requested slot against it); _booking_gate is patched for parity.
-- Bodies otherwise identical to blocklist-pause-migration.sql.
-- Requires Stage A (public.current_phone / phone_digits). Safe to re-run.
-- ============================================================================

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
  v_paused  boolean;
  v_buffer  int;
  v_dur     int;
  v_caller  text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_caller_ph text := coalesce(public.current_phone(), '');
begin
  select coalesce(booking_timezone, 'America/Phoenix'),
         coalesce(booking_enabled, false),
         coalesce(listing_paused, false),
         coalesce(booking_buffer_minutes, 0)
    into v_tz, v_enabled, v_paused, v_buffer
    from techs where id = p_tech_id;
  if not found or not v_enabled or v_paused then return; end if;

  if exists (
    select 1 from blocked_clients bc
     where bc.tech_id = p_tech_id
       and (   (v_caller <> ''    and bc.client_email = v_caller)
            or (v_caller_ph <> '' and public.phone_digits(bc.client_email) = v_caller_ph))
  ) then return; end if;

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
   where s > now()
     and not exists (
       select 1 from bookings b
        where b.tech_id = p_tech_id
          and b.status in ('pending','confirmed')
          and b.starts_at - make_interval(mins => v_buffer) < s + make_interval(mins => v_dur)
          and b.ends_at   + make_interval(mins => v_buffer) > s
     )
   order by s;
end $$;

create or replace function public._booking_gate(p_tech_id uuid) returns void
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_caller text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_caller_ph text := coalesce(public.current_phone(), '');
begin
  if exists (select 1 from techs where id = p_tech_id and coalesce(listing_paused, false)) then
    raise exception 'This tech is not taking bookings right now.';
  end if;
  if exists (
    select 1 from blocked_clients bc
     where bc.tech_id = p_tech_id
       and (   (v_caller <> ''    and bc.client_email = v_caller)
            or (v_caller_ph <> '' and public.phone_digits(bc.client_email) = v_caller_ph))
  ) then
    raise exception 'This tech is not taking bookings right now.';
  end if;
end $$;
