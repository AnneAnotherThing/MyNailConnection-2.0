-- ============================================================================
-- gate-manual-booking.sql — manual bookings become a paid feature
--
-- Anne, 2026-08-23: "i was able to manually book someone - but i didn't have
-- booking set up." She could, and so could every free tech.
--
-- tech_create_booking checked ONE thing: is this your tech row. It never asked
-- whether the tech could actually be booked. So a tech who never subscribed
-- could run her entire book through MNC — enter every client by hand, keep
-- private notes on each one, and have MNC send those clients automatic
-- reminders. The only thing she could not do was let clients book themselves.
--
-- That is not really a revenue hole; it is a HONESTY hole. The subscribe sheet
-- sells "Private notes on every client" and "Automatic reminders, so fewer
-- no-shows" as reasons to pay. A tech who has been using both free for a month
-- reaches the paywall and reads a list of things she already has, which is the
-- version of a paywall that feels arbitrary. Anne chose to gate rather than
-- rewrite the pitch: one product, one price, and the sheet stays true.
--
-- The gate is public.tech_is_bookable(), the SAME function behind the public
-- Book button and the is_bookable computed column — deliberately, so manual
-- and inbound booking can never disagree about whether a tech is live. It
-- already accounts for the paywall being off entirely (everyone bookable),
-- comped techs, and the 3-day renewal grace, so none of that is re-implemented
-- here and none of it can drift.
--
-- Client side pairs with this: the "+ Add appointment" button opens the
-- subscribe sheet instead of the form when she is not bookable. This function
-- is the enforcement; the button is the explanation.
--
-- Safe to re-run. Run in: Supabase dashboard → nwqnakoongrorbwnrqzc → SQL editor.
-- ============================================================================

begin;

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

  -- ── The gate (2026-08-23) ─────────────────────────────────────────────
  -- Same test as the public Book button, on purpose: one definition of
  -- "this tech is live", so the two write paths can never disagree.
  -- Admins are exempt so support can still fix a calendar by hand.
  if not (public.tech_is_bookable(p_tech_id) or public.is_admin()) then
    return jsonb_build_object('error', 'not_subscribed');
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

-- ============================================================================
-- DELIBERATELY NOT CHANGED: the reminder cron.
--
-- booking-reminders-observability.sql selects on booking status alone, so a
-- lapsed tech's EXISTING appointments still remind her clients. That is the
-- right behaviour: those clients made a real appointment and should be told
-- about it, the cost is a push, and a tier check inside the cron is a quiet
-- way to break reminders for a genuinely paid tech during the 3-day renewal
-- grace. With this gate in place she cannot create new ones anyway.
--
-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- 1. The gate exists:
--      select pg_get_functiondef('public.tech_create_booking(uuid,timestamptz,uuid,int,text,text,boolean)'::regprocedure)
--             like '%not_subscribed%' as gated;
--    Expect: gated = true
--
-- 2. Who this affects right now — free techs with booking turned on:
--      select name, subscription_tier, booking_enabled, is_bookable
--        from public.techs where booking_enabled is true;
--    A tech listed here with is_bookable = false can no longer add
--    appointments by hand. Expect that to be nobody, since going live already
--    requires being bookable.
--
-- 3. As a paid tech in the app, add an appointment. It should still work.
--    As a free tech, the button should open the subscribe sheet instead of
--    the form — and if it somehow reaches the server, the response is
--    {"error":"not_subscribed"}.
-- ============================================================================
