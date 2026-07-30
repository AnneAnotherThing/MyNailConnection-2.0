-- ============================================================================
-- PHONE-AUTH STAGE E: reminders + pushes reach phone-identity users (2026-07-24)
-- ============================================================================
-- Two problems, one file:
--   1. _booking_push in SOURCE still posted to the OLD project's send-push
--      (the live DB copy was hand-patched 2026-07-15; source drifted). This
--      re-issue pins the NEW project URL + anon key so re-runs are safe.
--   2. process_booking_reminders addressed pushes to client_email and the
--      tech's email. Phone-identity users have neither; their push
--      subscriptions are keyed by their E.164 identity ('+1XXXXXXXXXX',
--      exactly what the app's pushKey stores). Reminders now address
--      email when present, else the phone-derived key. _booking_push
--      already no-ops on a null recipient.
-- Requires Stage A (public.phone_digits). Safe to re-run.
-- ============================================================================

create or replace function public._booking_push(
  p_user text, p_title text, p_body text, p_tag text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  k_url  text := 'https://nwqnakoongrorbwnrqzc.supabase.co/functions/v1/send-push';
  k_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53cW5ha29vbmdyb3Jid25ycXpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzNzczMjUsImV4cCI6MjA5ODk1MzMyNX0.TFFMlg9VjB0cyJwbgmVbeatFYQFaF1Ri0nrH0GwhHJs';
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
    select b.id, b.status, b.client_email, b.client_phone, b.client_name, b.starts_at,
           t.name as tech_name, t.email as tech_email, t.phone as tech_phone,
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
      perform public._booking_push(coalesce(nullif(lower(rec.client_email), ''), '+1' || right(public.phone_digits(rec.client_phone), 10)), 'Appointment tomorrow 💅',
           rec.svc || ' with ' || coalesce(rec.tech_name, 'your tech') || ', ' || v_when || '.',
           'bk-day-' || rec.id);
      v_sent := v_sent + 1;
      perform public._booking_push(coalesce(nullif(lower(rec.tech_email), ''), rec.tech_phone), 'Tomorrow: ' || coalesce(rec.client_name, 'a client'),
           rec.svc || ', ' || v_when || '.',
           'bk-day-t-' || rec.id);
    else
      v_sent := v_sent + 1;
      perform public._booking_push(coalesce(nullif(lower(rec.tech_email), ''), rec.tech_phone), 'Request still waiting',
           coalesce(rec.client_name, 'A client') || ' asked for ' || v_when ||
           '. Confirm or decline before it arrives.',
           'bk-day-t-' || rec.id);
    end if;
    update bookings set reminded_day_at = now() where id = rec.id;
  end loop;

  -- Soon (3 hours) reminders, confirmed only
  for rec in
    select b.id, b.client_email, b.client_phone, b.client_name, b.starts_at,
           t.name as tech_name, t.email as tech_email, t.phone as tech_phone,
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
    perform public._booking_push(coalesce(nullif(lower(rec.client_email), ''), '+1' || right(public.phone_digits(rec.client_phone), 10)), 'Today at ' || v_when || ' 💅',
         rec.svc || ' with ' || coalesce(rec.tech_name, 'your tech') || '. See you soon!',
         'bk-soon-' || rec.id);
    v_sent := v_sent + 1;
    perform public._booking_push(coalesce(nullif(lower(rec.tech_email), ''), rec.tech_phone), 'Up next: ' || coalesce(rec.client_name, 'a client'),
         rec.svc || ' at ' || v_when || '.',
         'bk-soon-t-' || rec.id);
    update bookings set reminded_soon_at = now() where id = rec.id;
  end loop;

  return jsonb_build_object('pushes_queued', v_sent);
end $$;
