-- MNC: morning reminder wording for the What's happening board (2026-10-11).
-- The push and in-app reminder still said "Flip on Open today". The chip is
-- now Available now (a post with an end time on the What's happening board),
-- and tapping the reminder opens that sheet. Body text only; schedule,
-- guards and the push call are unchanged from avail-reminder-default-on.sql.
--
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query.
-- Proof this is the new copy: the body below says "Working today?".

begin;

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
           coalesce(t.avail_reminder_time, '08:00'::time) as avail_reminder_time,
           t.avail_reminded_on,
           coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix') as tz,
           t.is_available
      from public.techs t
     where not coalesce(t.daily_avail_nudge_off, false)
  loop
    v_tz      := rec.tz;
    v_localdt := now() at time zone v_tz;   -- wall-clock in her zone

    -- already fired today, or before her time, or already open: skip
    if rec.avail_reminded_on is not distinct from v_localdt::date then continue; end if;
    if v_localdt::time < rec.avail_reminder_time then continue; end if;
    if rec.is_available then
      update public.techs set avail_reminded_on = v_localdt::date where id = rec.id;
      continue;
    end if;

    perform public._booking_push(
      public.push_identity(rec.email, rec.phone),
      'Morning 💅',
      'Working today? Post Available now and the clients looking right now see you first. Tap and I''ll take you right there.',
      'avail-am-' || to_char(v_localdt, 'YYYYMMDD'),
      'avail-am'
    );
    v_sent := v_sent + 1;
    update public.techs set avail_reminded_on = v_localdt::date where id = rec.id;
  end loop;

  return jsonb_build_object('reminders_queued', v_sent);
end $$;

commit;

-- Check: select prosrc from pg_proc where proname = 'process_avail_reminders';  -- contains 'Working today?'
