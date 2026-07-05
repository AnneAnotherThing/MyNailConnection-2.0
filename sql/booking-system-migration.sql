-- ========================================================================
-- MNC 3.0 Booking System Migration  (2026-07-04)
-- ========================================================================
-- Run in Supabase -> SQL Editor. Safe to re-run, everything is
-- IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS.
--
-- The 3.0 pivot: free booking is the daily-use hook, photos are the
-- self-paced marketing layer. This migration adds:
--
--   * tech_services       what a tech offers (name, duration, price)
--   * tech_availability   weekly recurring windows, times are LOCAL
--                         wall-clock in the tech's booking_timezone
--   * bookings            already exists with RLS (client_id uuid =
--                         auth.uid, tech_id uuid = techs.id). We add
--                         the scheduling columns it never got.
--   * techs               + booking_enabled, booking_auto_confirm,
--                         booking_timezone
--   * get_open_slots()    server-side slot generation, timezone-aware,
--                         excludes past times and overlapping bookings
--   * create_booking()    SECURITY DEFINER, takes a per-tech advisory
--                         lock so two clients grabbing the same slot
--                         can't double-book (same rationale as the
--                         photo-autosave RPCs: atomicity beats
--                         read-modify-write from the client)
--
-- Statuses: pending -> confirmed | declined
--           pending/confirmed -> cancelled_by_client | cancelled_by_tech
--           confirmed -> completed (cosmetic, set by tech, optional)
--
-- Free-tier boundary (per V3-PLAN.md): reminders are push + email only,
-- no SMS. Event pushes (new request / confirmed / declined / cancelled)
-- are sent from the app via the existing send-push edge function.
-- Day-before reminder needs pg_cron + an edge function, deferred.
-- ========================================================================


-- ── 1. techs: booking settings ──────────────────────────────────────────

alter table public.techs add column if not exists booking_enabled      boolean not null default false;
alter table public.techs add column if not exists booking_auto_confirm boolean not null default false;
alter table public.techs add column if not exists booking_timezone     text    not null default 'America/Phoenix';


-- ── 2. tech_services ────────────────────────────────────────────────────

create table if not exists public.tech_services (
  id               uuid primary key default gen_random_uuid(),
  tech_id          uuid not null references public.techs(id) on delete cascade,
  name             text not null check (length(trim(name)) > 0),
  duration_minutes int  not null check (duration_minutes between 15 and 480),
  price            numeric(8,2),          -- null = "ask", shown as text in UI
  description      text,
  active           boolean not null default true,
  sort_order       int not null default 0,
  created_at       timestamptz not null default now()
);

create index if not exists idx_tech_services_tech on public.tech_services(tech_id);

alter table public.tech_services enable row level security;

drop policy if exists svc_select_all  on public.tech_services;
drop policy if exists svc_insert_self on public.tech_services;
drop policy if exists svc_update_self on public.tech_services;
drop policy if exists svc_delete_self on public.tech_services;

-- Anyone can see services (signed-out browsing shows the booking teaser)
create policy svc_select_all on public.tech_services
  for select using (true);

create policy svc_insert_self on public.tech_services
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

create policy svc_update_self on public.tech_services
  for update to authenticated
  using (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  )
  with check (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

create policy svc_delete_self on public.tech_services
  for delete to authenticated
  using (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );


-- ── 3. tech_availability, weekly recurring windows ──────────────────────
-- day_of_week: 0 = Sunday .. 6 = Saturday (matches extract(dow ...)).
-- start/end are wall-clock times in the tech's booking_timezone.

create table if not exists public.tech_availability (
  id          uuid primary key default gen_random_uuid(),
  tech_id     uuid not null references public.techs(id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  start_time  time not null,
  end_time    time not null,
  created_at  timestamptz not null default now(),
  check (end_time > start_time)
);

create index if not exists idx_tech_avail_tech on public.tech_availability(tech_id, day_of_week);

alter table public.tech_availability enable row level security;

drop policy if exists avail_select_all  on public.tech_availability;
drop policy if exists avail_insert_self on public.tech_availability;
drop policy if exists avail_update_self on public.tech_availability;
drop policy if exists avail_delete_self on public.tech_availability;

create policy avail_select_all on public.tech_availability
  for select using (true);

create policy avail_insert_self on public.tech_availability
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

create policy avail_update_self on public.tech_availability
  for update to authenticated
  using (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  )
  with check (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

create policy avail_delete_self on public.tech_availability
  for delete to authenticated
  using (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );


-- ── 4. bookings: add the scheduling columns ─────────────────────────────
-- Table + RLS already exist (rls-starter.sql / rls-fix.sql). Columns are
-- added defensively since the original column list predates sql/.

alter table public.bookings add column if not exists service_id    uuid references public.tech_services(id) on delete set null;
alter table public.bookings add column if not exists starts_at     timestamptz;
alter table public.bookings add column if not exists ends_at       timestamptz;
alter table public.bookings add column if not exists status        text not null default 'pending';
alter table public.bookings add column if not exists client_name   text;
alter table public.bookings add column if not exists client_email  text;
alter table public.bookings add column if not exists client_note   text;
alter table public.bookings add column if not exists cancel_reason text;
alter table public.bookings add column if not exists created_at    timestamptz not null default now();

-- 2.0 leftovers: the original hand-made bookings table has NOT NULL
-- booking_date / booking_time columns (discovered by the 2026-07-05
-- end-to-end test, insert failed on booking_date). create_booking now
-- fills both for continuity, and the NOT NULLs are dropped so the
-- legacy columns can retire gracefully.
alter table public.bookings alter column booking_date drop not null;
alter table public.bookings alter column booking_time drop not null;

-- Second 2.0 landmine (same e2e test): client_id had a foreign key to
-- public.users(id), but the RLS policies compare client_id to auth.uid().
-- Those are different id spaces, so inserts that satisfied the policy
-- violated the FK. Repoint the FK at auth.users. NOT VALID so any stray
-- legacy rows don't block the constraint; new rows are fully checked.
alter table public.bookings drop constraint if exists bookings_client_id_fkey;
alter table public.bookings add constraint bookings_client_id_fkey
  foreign key (client_id) references auth.users(id) on delete cascade
  not valid;

-- Third landmine: tech_id's FK pointed at nail_techs, the LEGACY table
-- that public.techs replaced. Repoint at techs.
alter table public.bookings drop constraint if exists bookings_tech_id_fkey;
alter table public.bookings add constraint bookings_tech_id_fkey
  foreign key (tech_id) references public.techs(id) on delete cascade
  not valid;

-- Status check constraint, added via DO block so re-runs don't error.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'bookings_status_check' and conrelid = 'public.bookings'::regclass
  ) then
    alter table public.bookings add constraint bookings_status_check
      check (status in ('pending','confirmed','declined',
                        'cancelled_by_client','cancelled_by_tech','completed'));
  end if;
end $$;

create index if not exists idx_bookings_tech_time   on public.bookings(tech_id, starts_at);
create index if not exists idx_bookings_client_time on public.bookings(client_id, starts_at);


-- ── 5. get_open_slots, server-side slot generation ──────────────────────
-- Returns bookable start times (timestamptz) for one tech + service on
-- one LOCAL calendar day. 30-minute grid within the tech's availability
-- windows; a slot must fit the whole service duration inside the window,
-- be in the future, and not overlap any pending/confirmed booking.
-- SECURITY DEFINER so it can see other clients' bookings (RLS hides
-- them) while only ever exposing derived free/busy, never who booked.

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
  v_dur     int;
begin
  select coalesce(booking_timezone, 'America/Phoenix'), coalesce(booking_enabled, false)
    into v_tz, v_enabled
    from techs where id = p_tech_id;
  if not found or not v_enabled then return; end if;

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
    -- local wall-clock slot starts, stepped on a 30-min grid, where the
    -- full service duration still fits inside the window
    select gs as slot_local
      from windows w
     cross join lateral generate_series(
       p_day + w.start_time,
       p_day + w.end_time - make_interval(mins => v_dur),
       interval '30 minutes'
     ) gs
  ),
  stamped as (
    -- interpret local wall time in the tech's timezone -> timestamptz
    select (g.slot_local at time zone v_tz) as s from grid g
  )
  select s
    from stamped
   where s > now()
     and not exists (
       select 1 from bookings b
        where b.tech_id = p_tech_id
          and b.status in ('pending','confirmed')
          and b.starts_at < s + make_interval(mins => v_dur)
          and b.ends_at   > s
     )
   order by s;
end $$;

grant execute on function public.get_open_slots(uuid, uuid, date) to anon, authenticated;


-- ── 6. create_booking, atomic, double-booking-proof ─────────────────────
-- Advisory xact lock per tech serializes concurrent booking attempts;
-- the slot is re-validated inside the lock, so "two clients tap the
-- same 2:00pm" resolves to one booking and one friendly error.

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


-- ========================================================================
-- VERIFICATION, run after:
--   select booking_enabled, booking_auto_confirm, booking_timezone
--     from techs limit 3;
--   select * from get_open_slots(null, null, current_date);  -- returns 0 rows, no error
-- ========================================================================
