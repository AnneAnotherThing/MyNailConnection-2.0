-- MNC: Open today and Open this week turn themselves off.
-- Anne, 2026-10-09: "does open today reset at midnight and open this week
-- reset sunday?" They did not. The only reset lived in the tech's browser
-- (scheduleAvailabilityResets in index.html) and its trigger never armed,
-- and no cron touched the flags. A tech's Open today stayed lit until she
-- tapped it off, and the morning reminder skipped her while it was lit.
--
-- This file:
--   1. Two stamp columns, avail_set_at and week_set_at, written by a trigger
--      whenever the flag flips on (and on insert when it starts on). Rows
--      that are on today get stamped now, so they reset at the next
--      boundary instead of being switched off on the first run.
--   2. process_avail_resets(): Open today goes off once the tech's local
--      date has moved past the day she set it. Open this week goes off at
--      her local Sunday midnight after the week she set it (set on a
--      Sunday = lasts through the following Saturday).
--      Timezone: avail_reminder_tz, then booking_timezone, then Phoenix.
--   3. A cron job, avail-resets, every 15 minutes, same cadence as the
--      reminders.
--
-- Side effect worth knowing: new techs start with Open this week on
-- (sql/default-open-week-new-clients.sql). From now on that first week ends
-- on the first Sunday after signup, like anyone else's.
--
-- Idempotent. Re-run freely.

begin;

-- ── 1. Stamps ───────────────────────────────────────────────────────────────
alter table public.techs
  add column if not exists avail_set_at timestamptz,
  add column if not exists week_set_at  timestamptz;

comment on column public.techs.avail_set_at is 'When is_available last flipped on. Cleared by process_avail_resets at the next local midnight.';
comment on column public.techs.week_set_at  is 'When is_same_day (Open this week) last flipped on. Cleared by process_avail_resets at the next local Sunday midnight.';

create or replace function public.techs_stamp_avail()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(new.is_available, false) then new.avail_set_at := now(); end if;
    if coalesce(new.is_same_day, false)  then new.week_set_at  := now(); end if;
  else
    if coalesce(new.is_available, false) and not coalesce(old.is_available, false) then new.avail_set_at := now(); end if;
    if coalesce(new.is_same_day, false)  and not coalesce(old.is_same_day, false)  then new.week_set_at  := now(); end if;
  end if;
  return new;
end $$;

drop trigger if exists techs_stamp_avail_trg on public.techs;
create trigger techs_stamp_avail_trg
  before insert or update of is_available, is_same_day on public.techs
  for each row execute function public.techs_stamp_avail();

-- Rows that are on right now: stamp them so they reset at the next boundary.
update public.techs set avail_set_at = now() where is_available and avail_set_at is null;
update public.techs set week_set_at  = now() where is_same_day  and week_set_at  is null;

-- ── 2. The reset ────────────────────────────────────────────────────────────
create or replace function public.process_avail_resets()
returns table (today_off int, week_off int)
language plpgsql security definer
set search_path = public
as $$
declare
  v_today int := 0;
  v_week  int := 0;
begin
  -- Open today: off once the local date is past the date it was set.
  with cand as (
    select t.id
      from public.techs t
     where t.is_available
       and t.avail_set_at is not null
       and (now() at time zone coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix'))::date
         > (t.avail_set_at at time zone coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix'))::date
  )
  update public.techs t
     set is_available = false, avail_set_at = null
    from cand
   where t.id = cand.id;
  get diagnostics v_today = row_count;

  -- Open this week: off once the local date reaches the Sunday after the
  -- week it was set. Sunday is dow 0; set on a Sunday means the next one.
  with cand as (
    select t.id
      from public.techs t,
      lateral (select coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix') as tz) z,
      lateral (select (t.week_set_at at time zone z.tz)::date as set_d,
                      (now() at time zone z.tz)::date       as now_d) d
     where t.is_same_day
       and t.week_set_at is not null
       and d.now_d >= d.set_d + (case when extract(dow from d.set_d) = 0 then 7
                                      else 7 - extract(dow from d.set_d)::int end)
  )
  update public.techs t
     set is_same_day = false, week_set_at = null
    from cand
   where t.id = cand.id;
  get diagnostics v_week = row_count;

  return query select v_today, v_week;
end $$;

revoke all on function public.process_avail_resets() from public, anon, authenticated;

-- ── 3. Schedule it ─────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from cron.job where jobname = 'avail-resets') then
    perform cron.unschedule('avail-resets');
  end if;
  perform cron.schedule('avail-resets', '*/15 * * * *',
                        'select public.process_avail_resets()');
end $$;

commit;

-- Check:
--   select jobname, schedule from cron.job where jobname like 'avail-%';
--   select name, is_available, avail_set_at, is_same_day, week_set_at from public.techs where is_available or is_same_day;
--   select * from public.process_avail_resets();   -- returns how many it turned off this run
