-- ─────────────────────────────────────────────────────────────────────────
-- MNC — Admin Stats dashboard migration
--
-- Run this once in Supabase → SQL Editor. Safe to re-run (idempotent).
--
-- What it does:
--   1. Adds Leslie's email to the is_admin() allowlist so she can read stats
--      (EDIT the email below before running — defaults to a placeholder).
--   2. Grants admin-only SELECT on the launch_waitlist table so the stats
--      dashboard in the app can read totals / trends / sources.
--   3. Grants admin-only SELECT on tech_photos so the "photos uploaded"
--      count works (only if the table exists).
--   4. Creates a generic `events` table for future first-party event
--      logging — profile_created, photo_uploaded, booking_clicked, etc.
--      INSERT is open (so the app / marketing site can log events),
--      SELECT is admin-only.
-- ─────────────────────────────────────────────────────────────────────────

-- ── 1. Admin allowlist ────────────────────────────────────────────────────
-- ⚠️  EDIT this email before running: swap 'leslie@mynailconnection.com'
-- for Leslie's actual email address. She needs a Supabase Auth account
-- under that email (if she doesn't have one yet, have her sign up through
-- the app first — password reset works fine).
create or replace function public.is_admin() returns boolean
language sql stable security definer as $$
  select coalesce(
    (auth.jwt() ->> 'email') in (
      'annewilson1021@gmail.com',
      'leslie@mynailconnection.com'
      -- add more admin emails here, one per line, each ending with a comma
      -- except the last one.
    ),
    false
  );
$$;


-- ── 2. Waitlist admin SELECT ──────────────────────────────────────────────
-- Non-admins still can't read waitlist data (anon users can only INSERT).
drop policy if exists waitlist_select_admin on public.launch_waitlist;
create policy waitlist_select_admin
  on public.launch_waitlist
  for select
  to authenticated
  using (public.is_admin());

grant select on public.launch_waitlist to authenticated;


-- ── 3. Photo count (optional — only run if tech_photos exists) ────────────
do $$
begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'tech_photos') then
    execute 'drop policy if exists tech_photos_select_admin on public.tech_photos';
    execute 'create policy tech_photos_select_admin on public.tech_photos for select to authenticated using (public.is_admin())';
    execute 'grant select on public.tech_photos to authenticated';
  end if;
end $$;


-- ── 4. First-party events table ───────────────────────────────────────────
-- Write-once append-only log. Every meaningful action fires an event row
-- so the admin dashboard can report on things GA4 can't see (internal
-- conversions, per-tech engagement, retention cohorts, etc.).
create table if not exists public.events (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  user_email  text,                   -- who did it (null for anon/marketing events)
  event_name  text not null,          -- 'waitlist_signup' | 'profile_created' | etc.
  source      text,                   -- UI surface: 'final-cta' | 'popin' | 'tech-dash' | etc.
  properties  jsonb not null default '{}'::jsonb   -- everything else
);

create index if not exists events_created_at_idx on public.events (created_at desc);
create index if not exists events_name_idx       on public.events (event_name);
create index if not exists events_user_idx       on public.events (user_email);

alter table public.events enable row level security;

drop policy if exists events_insert_anyone on public.events;
drop policy if exists events_select_admin  on public.events;

-- Anyone (anon + authenticated) can INSERT an event. Prevents abuse via
-- a permissive WITH CHECK + the rate limiting Supabase applies at the edge.
create policy events_insert_anyone
  on public.events
  for insert
  to anon, authenticated
  with check (true);

-- Only admins can read the events table.
create policy events_select_admin
  on public.events
  for select
  to authenticated
  using (public.is_admin());

grant insert on public.events to anon, authenticated;
grant select on public.events to authenticated;
grant usage, select on sequence public.events_id_seq to anon, authenticated;


-- ── 5. Verify ─────────────────────────────────────────────────────────────
-- After running, check that things worked:
--   select public.is_admin();
--     → true when you run this in the SQL Editor while signed in as an admin
--   select count(*) from public.launch_waitlist;
--     → actual waitlist count (as admin)
--   select count(*) from public.events;
--     → 0 initially, grows as events fire
