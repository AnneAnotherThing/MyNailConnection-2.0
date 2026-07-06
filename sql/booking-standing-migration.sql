-- ========================================================================
-- MNC 3.0 Standing Appointments  (2026-07-05)
-- ========================================================================
-- Run in Supabase -> SQL Editor AFTER booking-tier1-migration.sql.
-- Safe to re-run.
--
-- "Convert to standing": the tech turns one upcoming appointment into a
-- repeating series, same wall-clock time, every N weeks (1-8, UI offers
-- 1/2/3/4). Occurrences are MATERIALIZED as real bookings rows so
-- reminders, lists, cancellation, and slot-blocking all work with zero
-- special cases. A daily cron keeps ~4 future occurrences on the books.
-- Conflicts (existing bookings incl. buffer, time off) are skipped, not
-- forced, the tech resolves those by hand.
--
-- Wall-clock math is done in the tech's timezone so a 2:00 PM standing
-- stays 2:00 PM across DST (moot in Arizona, correct everywhere else).
-- ========================================================================


-- ── 1. Table + booking link column ──────────────────────────────────────

create table if not exists public.standing_appointments (
  id               uuid primary key default gen_random_uuid(),
  tech_id          uuid not null references public.techs(id) on delete cascade,
  client_id        uuid not null,
  service_id       uuid references public.tech_services(id) on delete set null,
  interval_weeks   int  not null check (interval_weeks between 1 and 8),
  anchor_starts_at timestamptz not null,
  client_email     text,
  client_name      text,
  active           boolean not null default true,
  created_at       timestamptz not null default now()
);

create index if not exists idx_standing_tech on public.standing_appointments(tech_id, active);

alter table public.bookings add column if not exists standing_id uuid
  references public.standing_appointments(id) on delete set null;

alter table public.standing_appointments enable row level security;

drop policy if exists standing_select_involved on public.standing_appointments;
drop policy if exists standing_update_tech     on public.standing_appointments;

create policy standing_select_involved on public.standing_appointments
  for select to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

-- Tech can end (active=false) their own series; creation goes through
-- the convert_to_standing RPC only.
create policy standing_update_tech on public.standing_appointments
  for update to authenticated
  using (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  )
  with check (
    tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );


-- ── 2. Occurrence generator (shared by RPC + daily cron) ────────────────
-- Materializes future occurrences for one series until p_target future
-- bookings exist. Advances candidate dates even when skipping conflicts
-- (a blocked date consumes that cycle, it doesn't shift the rhythm).

create or replace function public._materialize_standing(
  p_standing_id uuid,
  p_target      int default 4
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  s record;
  v_tz     text;
  v_buffer int;
  v_dur    int;
  v_local  timestamp;      -- wall clock of the latest occurrence
  cand     timestamptz;
  cand_end timestamptz;
  fut      int;
  created  int := 0;
  skipped  int := 0;
  guard    int := 0;
begin
  select sa.*, coalesce(t.booking_timezone, 'America/Phoenix') as tz,
         coalesce(t.booking_buffer_minutes, 0) as buf
    into s
    from standing_appointments sa
    join techs t on t.id = sa.tech_id
   where sa.id = p_standing_id and sa.active;
  if not found then return jsonb_build_object('created', 0, 'skipped', 0); end if;
  v_tz := s.tz; v_buffer := s.buf;

  select coalesce(duration_minutes, 60) into v_dur
    from tech_services where id = s.service_id;
  if not found then v_dur := 60; end if;

  perform pg_advisory_xact_lock(hashtext('booking:' || s.tech_id::text));

  select count(*) into fut from bookings
   where standing_id = p_standing_id
     and status in ('pending','confirmed')
     and starts_at > now();

  -- start stepping from the latest occurrence on the books (or the anchor)
  select coalesce(max(starts_at), s.anchor_starts_at) at time zone v_tz
    into v_local
    from bookings
   where standing_id = p_standing_id;

  while fut < p_target and guard < 26 loop
    guard := guard + 1;
    v_local := v_local + (s.interval_weeks * interval '1 week');
    cand := v_local at time zone v_tz;
    if cand <= now() then continue; end if;
    cand_end := cand + make_interval(mins => v_dur);

    if exists (
         select 1 from tech_time_off o
          where o.tech_id = s.tech_id
            and (cand at time zone v_tz)::date between o.start_date and o.end_date
       )
       or exists (
         select 1 from bookings x
          where x.tech_id = s.tech_id
            and x.status in ('pending','confirmed')
            and x.starts_at - make_interval(mins => v_buffer) < cand_end
            and x.ends_at   + make_interval(mins => v_buffer) > cand
       )
    then
      skipped := skipped + 1;
    else
      insert into bookings
        (client_id, tech_id, service_id, starts_at, ends_at, status,
         client_name, client_email, standing_id, booking_date, booking_time)
      values
        (s.client_id, s.tech_id, s.service_id, cand, cand_end, 'confirmed',
         s.client_name, s.client_email, p_standing_id,
         (cand at time zone v_tz)::date,
         to_char(cand at time zone v_tz, 'HH24:MI'));
      created := created + 1;
      fut := fut + 1;
    end if;
  end loop;

  return jsonb_build_object('created', created, 'skipped', skipped);
end $$;


-- ── 3. convert_to_standing RPC (tech-initiated) ─────────────────────────

create or replace function public.convert_to_standing(
  p_booking_id     uuid,
  p_interval_weeks int
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  b record;
  v_standing uuid;
  r jsonb;
begin
  if p_interval_weeks not between 1 and 8 then
    raise exception 'Interval must be between 1 and 8 weeks.';
  end if;

  select b2.id, b2.client_id, b2.tech_id, b2.service_id, b2.starts_at,
         b2.status, b2.client_name, b2.client_email, b2.standing_id,
         t.email as tech_email, t.name as tech_name
    into b
    from bookings b2
    join techs t on t.id = b2.tech_id
   where b2.id = p_booking_id;
  if not found then raise exception 'Appointment not found.'; end if;
  if lower(coalesce(b.tech_email, '')) <> v_email and not public.is_admin() then
    raise exception 'Only the tech can make an appointment standing.';
  end if;
  if b.status not in ('pending', 'confirmed') then
    raise exception 'Only upcoming appointments can become standing.';
  end if;
  if b.standing_id is not null then
    raise exception 'This appointment is already part of a standing series.';
  end if;

  insert into standing_appointments
    (tech_id, client_id, service_id, interval_weeks, anchor_starts_at,
     client_email, client_name)
  values
    (b.tech_id, b.client_id, b.service_id, p_interval_weeks, b.starts_at,
     b.client_email, b.client_name)
  returning id into v_standing;

  update bookings set standing_id = v_standing where id = p_booking_id;

  r := public._materialize_standing(v_standing, 4);

  -- tell the client (best effort)
  begin
    perform public._booking_push(
      b.client_email,
      'You have a standing appointment 💅',
      coalesce(b.tech_name, 'Your tech') || ' set you up every ' ||
        case when p_interval_weeks = 1 then 'week' else p_interval_weeks || ' weeks' end ||
        ' at the same time. See them all in My Appointments.',
      'standing-' || v_standing);
  exception when others then null;
  end;

  return jsonb_build_object('standing_id', v_standing) || r;
end $$;

grant execute on function public.convert_to_standing(uuid, int) to authenticated;


-- ── 4. Daily top-up cron ─────────────────────────────────────────────────

create or replace function public.extend_standing_appointments()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  rec record;
  tot_created int := 0;
  r jsonb;
begin
  for rec in select id from standing_appointments where active loop
    r := public._materialize_standing(rec.id, 4);
    tot_created := tot_created + coalesce((r ->> 'created')::int, 0);
  end loop;
  return jsonb_build_object('created', tot_created);
end $$;

do $$
begin
  begin
    perform cron.unschedule('standing-extend');
  exception when others then null;
  end;
  perform cron.schedule('standing-extend', '0 9 * * *',
                        'select public.extend_standing_appointments()');
end $$;


-- ========================================================================
-- VERIFY:
--   select jobname, schedule from cron.job order by jobname;
--   -- expect booking-reminders (*/15) and standing-extend (0 9 * * *)
-- ========================================================================
