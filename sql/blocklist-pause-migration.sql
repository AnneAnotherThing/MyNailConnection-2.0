-- ========================================================================
-- MNC 3.0 Blocklist + "Not taking new clients"  (2026-07-05)
-- ========================================================================
-- Run in Supabase -> SQL Editor AFTER booking-standing-migration.sql.
-- Safe to re-run.
--
-- 1. techs.listing_paused: the one-and-only off switch. Hides the tech's
--    photos from the Gallery (app-side), replaces contact buttons with a
--    "taking a break" note, and refuses bookings server-side. Account
--    and portfolio stay intact.
-- 2. blocked_clients: per-tech quiet blocklist. A blocked client is
--    never told, they simply see no open slots for that tech, ever, and
--    any direct create_booking attempt gets the generic "not taking
--    bookings" message. Table is NOT publicly readable (privacy), the
--    enforcement lives inside the SECURITY DEFINER functions.
-- ========================================================================


-- ── 1. Pause switch ──────────────────────────────────────────────────────

alter table public.techs add column if not exists listing_paused boolean not null default false;


-- ── 2. Blocklist ─────────────────────────────────────────────────────────

create table if not exists public.blocked_clients (
  id           uuid primary key default gen_random_uuid(),
  tech_id      uuid not null references public.techs(id) on delete cascade,
  client_email text not null check (client_email = lower(btrim(client_email))),
  note         text,
  created_at   timestamptz not null default now(),
  unique (tech_id, client_email)
);

alter table public.blocked_clients enable row level security;

drop policy if exists blk_select_self on public.blocked_clients;
drop policy if exists blk_insert_self on public.blocked_clients;
drop policy if exists blk_delete_self on public.blocked_clients;

create policy blk_select_self on public.blocked_clients
  for select to authenticated
  using (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

create policy blk_insert_self on public.blocked_clients
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

create policy blk_delete_self on public.blocked_clients
  for delete to authenticated
  using (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );


-- ── 3. get_open_slots v3: pause + blocklist aware ────────────────────────
-- A paused tech and a blocked caller both get an empty slot list, which
-- reads as "no openings", quiet by design.

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
begin
  select coalesce(booking_timezone, 'America/Phoenix'),
         coalesce(booking_enabled, false),
         coalesce(listing_paused, false),
         coalesce(booking_buffer_minutes, 0)
    into v_tz, v_enabled, v_paused, v_buffer
    from techs where id = p_tech_id;
  if not found or not v_enabled or v_paused then return; end if;

  if v_caller <> '' and exists (
    select 1 from blocked_clients bc
     where bc.tech_id = p_tech_id and bc.client_email = v_caller
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

grant execute on function public.get_open_slots(uuid, uuid, date) to anon, authenticated;


-- ── 4. create_booking guard (pause + blocklist) ──────────────────────────
-- create_booking validates the slot against get_open_slots, which now
-- returns empty for paused/blocked, so the "just taken" error would fire
-- anyway. This adds the earlier, cleaner message on the direct path.

create or replace function public._booking_gate(p_tech_id uuid) returns void
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_caller text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if exists (select 1 from techs where id = p_tech_id and coalesce(listing_paused, false)) then
    raise exception 'This tech is not taking bookings right now.';
  end if;
  if v_caller <> '' and exists (
    select 1 from blocked_clients bc
     where bc.tech_id = p_tech_id and bc.client_email = v_caller
  ) then
    raise exception 'This tech is not taking bookings right now.';
  end if;
end $$;

-- create_booking v3: same as v2 plus the gate call right after auth.
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
  v_tz     text;
  v_auto   boolean;
  v_dur    int;
  v_ends   timestamptz;
  v_status text;
  v_id     uuid;
  v_open   boolean;
begin
  if v_client is null then
    raise exception 'Please sign in to book.';
  end if;

  -- 3.0 blocklist/pause gate (friendly message on the direct path;
  -- get_open_slots returning empty already fails closed regardless)
  perform public._booking_gate(p_tech_id);

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
     client_name, client_email, client_note,
     -- legacy 2.0 columns, filled for continuity with anything that
     -- still reads them (local wall-clock in the tech's timezone)
     booking_date, booking_time)
  values
    (v_client, p_tech_id, p_service_id, p_starts_at, v_ends, v_status,
     nullif(trim(p_client_name), ''), nullif(v_email, ''), nullif(trim(p_note), ''),
     (p_starts_at at time zone v_tz)::date,
     to_char(p_starts_at at time zone v_tz, 'HH24:MI'))
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id, 'status', v_status,
    'starts_at', p_starts_at, 'ends_at', v_ends
  );
end $$;

grant execute on function public.create_booking(uuid, uuid, timestamptz, text, text) to authenticated;
