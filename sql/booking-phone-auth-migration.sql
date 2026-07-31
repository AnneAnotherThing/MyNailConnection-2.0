-- ========================================================================
-- Booking phone-auth migration (Path A)
--
-- Lets a not-signed-in client book by verifying their phone via Supabase
-- native Phone Auth (pointed at Twilio Verify in the dashboard). The client
-- ends up with a real, passwordless auth session, so the EXISTING
-- create_booking() path (which keys off auth.uid()) just works, no separate
-- guest-booking machinery needed.
--
-- What this migration does:
--   1. Adds bookings.client_phone so the tech can actually reach a
--      phone-verified client (email is null for phone-auth users).
--   2. Rebuilds create_booking() to also stamp the caller's phone onto the
--      booking. It reads the phone from the JWT (phone-auth users) and, for
--      email users, falls back to their saved profile phone. Everything else
--      about the function is unchanged.
--
-- Run this in the Supabase SQL editor. It is idempotent.
--
-- Dashboard config that pairs with this (do this too, separately):
--   Authentication -> Providers -> Phone: enable it, choose Twilio Verify,
--   paste Account SID + Auth Token + Verify Service SID (VA9fc79...).
--   Make sure new-user sign-ups are allowed so first-time bookers can be
--   created.
-- ========================================================================

alter table public.bookings add column if not exists client_phone text;


create or replace function public.create_booking(
  p_tech_id     uuid,
  p_service_id  uuid,
  p_starts_at   timestamptz,
  p_client_name text default null,
  p_note        text default null
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_client uuid := auth.uid();
  v_email  text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_phone  text := coalesce(auth.jwt() ->> 'phone', '');
  v_tz     text;
  v_auto   boolean;
  v_dur    int;
  v_ends   timestamptz;
  v_status text;
  v_id     uuid;
  v_open   boolean;
begin
  if v_client is null then
    raise exception 'Please verify your phone or sign in to book.';
  end if;

  -- Email users have their phone on their profile, not in the JWT. Fall back
  -- to it so the tech always has a number to reach the client on.
  if v_phone = '' and v_email <> '' then
    select coalesce(phone, '') into v_phone
      from users where lower(email) = v_email limit 1;
    v_phone := coalesce(v_phone, '');
  end if;

  select coalesce(booking_timezone, 'America/Phoenix'), coalesce(booking_auto_confirm, false)
    into v_tz, v_auto
    from techs where id = p_tech_id and coalesce(booking_enabled, false);
  if not found then
    raise exception 'This tech is not taking bookings right now.';
  end if;

  select duration_minutes into v_dur
    from tech_services
   where id = p_service_id and tech_id = p_tech_id and active;
  if not found then
    raise exception 'That service is no longer available.';
  end if;

  v_ends := p_starts_at + make_interval(mins => v_dur);

  -- Serialize per tech, then re-check the slot inside the lock.
  perform pg_advisory_xact_lock(hashtext('booking:' || p_tech_id::text));

  select exists (
    select 1
      from get_open_slots(p_tech_id, p_service_id,
                          (p_starts_at at time zone v_tz)::date) g
     where g.slot_start = p_starts_at
  ) into v_open;

  if not v_open then
    raise exception 'That time was just taken. Please pick another slot.';
  end if;

  v_status := case when v_auto then 'confirmed' else 'pending' end;

  insert into bookings
    (client_id, tech_id, service_id, starts_at, ends_at, status,
     client_name, client_email, client_phone, client_note,
     -- legacy 2.0 columns, filled for continuity with anything that
     -- still reads them (local wall-clock in the tech's timezone)
     booking_date, booking_time)
  values
    (v_client, p_tech_id, p_service_id, p_starts_at, v_ends, v_status,
     nullif(trim(p_client_name), ''), nullif(v_email, ''), nullif(trim(v_phone), ''),
     nullif(trim(p_note), ''),
     (p_starts_at at time zone v_tz)::date,
     to_char(p_starts_at at time zone v_tz, 'HH24:MI'))
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id, 'status', v_status,
    'starts_at', p_starts_at, 'ends_at', v_ends
  );
end $$;

grant execute on function public.create_booking(uuid, uuid, timestamptz, text, text) to authenticated;
