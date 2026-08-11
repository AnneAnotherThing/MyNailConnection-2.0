-- ============================================================================
-- tech_create_booking: tech-entered appointments (2026-08-11, Anne:
-- "i don't see a way to 'take a booking' for the tech to enter someone
-- themselves")
--
-- Walk-ins, phone clients, Instagram DMs — the tech types the appointment in
-- herself and it lands on her calendar as confirmed. The bookings insert
-- policy is deliberately client-only (client_id = auth.uid()), so this is a
-- SECURITY DEFINER RPC like create_booking: it verifies the caller owns the
-- tech row (email OR phone identity, or admin), then inserts with client_id
-- NULL — there is no client account behind a manual entry; the client_name /
-- client_phone text fields carry who it is.
--
-- Unlike create_booking it does NOT require booking_enabled or an open slot:
-- the tech is the authority on her own calendar. It takes the SAME per-tech
-- advisory lock key as create_booking so client bookings and manual entries
-- serialize against each other, and it warns on overlaps — the app confirms
-- with her, then retries with p_force = true to book anyway.
--
-- Requires phone-auth Stage A helpers (current_email / current_phone /
-- phone_digits) and is_admin(). Runs in the Supabase SQL editor. Safe to
-- re-run.
-- ============================================================================

begin;

-- Manual entries have no client account behind them.
alter table public.bookings alter column client_id drop not null;

create or replace function public.tech_create_booking(
  p_tech_id          uuid,
  p_starts_at        timestamptz,
  p_service_id       uuid default null,
  p_duration_minutes int  default null,
  p_client_name      text default null,
  p_client_phone     text default null,
  p_force            boolean default false
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_tz   text;
  v_dur  int;
  v_ends timestamptz;
  v_id   uuid;
begin
  select coalesce(booking_timezone, 'America/Phoenix') into v_tz
    from techs
   where id = p_tech_id
     and (lower(email) = public.current_email()
          or public.phone_digits(phone) = public.current_phone()
          or public.is_admin());
  if not found then
    return jsonb_build_object('error', 'not_your_tech');
  end if;
  if p_starts_at is null then
    return jsonb_build_object('error', 'no_time');
  end if;

  select duration_minutes into v_dur
    from tech_services
   where id = p_service_id and tech_id = p_tech_id;
  v_dur  := coalesce(v_dur, p_duration_minutes, 60);
  v_ends := p_starts_at + make_interval(mins => v_dur);

  -- Same lock key as create_booking so the two write paths serialize.
  perform pg_advisory_xact_lock(hashtext('booking:' || p_tech_id::text));

  if not p_force and exists (
    select 1 from bookings b
     where b.tech_id = p_tech_id
       and b.status in ('pending', 'confirmed')
       and b.starts_at < v_ends
       and coalesce(b.ends_at, b.starts_at + interval '60 minutes') > p_starts_at
  ) then
    return jsonb_build_object('error', 'overlap');
  end if;

  insert into bookings
    (client_id, tech_id, service_id, starts_at, ends_at, status,
     client_name, client_phone,
     -- legacy 2.0 columns, filled for continuity (local wall-clock in
     -- the tech's timezone), same as create_booking
     booking_date, booking_time)
  values
    (null, p_tech_id, p_service_id, p_starts_at, v_ends, 'confirmed',
     nullif(trim(p_client_name), ''), nullif(trim(p_client_phone), ''),
     (p_starts_at at time zone v_tz)::date,
     to_char(p_starts_at at time zone v_tz, 'HH24:MI'))
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'starts_at', p_starts_at, 'ends_at', v_ends);
end $$;

grant execute on function public.tech_create_booking(uuid, timestamptz, uuid, int, text, text, boolean) to authenticated;

commit;
