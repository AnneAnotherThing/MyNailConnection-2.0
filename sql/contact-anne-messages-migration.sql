-- ────────────────────────────────────────────────────────────────────────
-- MNC contact_anne_messages migration
-- ────────────────────────────────────────────────────────────────────────
-- Purpose: persist every "Nudge Anne" message to a database table so
-- messages aren't lost when the push edge function can't reach Anne
-- (no active push subscription, offline, etc.). Anne sees the inbox in
-- the admin screen regardless of push state.
--
-- SAFE TO RE-RUN: uses IF NOT EXISTS and drops existing policies before
-- re-creating them.
--
-- HOW TO APPLY: paste into Supabase → SQL Editor and Run.
-- ────────────────────────────────────────────────────────────────────────

-- ========================================================================
-- TABLE
-- ========================================================================
create table if not exists public.contact_anne_messages (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  user_email    text not null,
  user_name     text,
  user_role     text,   -- 'tech' / 'client' / 'admin' at the time of sending
  body          text not null,
  phone         text,   -- captured from profile at send time (Anne's contact-back path)
  consent       boolean default true,
  read_at       timestamptz,    -- null = unread; timestamp = when Anne marked it read
  status        text default 'new'  -- 'new' | 'in_progress' | 'resolved' (future use)
);

create index if not exists contact_anne_messages_created_idx
  on public.contact_anne_messages (created_at desc);
create index if not exists contact_anne_messages_unread_idx
  on public.contact_anne_messages (read_at) where read_at is null;

-- ========================================================================
-- ROW LEVEL SECURITY
-- Anyone signed-in can INSERT their own message (matched by email).
-- Only admins can SELECT / UPDATE / DELETE.
-- ========================================================================
alter table public.contact_anne_messages enable row level security;

drop policy if exists camsg_insert_self on public.contact_anne_messages;
drop policy if exists camsg_admin_all   on public.contact_anne_messages;

-- Authenticated users can insert messages where user_email matches their own.
create policy camsg_insert_self on public.contact_anne_messages
  for insert to authenticated
  with check (lower(user_email) = public.current_email());

-- Admins can read / update / delete all messages.
create policy camsg_admin_all on public.contact_anne_messages
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ========================================================================
-- VERIFY
-- ========================================================================
-- After running, these should both return a sensible count:
--   select count(*) from public.contact_anne_messages;  -- 0 on fresh install
--   select * from pg_policies where tablename = 'contact_anne_messages';
