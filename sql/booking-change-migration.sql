-- ============================================================================
-- booking-change-migration.sql  (2026-09-20)
--
-- Change an existing appointment: cancel, reschedule, and (tech-only) mark
-- no-show. The bookings table already carried cancelled_by_client /
-- cancelled_by_tech / cancel_reason from the original schema; this wires the
-- functions and adds 'no_show' to the status set. Mirrors create_booking:
-- SECURITY DEFINER, slot re-validated under the same per-tech advisory lock,
-- auto-confirm re-applied, timezone honored, legacy booking_date/time kept.
--
-- Identity: the client is auth.uid() (bookings.client_id). The tech is matched
-- by reading auth.users for auth.uid() and comparing to the booking's tech row
-- (phone last-10 or email) -- the uid-based pattern from push-identity-by-uid,
-- so a phone-auth session whose token omits the phone claim still resolves.
--
-- Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc). Re-runnable.
-- ============================================================================

-- ── 0. Add 'no_show' to the status check ────────────────────────────────────
do $$
begin
  alter table public.bookings drop constraint if exists bookings_status_check;
  alter table public.bookings add constraint bookings_status_check
    check (status in ('pending','confirmed','declined',
                      'cancelled_by_client','cancelled_by_tech',
                      'completed','no_show'));
end $$;

-- ── 1. Who is the caller, relative to a booking? ────────────────────────────
-- Returns 'client', 'tech', or null. uid-based tech match (auth.users read by
-- auth.uid()), robust to phone-auth tokens that omit the phone claim.
create or replace function public.booking_caller_role(p_booking_id uuid)
returns text
language sql stable security definer set search_path = public, auth
as $$
  select case
    when exists (select 1 from public.bookings b
                  where b.id = p_booking_id and b.client_id = auth.uid())
      then 'client'
    when exists (
      select 1
      from public.bookings b
      join public.techs t   on t.id = b.tech_id
      join auth.users  u    on u.id = auth.uid()
      where b.id = p_booking_id
        and (
          (u.email is not null and t.email is not null
             and lower(u.email) = lower(t.email))
          or (u.phone is not null and t.phone is not null
             and nullif(right(regexp_replace(u.phone, '\D', '', 'g'), 10), '')
               = nullif(right(regexp_replace(t.phone, '\D', '', 'g'), 10), ''))
        )
    ) then 'tech'
    else null
  end;
$$;
revoke all on function public.booking_caller_role(uuid) from public, anon;
grant execute on function public.booking_caller_role(uuid) to authenticated;

-- ── 2. Cancel ───────────────────────────────────────────────────────────────
-- Either party may cancel. Records who and why. Only an open appointment
-- (pending/confirmed) can be cancelled; a finished/declined one is left alone.
-- Returns the info the app needs to notify the OTHER party.
create or replace function public.cancel_booking(
  p_booking_id uuid,
  p_reason     text default null
) returns jsonb
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_role   text := public.booking_caller_role(p_booking_id);
  v_new    text;
  v_b      public.bookings%rowtype;
  v_tech   record;
begin
  if v_role is null then
    raise exception 'You can only change your own appointment.';
  end if;

  select * into v_b from public.bookings where id = p_booking_id;
  if not found then
    raise exception 'That appointment no longer exists.';
  end if;
  if v_b.status not in ('pending','confirmed') then
    raise exception 'That appointment can no longer be cancelled.';
  end if;

  v_new := case when v_role = 'client' then 'cancelled_by_client'
                else 'cancelled_by_tech' end;

  update public.bookings
     set status        = v_new,
         cancel_reason = nullif(trim(p_reason), '')
   where id = p_booking_id
   returning * into v_b;

  select t.name as tech_name,
         coalesce(t.email, t.phone) as tech_key
    into v_tech
    from public.techs t where t.id = v_b.tech_id;

  return jsonb_build_object(
    'id',            v_b.id,
    'status',        v_b.status,
    'cancelled_by',  v_role,
    'tech_id',       v_b.tech_id,
    'tech_name',     v_tech.tech_name,
    'tech_key',      lower(coalesce(v_tech.tech_key, '')),
    'client_key',    lower(coalesce(v_b.client_email, '')),
    'client_name',   v_b.client_name,
    'starts_at',     v_b.starts_at
  );
end $$;
revoke all on function public.cancel_booking(uuid, text) from public, anon;
grant execute on function public.cancel_booking(uuid, text) to authenticated;

-- ── 3. Reschedule ───────────────────────────────────────────────────────────
-- Move an open appointment to a new open slot for the SAME tech + service.
-- Re-validates the slot under the per-tech lock (excluding this booking so it
-- doesn't block its own move), re-applies auto-confirm, keeps the legacy
-- wall-clock columns. Either party may do it. Returns notify info.
create or replace function public.reschedule_booking(
  p_booking_id uuid,
  p_new_start  timestamptz
) returns jsonb
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_role   text := public.booking_caller_role(p_booking_id);
  v_b      public.bookings%rowtype;
  v_tz     text;
  v_auto   boolean;
  v_dur    int;
  v_ends   timestamptz;
  v_status text;
  v_open   boolean;
  v_tech   record;
begin
  if v_role is null then
    raise exception 'You can only change your own appointment.';
  end if;

  select * into v_b from public.bookings where id = p_booking_id;
  if not found then
    raise exception 'That appointment no longer exists.';
  end if;
  if v_b.status not in ('pending','confirmed') then
    raise exception 'That appointment can no longer be changed.';
  end if;

  select coalesce(booking_timezone, 'America/Phoenix'),
         coalesce(booking_auto_confirm, false)
    into v_tz, v_auto
    from public.techs
   where id = v_b.tech_id and coalesce(booking_enabled, false);
  if not found then
    raise exception 'This tech is not taking bookings right now.';
  end if;

  select duration_minutes into v_dur
    from public.tech_services
   where id = v_b.service_id and tech_id = v_b.tech_id and active;
  if not found then
    raise exception 'That service is no longer available.';
  end if;

  v_ends := p_new_start + make_interval(mins => v_dur);

  perform pg_advisory_xact_lock(hashtext('booking:' || v_b.tech_id::text));

  -- Free this booking from the conflict set while we test the new slot, so a
  -- small shift that overlaps its own old time still reads as open.
  update public.bookings set status = 'declined' where id = p_booking_id;

  select exists (
    select 1
      from public.get_open_slots(v_b.tech_id, v_b.service_id,
                                (p_new_start at time zone v_tz)::date) g
     where g.slot_start = p_new_start
  ) into v_open;

  if not v_open then
    -- restore and refuse
    update public.bookings set status = v_b.status where id = p_booking_id;
    raise exception 'That time is not open. Please pick another slot.';
  end if;

  v_status := case when v_auto then 'confirmed' else 'pending' end;

  update public.bookings
     set starts_at     = p_new_start,
         ends_at       = v_ends,
         status        = v_status,
         booking_date  = (p_new_start at time zone v_tz)::date,
         booking_time  = to_char(p_new_start at time zone v_tz, 'HH24:MI')
   where id = p_booking_id
   returning * into v_b;

  select t.name as tech_name,
         coalesce(t.email, t.phone) as tech_key
    into v_tech
    from public.techs t where t.id = v_b.tech_id;

  return jsonb_build_object(
    'id',          v_b.id,
    'status',      v_b.status,
    'moved_by',    v_role,
    'tech_id',     v_b.tech_id,
    'tech_name',   v_tech.tech_name,
    'tech_key',    lower(coalesce(v_tech.tech_key, '')),
    'client_key',  lower(coalesce(v_b.client_email, '')),
    'client_name', v_b.client_name,
    'starts_at',   v_b.starts_at,
    'ends_at',     v_b.ends_at
  );
end $$;
revoke all on function public.reschedule_booking(uuid, timestamptz) from public, anon;
grant execute on function public.reschedule_booking(uuid, timestamptz) to authenticated;

-- ── 4. Mark no-show (tech only) ─────────────────────────────────────────────
create or replace function public.mark_booking_no_show(p_booking_id uuid)
returns jsonb
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_role text := public.booking_caller_role(p_booking_id);
  v_b    public.bookings%rowtype;
begin
  if v_role <> 'tech' then
    raise exception 'Only the tech can mark a no-show.';
  end if;
  select * into v_b from public.bookings where id = p_booking_id;
  if not found then raise exception 'That appointment no longer exists.'; end if;
  if v_b.status not in ('pending','confirmed') then
    raise exception 'Only an upcoming appointment can be marked no-show.';
  end if;
  update public.bookings set status = 'no_show' where id = p_booking_id
    returning * into v_b;
  return jsonb_build_object('id', v_b.id, 'status', v_b.status);
end $$;
revoke all on function public.mark_booking_no_show(uuid) from public, anon;
grant execute on function public.mark_booking_no_show(uuid) to authenticated;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conrelid='public.bookings'::regclass and conname='bookings_status_check';
-- A client cancels their own booking:
--   select public.cancel_booking('<booking-uuid>', 'Something came up');
-- Reschedule (new slot must be open per get_open_slots):
--   select public.reschedule_booking('<booking-uuid>', '2026-09-22 15:00-07');
