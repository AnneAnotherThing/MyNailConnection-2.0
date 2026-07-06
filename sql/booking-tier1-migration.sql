-- ========================================================================
-- MNC 3.0 Booking Tier 1  (2026-07-05)
-- ========================================================================
-- Run in Supabase -> SQL Editor AFTER booking-system-migration.sql.
-- Safe to re-run.
--
-- Adds the three daily-driver-trust features:
--   1. tech_time_off      block dates (vacation, appointments off)
--   2. buffer time        techs.booking_buffer_minutes, breathing room
--                         around every appointment
--   3. reminders          pg_cron + pg_net push reminders, day-before
--                         and 3-hours-before, to client AND tech.
--                         Push only for now (MNC has no transactional
--                         email sender; revisit if one is added).
-- ========================================================================


-- ── 1. Time off ──────────────────────────────────────────────────────────

create table if not exists public.tech_time_off (
  id         uuid primary key default gen_random_uuid(),
  tech_id    uuid not null references public.techs(id) on delete cascade,
  start_date date not null,
  end_date   date not null,
  note       text,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create index if not exists idx_tech_time_off on public.tech_time_off(tech_id, start_date);

alter table public.tech_time_off enable row level security;

drop policy if exists toff_select_all  on public.tech_time_off;
drop policy if exists toff_insert_self on public.tech_time_off;
drop policy if exists toff_delete_self on public.tech_time_off;

-- Public read: the client booking UI grays out blocked days.
create policy toff_select_all on public.tech_time_off
  for select using (true);

create policy toff_insert_self on public.tech_time_off
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

create policy toff_delete_self on public.tech_time_off
  for delete to authenticated
  using (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );


-- ── 2. Buffer time ───────────────────────────────────────────────────────

alter table public.techs add column if not exists booking_buffer_minutes int not null default 0
  check (booking_buffer_minutes between 0 and 120);


-- ── 3. Reminder bookkeeping ──────────────────────────────────────────────

alter table public.bookings add column if not exists reminded_day_at  timestamptz;
alter table public.bookings add column if not exists reminded_soon_at timestamptz;


-- ── 4. get_open_slots v2: time off + buffer aware ────────────────────────

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
  v_dur     int;
begin
  select coalesce(booking_timezone, 'America/Phoenix'),
         coalesce(booking_enabled, false),
         coalesce(booking_buffer_minutes, 0)
    into v_tz, v_enabled, v_buffer
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
   where s > now()
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


-- ── 5. Reminders: pg_cron + pg_net -> send-push edge function ────────────
-- Runs every 15 minutes. A booking gets its day-before reminder the
-- first cron tick inside the 24h window (so a cron outage can't skip
-- anyone, only delay them), and a heads-up inside the 3h window.
-- Both client and tech are pushed; push_subscriptions is keyed by email.
-- The anon key is public by design (it ships in index.html), the edge
-- function accepts it, and RLS doesn't apply here (security definer).

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public._booking_push(
  p_user text, p_title text, p_body text, p_tag text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  k_url  text := 'https://ktiztunuifzbzwzyqrrq.supabase.co/functions/v1/send-push';
  k_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt0aXp0dW51aWZ6Ynp3enlxcnJxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3Njk3MDgsImV4cCI6MjA4OTM0NTcwOH0.QXhI1oO-v5Qs2XOlijjpRgM2pxDD6lkWxUQ6uW6HbtM';
begin
  if p_user is null or p_user = '' then return; end if;
  perform net.http_post(
    url := k_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', k_anon,
      'Authorization', 'Bearer ' || k_anon
    ),
    body := jsonb_build_object(
      'user_id', p_user, 'title', p_title, 'body', p_body,
      'url', '/app/', 'tag', p_tag
    )
  );
end $$;

create or replace function public.process_booking_reminders()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  rec record;
  v_when text;
  v_sent int := 0;
begin
  -- Day-before reminders (confirmed only; pending gets nudged too so the
  -- tech doesn't let a request rot into the appointment window)
  for rec in
    select b.id, b.status, b.client_email, b.client_name, b.starts_at,
           t.name as tech_name, t.email as tech_email,
           coalesce(t.booking_timezone, 'America/Phoenix') as tz,
           coalesce(s.name, 'appointment') as svc
      from bookings b
      join techs t on t.id = b.tech_id
      left join tech_services s on s.id = b.service_id
     where b.status in ('pending','confirmed')
       and b.reminded_day_at is null
       and b.starts_at > now()
       and b.starts_at <= now() + interval '24 hours'
  loop
    v_when := trim(to_char(rec.starts_at at time zone rec.tz, 'Dy Mon FMDD "at" FMHH12:MI PM'));
    if rec.status = 'confirmed' then
      v_sent := v_sent + 1;
      perform public._booking_push(rec.client_email, 'Appointment tomorrow 💅',
           rec.svc || ' with ' || coalesce(rec.tech_name, 'your tech') || ', ' || v_when || '.',
           'bk-day-' || rec.id);
      v_sent := v_sent + 1;
      perform public._booking_push(rec.tech_email, 'Tomorrow: ' || coalesce(rec.client_name, 'a client'),
           rec.svc || ', ' || v_when || '.',
           'bk-day-t-' || rec.id);
    else
      v_sent := v_sent + 1;
      perform public._booking_push(rec.tech_email, 'Request still waiting',
           coalesce(rec.client_name, 'A client') || ' asked for ' || v_when ||
           '. Confirm or decline before it arrives.',
           'bk-day-t-' || rec.id);
    end if;
    update bookings set reminded_day_at = now() where id = rec.id;
  end loop;

  -- Soon (3 hours) reminders, confirmed only
  for rec in
    select b.id, b.client_email, b.client_name, b.starts_at,
           t.name as tech_name, t.email as tech_email,
           coalesce(t.booking_timezone, 'America/Phoenix') as tz,
           coalesce(s.name, 'appointment') as svc
      from bookings b
      join techs t on t.id = b.tech_id
      left join tech_services s on s.id = b.service_id
     where b.status = 'confirmed'
       and b.reminded_soon_at is null
       and b.starts_at > now()
       and b.starts_at <= now() + interval '3 hours'
  loop
    v_when := trim(to_char(rec.starts_at at time zone rec.tz, 'FMHH12:MI PM'));
    v_sent := v_sent + 1;
    perform public._booking_push(rec.client_email, 'Today at ' || v_when || ' 💅',
         rec.svc || ' with ' || coalesce(rec.tech_name, 'your tech') || '. See you soon!',
         'bk-soon-' || rec.id);
    v_sent := v_sent + 1;
    perform public._booking_push(rec.tech_email, 'Up next: ' || coalesce(rec.client_name, 'a client'),
         rec.svc || ' at ' || v_when || '.',
         'bk-soon-t-' || rec.id);
    update bookings set reminded_soon_at = now() where id = rec.id;
  end loop;

  return jsonb_build_object('pushes_queued', v_sent);
end $$;

-- Schedule every 15 minutes (unschedule-first so re-runs don't error)
do $$
begin
  begin
    perform cron.unschedule('booking-reminders');
  exception when others then null;
  end;
  perform cron.schedule('booking-reminders', '*/15 * * * *',
                        'select public.process_booking_reminders()');
end $$;


-- ========================================================================
-- VERIFY:
--   select jobname, schedule from cron.job where jobname = 'booking-reminders';
--   select public.process_booking_reminders();  -- manual tick, returns queue count
-- ========================================================================
