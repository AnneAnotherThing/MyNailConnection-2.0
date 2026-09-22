-- ─────────────────────────────────────────────────────────────────────────
-- MNC, Morning "are you open today?" push reminder
--
-- Run once in Supabase → SQL Editor. Idempotent / safe to re-run.
-- Requires the existing push stack: public._booking_push, public.push_identity,
-- public.push_log, pg_cron + pg_net (all created by
-- sql/booking-reminders-observability.sql). No edge deploy, no app rebuild.
--
-- What it does:
--   A tech can pick a time in My Settings ("Remind me every morning at ___").
--   Each morning at that local time she gets ONE push nudging her to flip
--   Open today on. It only reminds — it never sets availability for her, and
--   it never fires on a day she's already showing Open today. Off by default
--   (avail_reminder_time null = no reminder).
--
--   The cron reuses the same _booking_push helper the booking reminders use,
--   so delivery is proven and logged in public.push_log (source 'avail-am').
-- ─────────────────────────────────────────────────────────────────────────

begin;

-- ── 1. Per-tech reminder settings ────────────────────────────────────────
alter table public.techs
  add column if not exists avail_reminder_time time,          -- null = off
  add column if not exists avail_reminder_tz   text,          -- IANA tz captured in-browser when set
  add column if not exists avail_reminded_on   date;          -- last local date we fired (once/day guard)

comment on column public.techs.avail_reminder_time is
  'Local time of the daily "are you open today?" push. Null = reminder off. Set from My Settings; tz in avail_reminder_tz.';


-- ── 2. The cron worker ────────────────────────────────────────────────────
-- Fires at/after the tech's chosen local time, at most once per local day,
-- and only when she is not already Open today. Robust to the 15-minute cron
-- cadence: "at or after" + a per-day stamp means a missed slot still fires on
-- the next run, and never twice.
create or replace function public.process_avail_reminders()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rec       record;
  v_tz      text;
  v_localdt timestamptz;
  v_sent    int := 0;
begin
  for rec in
    select t.id, t.email, t.phone, t.name,
           t.avail_reminder_time, t.avail_reminded_on,
           coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix') as tz,
           t.is_available
      from public.techs t
     where t.avail_reminder_time is not null
  loop
    v_tz      := rec.tz;
    v_localdt := now() at time zone v_tz;   -- wall-clock in her zone

    -- already fired today, or before her time, or already open → skip
    if rec.avail_reminded_on is not distinct from v_localdt::date then continue; end if;
    if v_localdt::time < rec.avail_reminder_time then continue; end if;
    if rec.is_available then
      -- nothing to nudge; still stamp so we don't reconsider her all day
      update public.techs set avail_reminded_on = v_localdt::date where id = rec.id;
      continue;
    end if;

    perform public._booking_push(
      public.push_identity(rec.email, rec.phone),
      'Taking clients today? 💅',
      'Flip Open today on so clients looking right now can find you. Tap to set it.',
      'avail-am-' || to_char(v_localdt, 'YYYYMMDD'),
      'avail-am'
    );
    v_sent := v_sent + 1;
    update public.techs set avail_reminded_on = v_localdt::date where id = rec.id;
  end loop;

  return jsonb_build_object('reminders_queued', v_sent);
end $$;


-- ── 3. Schedule it ─────────────────────────────────────────────────────────
-- Every 15 minutes, same cadence as the booking reminders. The per-tech time
-- gate inside the function decides who actually gets pushed on each run.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'avail-reminders') then
    perform cron.unschedule('avail-reminders');
  end if;
  perform cron.schedule('avail-reminders', '*/15 * * * *',
                        'select public.process_avail_reminders()');
end $$;

commit;

-- ── Verify ────────────────────────────────────────────────────────────────
-- select jobname, schedule, active from cron.job where jobname='avail-reminders';
-- -- force a tech on, then run by hand:
-- update public.techs set avail_reminder_time='08:00', avail_reminder_tz='America/Phoenix',
--        avail_reminded_on=null where phone like '%6166';
-- select public.process_avail_reminders();
-- select created_at, source, recipient, title from public.push_log
--   where source='avail-am' order by created_at desc limit 5;
