-- Task #11 fix (2026-08-03): _booking_push still pointed at the dead ktiz
-- project, so every cron reminder push silently went nowhere. Recreate it
-- on nwqnakoongrorbwnrqzc with the live URL + anon key. The URL/key live
-- only inside this one function, so redefining it fixes both the day-before
-- and same-day reminder paths (process_booking_reminders / _soon variants)
-- without touching them.
--
-- Run in: Supabase dashboard → nwqnakoongrorbwnrqzc → SQL editor.

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

-- ── Confirm (read-only) ─────────────────────────────────────────────────────
-- Should print exactly one row containing the nwqn URL and no ktiz anywhere.
select case when prosrc like '%nwqnakoongrorbwnrqzc%' and prosrc not like '%ktiz%'
            then 'OK — _booking_push points at nwqn'
            else 'STILL WRONG — inspect prosrc' end as status
from pg_proc
where proname = '_booking_push' and pronamespace = 'public'::regnamespace;
