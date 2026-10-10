-- MNC: the morning "are you open today?" push is on for everyone by default.
-- Anne, 2026-10-09: now that Open today turns itself off at midnight, a tech
-- who never set the reminder would never be asked again. Live check that
-- evening: 37 techs, 2 with a reminder time set, 0 opted out.
--
-- Before: the push only went to techs with avail_reminder_time set (My
-- Settings). After: a tech with no time set gets it at 8:00 her local time.
-- Opting out still works the same way (daily_avail_nudge_off, which My
-- Settings sets when she picks "off"), and a tech who picked a time keeps
-- her time. Everything else in process_avail_reminders is unchanged.
--
-- Delivery still needs a push subscription on her phone; without one the
-- message is kept in her in-app Notifications and nothing is sent.
--
-- Idempotent. Re-run freely.

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
      'Got chair time today? Flip on Open today and your work glows for the clients looking right now. Tap and I''ll take you right there.',
      'avail-am-' || to_char(v_localdt, 'YYYYMMDD'),
      'avail-am'
    );
    v_sent := v_sent + 1;
    update public.techs set avail_reminded_on = v_localdt::date where id = rec.id;
  end loop;

  return jsonb_build_object('reminders_queued', v_sent);
end $$;

-- Check:
--   select name, avail_reminder_time, daily_avail_nudge_off, avail_reminded_on from public.techs order by name;
--   select * from public.push_log where source = 'avail-am' order by created_at desc limit 20;
