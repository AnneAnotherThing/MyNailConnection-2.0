-- ============================================================================
-- BOOKING REMINDERS: make them observable, and fix the tech phone key (2026-08-15)
-- ============================================================================
-- Background: the day-before and same-day reminders have never been observed
-- firing. Not "seen failing" — never observed at all, because there was
-- nothing to observe. _booking_push calls net.http_post, which is
-- fire-and-forget: it queues a request, returns immediately, and throws away
-- the id. Whether send-push ever answered, and what it said, went nowhere.
-- pg_net does keep responses in net._http_response, but it prunes them after
-- a few hours, so by the time anyone thought to look the evidence was gone.
--
-- This migration does three things:
--
--   1. public.push_log — a durable row per push the database sends, stamped
--      with the pg_net request id. Survives pg_net's pruning, so "did the
--      2am reminder fire" has an answer tomorrow morning.
--   2. public.push_log_recent — a view joining that log to whatever pg_net
--      still holds, so a recent push shows its actual HTTP status and the
--      send-push JSON body ({"sent":1} vs {"sent":0,"reason":...}).
--   3. Fixes a real bug found while reading this code: the CLIENT fallback
--      key was normalised to '+1XXXXXXXXXX' but the TECH fallback passed
--      techs.phone raw. push_subscriptions.user_id is written by the app's
--      pushKeyFor(), which always produces '+1' + last ten digits, so any
--      tech row whose phone was stored in another shape got a reminder
--      addressed to a key that matches no subscription. Silent no-op. Both
--      sides now go through one helper that mirrors pushKeyFor exactly.
--
-- Depends on: Stage A (public.phone_digits), pg_cron + pg_net already installed.
-- Safe to re-run. Run in: Supabase dashboard → nwqnakoongrorbwnrqzc → SQL editor.
-- ============================================================================

begin;

-- ── 1. The log ──────────────────────────────────────────────────────────────
create table if not exists public.push_log (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  source      text,          -- 'reminder-day' | 'reminder-soon' | 'standing' | ...
  recipient   text,          -- the push_subscriptions.user_id we addressed
  title       text,
  tag         text,
  request_id  bigint         -- net.http_post's id, joins to net._http_response
);

create index if not exists push_log_created_idx on public.push_log (created_at desc);
create index if not exists push_log_request_idx on public.push_log (request_id);

comment on table public.push_log is
  'One row per push the DATABASE sends via _booking_push. Exists so cron reminders can be proven to have fired after pg_net has pruned its response rows.';

alter table public.push_log enable row level security;

-- Admins read it; nothing else touches it directly. _booking_push is
-- security definer, so its inserts do not need a policy.
drop policy if exists push_log_admin_read on public.push_log;
create policy push_log_admin_read on public.push_log
  for select using (public.is_admin());

-- ── 2. One identity helper, mirroring the app's pushKeyFor() ────────────────
-- index.html: pushKeyFor(email, phone) returns the email when there is one,
-- otherwise '+1' + the last ten digits. push_subscriptions.user_id holds
-- exactly that, so anything addressing a user has to produce the same string.
create or replace function public.push_identity(p_email text, p_phone text)
returns text
language sql
immutable
as $$
  select coalesce(
           nullif(lower(trim(coalesce(p_email, ''))), ''),
           case
             when length(public.phone_digits(p_phone)) >= 10
               then '+1' || right(public.phone_digits(p_phone), 10)
             else null
           end
         );
$$;

comment on function public.push_identity(text, text) is
  'Mirrors index.html pushKeyFor(): email if present, else +1 and the last ten digits. Must match push_subscriptions.user_id.';

grant execute on function public.push_identity(text, text) to authenticated;

-- ── 3. _booking_push, now logging what it sent ──────────────────────────────
-- p_source has a default so the existing 4-argument callers (standing
-- bookings) keep working untouched.
--
-- The old 4-arg function has to be DROPPED, not replaced: adding a defaulted
-- parameter creates a new signature rather than replacing the old one, and
-- Postgres would then be left with both. Every existing 4-argument call would
-- fail with "function _booking_push(text,text,text,text) is not unique".
drop function if exists public._booking_push(text, text, text, text);

create or replace function public._booking_push(
  p_user text, p_title text, p_body text, p_tag text, p_source text default 'unknown'
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  k_url  text := 'https://nwqnakoongrorbwnrqzc.supabase.co/functions/v1/send-push';
  k_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53cW5ha29vbmdyb3Jid25ycXpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzNzczMjUsImV4cCI6MjA5ODk1MzMyNX0.TFFMlg9VjB0cyJwbgmVbeatFYQFaF1Ri0nrH0GwhHJs';
  v_request_id bigint;
begin
  if p_user is null or p_user = '' then
    -- Worth recording: an un-addressable push is exactly the failure mode
    -- that used to vanish without trace.
    insert into public.push_log (source, recipient, title, tag, request_id)
    values (p_source, '(no recipient)', p_title, p_tag, null);
    return;
  end if;

  select net.http_post(
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
  ) into v_request_id;

  insert into public.push_log (source, recipient, title, tag, request_id)
  values (p_source, p_user, p_title, p_tag, v_request_id);
end $$;

-- ── 4. process_booking_reminders, with normalised keys and a source label ───
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
      perform public._booking_push(
           public.push_identity(rec.client_email, rec.client_phone),
           'Appointment tomorrow 💅',
           rec.svc || ' with ' || coalesce(rec.tech_name, 'your tech') || ', ' || v_when || '.',
           'bk-day-' || rec.id, 'reminder-day');
      v_sent := v_sent + 1;
      perform public._booking_push(
           public.push_identity(rec.tech_email, rec.tech_phone),
           'Tomorrow: ' || coalesce(rec.client_name, 'a client'),
           rec.svc || ', ' || v_when || '.',
           'bk-day-t-' || rec.id, 'reminder-day');
    else
      v_sent := v_sent + 1;
      perform public._booking_push(
           public.push_identity(rec.tech_email, rec.tech_phone),
           'Request still waiting',
           coalesce(rec.client_name, 'A client') || ' asked for ' || v_when ||
           '. Confirm or decline before it arrives.',
           'bk-day-t-' || rec.id, 'reminder-day');
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
    perform public._booking_push(
         public.push_identity(rec.client_email, rec.client_phone),
         'Today at ' || v_when || ' 💅',
         rec.svc || ' with ' || coalesce(rec.tech_name, 'your tech') || '. See you soon.',
         'bk-soon-' || rec.id, 'reminder-soon');
    v_sent := v_sent + 1;
    perform public._booking_push(
         public.push_identity(rec.tech_email, rec.tech_phone),
         'Up next: ' || coalesce(rec.client_name, 'a client'),
         rec.svc || ' at ' || v_when || '.',
         'bk-soon-t-' || rec.id, 'reminder-soon');
    update bookings set reminded_soon_at = now() where id = rec.id;
  end loop;

  -- Keep the log from growing without bound. 60 days is far longer than any
  -- question anyone will ask of it, and this runs every 15 minutes.
  delete from public.push_log where created_at < now() - interval '60 days';

  return jsonb_build_object('pushes_queued', v_sent);
end $$;

commit;

-- ── 5. The view that answers "did it actually go out" ───────────────────────
-- Created outside the transaction and guarded, because net._http_response is
-- pg_net's internal table and the name has moved between versions. If it is
-- not there, the view still gives the log on its own, which is the part that
-- matters after a few hours anyway.
do $$
begin
  if to_regclass('net._http_response') is not null then
    execute $v$
      create or replace view public.push_log_recent as
      select l.id, l.created_at, l.source, l.recipient, l.title, l.tag,
             l.request_id,
             r.status_code,
             -- pg_net stores the body as text; cast defensively rather than
             -- assuming, since this table is internal to the extension.
             r.content::text as response_body,
             r.error_msg
        from public.push_log l
        left join net._http_response r on r.id = l.request_id
       order by l.created_at desc
    $v$;
  else
    execute $v$
      create or replace view public.push_log_recent as
      select l.id, l.created_at, l.source, l.recipient, l.title, l.tag,
             l.request_id,
             null::int  as status_code,
             null::text as response_body,
             null::text as error_msg
        from public.push_log l
       order by l.created_at desc
    $v$;
  end if;
end $$;

-- ── 6. Make sure the job is actually SCHEDULED on this project ──────────────
-- This is the step that may never have happened. booking-tier1-migration.sql
-- scheduled 'booking-reminders', but that file predates the move from the old
-- ktiz project, and sql/diagnose-confirm-and-push.sql (2026-08-03) lists
-- "are the reminder cron jobs even scheduled here?" as an OPEN question that
-- was never answered. Recreating the functions is worthless if nothing calls
-- them every 15 minutes. Unschedule-first so re-runs never error.
create extension if not exists pg_cron;
create extension if not exists pg_net;

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
-- VERIFY / OPERATE
--
-- a) Is the cron job scheduled on THIS project? (Step 6 just did it, this
--    confirms it took.)
--      select jobid, jobname, schedule, active from cron.job;
--    Expect 'booking-reminders' every */15, active = true.
--
-- b) Has it been running, and did any run error?
--      select jobid, status, return_message, start_time
--        from cron.job_run_details
--       where start_time > now() - interval '24 hours'
--       order by start_time desc limit 20;
--
-- c) What has the database actually sent, and what came back?
--      select * from public.push_log_recent limit 50;
--    status_code 200 with response_body {"sent":1} is a delivered push.
--    {"sent":0,"reason":"no subscriptions found"} means the recipient key
--    matched no row: compare `recipient` against
--      select user_id from push_subscriptions;
--    Anything older than a few hours will show a null status_code because
--    pg_net pruned the response. The log row itself still proves it fired.
--
-- d) Force a tick right now without waiting for cron:
--      select public.process_booking_reminders();
--      select * from public.push_log_recent limit 10;
--
-- e) End-to-end test with a real booking. Set one up ~2 hours out on a tech
--    account whose phone has the app installed and notifications accepted,
--    confirm it, then run (d). The same-day path fires inside 3 hours.
--    To re-test the SAME booking, clear the stamps first:
--      update bookings set reminded_day_at = null, reminded_soon_at = null
--       where id = '<booking-uuid>';
-- ========================================================================
