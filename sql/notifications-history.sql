-- ============================================================================
-- notifications-history.sql  —  a durable, user-readable record of every push
--
-- Anne, 2026-08-21, testing the 3.0 APK: "i couldn't read the whole contents
-- of one and dismissed it, never to be seen again. dealbreaker for launch."
--
-- She was right that there was nowhere to look. Before this migration the app
-- recorded NOTHING user-facing when it pushed:
--
--   * push_subscriptions  — who can be reached, not what was said
--   * push_log            — only pushes the DATABASE sends (_booking_push),
--                           and RLS-restricted to admins
--   * send-push /
--     broadcast-push      — sent and forgot; no row written anywhere
--
-- So a booking ping, a confirmation, or an admin broadcast existed only as an
-- OS notification. Swipe it away and the content was gone for good.
--
-- This table is the record. One row per person per notification, written by
-- whoever sends it, readable only by the person it was addressed to.
--
-- ── Identity ────────────────────────────────────────────────────────────────
-- `recipient` holds exactly what push_subscriptions.user_id holds: the app's
-- pushKeyFor() output — a lowercased email, or '+1' + the last ten digits for
-- phone-identified accounts. Anything addressing a user must produce the same
-- string, which is what public.push_identity(email, phone) is for. Do not
-- invent a second shape here; that bug (tech phones passed raw while client
-- phones were normalised) already cost a round of silent no-op reminders.
--
-- ── Who can write ───────────────────────────────────────────────────────────
-- Deliberately NO insert policy for `authenticated`. Rows arrive from the edge
-- functions (service role, bypasses RLS) and from security-definer database
-- functions. A signed-in client cannot forge a notification into someone
-- else's history — or their own.
--
-- Depends on: public.current_email(), public.current_phone(), phone_digits(),
--             public.is_admin()  (all from phone-auth-stage-a-foundation.sql)
-- Safe to re-run. Run in: Supabase dashboard → nwqnakoongrorbwnrqzc → SQL editor.
-- ============================================================================

begin;

-- ── 1. The table ────────────────────────────────────────────────────────────
create table if not exists public.notifications (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  recipient   text        not null,   -- push_subscriptions.user_id shape
  title       text        not null,
  body        text,
  url         text,                   -- deep link the notification carried
  tag         text,                   -- collapse key, mirrors the push
  source      text,                   -- 'booking' | 'broadcast' | 'reminder-day' | ...
  read_at     timestamptz
);

comment on table public.notifications is
  'One row per person per push. The user-facing history behind the in-app Notifications screen: what was said, when, and whether it has been read. Written by send-push / broadcast-push (service role) and _booking_push (security definer). Never written directly by a signed-in client.';

comment on column public.notifications.recipient is
  'Matches push_subscriptions.user_id: lowercased email, or +1 plus the last ten digits. Produce it with public.push_identity(email, phone).';

-- The screen's only query: newest-first for one person. Partial index keeps
-- the unread-badge count cheap without carrying the whole read history.
create index if not exists notifications_recipient_created_idx
  on public.notifications (recipient, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications (recipient) where read_at is null;

-- ── 2. RLS ──────────────────────────────────────────────────────────────────
-- Same three-way ownership test used by push_subscriptions, so email accounts
-- and phone accounts both resolve. Admins see everything.
alter table public.notifications enable row level security;

drop policy if exists notif_select_self on public.notifications;
create policy notif_select_self on public.notifications for select to authenticated
  using (lower(recipient) = public.current_email()
         or phone_digits(recipient) = public.current_phone()
         or public.is_admin());

-- Delete lets someone clear their own history. No insert or update policy on
-- purpose: marking read goes through the RPC below so a client can only ever
-- touch read_at, never rewrite what a notification said.
drop policy if exists notif_delete_self on public.notifications;
create policy notif_delete_self on public.notifications for delete to authenticated
  using (lower(recipient) = public.current_email()
         or phone_digits(recipient) = public.current_phone()
         or public.is_admin());

-- ── 3. Ownership helper ─────────────────────────────────────────────────────
-- One definition of "this row is mine", so the RPCs below cannot drift from
-- the policies above.
create or replace function public.notif_is_mine(p_recipient text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(p_recipient) = public.current_email()
      or phone_digits(p_recipient) = public.current_phone()
      or public.is_admin();
$$;

-- ── 4. Read-state RPCs ──────────────────────────────────────────────────────
-- Security definer so they can UPDATE a table with no update policy, but each
-- one re-checks ownership per row. Idempotent: marking a read notification
-- read again is a no-op, and read_at is never moved backwards.
create or replace function public.notifications_mark_read(p_ids bigint[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.notifications
     set read_at = now()
   where id = any(p_ids)
     and read_at is null
     and public.notif_is_mine(recipient);
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.notifications_mark_all_read()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.notifications
     set read_at = now()
   where read_at is null
     and public.notif_is_mine(recipient);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Badge count. Cheap enough to call on every portal render thanks to the
-- partial index.
create or replace function public.notifications_unread_count()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.notifications
   where read_at is null
     and public.notif_is_mine(recipient);
$$;

revoke all on function public.notifications_mark_read(bigint[])   from public;
revoke all on function public.notifications_mark_all_read()       from public;
revoke all on function public.notifications_unread_count()        from public;
grant execute on function public.notifications_mark_read(bigint[]) to authenticated;
grant execute on function public.notifications_mark_all_read()     to authenticated;
grant execute on function public.notifications_unread_count()      to authenticated;

-- ── 5. Writer used by the database's own push path ──────────────────────────
-- _booking_push (the cron reminders) calls this alongside its push_log insert.
-- Security definer because the caller is already trusted and the table has no
-- insert policy at all.
create or replace function public.notifications_record(
  p_recipient text,
  p_title     text,
  p_body      text default null,
  p_url       text default null,
  p_tag       text default null,
  p_source    text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id bigint;
begin
  if p_recipient is null or btrim(p_recipient) = '' or p_title is null then
    return null;   -- never let a malformed call abort the push it belongs to
  end if;
  insert into public.notifications (recipient, title, body, url, tag, source)
  values (lower(btrim(p_recipient)), p_title, p_body, p_url, p_tag, p_source)
  returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.notifications_record(text,text,text,text,text,text) from public;

-- ── 6. Retention ────────────────────────────────────────────────────────────
-- Unbounded history would grow forever for no benefit. Read notifications get
-- 90 days, unread ones a year — an unread row is still someone's unanswered
-- message and should not vanish because it aged out.
create or replace function public.notifications_purge()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  delete from public.notifications
   where (read_at is not null and created_at < now() - interval '90 days')
      or (read_at is null     and created_at < now() - interval '365 days');
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.notifications_purge() from public;

commit;

-- ============================================================================
-- OPTIONAL, run once if you want the purge automated (pg_cron is already
-- installed for the booking reminders). Left out of the transaction above so
-- re-running this file doesn't stack duplicate schedules.
--
--   select cron.schedule('notifications-purge', '17 4 * * 0',
--                        $$select public.notifications_purge();$$);
--
-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- Run these after the migration and read the output before moving on.
--
-- 1. Table exists with the right shape:
--      select column_name, data_type
--        from information_schema.columns
--       where table_schema = 'public' and table_name = 'notifications'
--       order by ordinal_position;
--    Expect: id, created_at, recipient, title, body, url, tag, source, read_at
--
-- 2. RLS is on and there is NO insert/update policy for authenticated:
--      select policyname, cmd from pg_policies
--       where schemaname = 'public' and tablename = 'notifications';
--    Expect exactly two rows: notif_select_self (SELECT), notif_delete_self (DELETE)
--
-- 3. Write one to yourself and read it back from the app.
--    Replace the address with your own email or +1XXXXXXXXXX:
--      select public.notifications_record(
--        'annewilson1021@gmail.com',
--        'Test notification',
--        'If you can see this in the app, the history works.',
--        '/', 'mnc-test', 'manual');
--
-- 4. Badge count reflects it (run while signed in as that user, not as
--    the SQL editor's service role — this one only means something from
--    the app):
--      select public.notifications_unread_count();
-- ============================================================================
