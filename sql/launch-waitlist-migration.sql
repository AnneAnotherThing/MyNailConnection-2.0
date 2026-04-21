-- ────────────────────────────────────────────────────────────
-- Pre-launch mailing list for My Nail Connection
-- Run this once in Supabase → SQL Editor before the marketing page
-- waitlist form can accept signups.
-- ────────────────────────────────────────────────────────────

create table if not exists public.launch_waitlist (
  email       text primary key,
  created_at  timestamptz not null default now(),
  source      text                    -- 'hero' | 'final-cta' | etc.
);

-- Helpful indexes
create index if not exists launch_waitlist_created_at_idx
  on public.launch_waitlist (created_at desc);

-- Row-Level Security: anonymous visitors can INSERT only.
-- Reads / updates / deletes require the service_role key (admin-only).
alter table public.launch_waitlist enable row level security;

-- Wipe any old policies so we start clean
drop policy if exists "anon_can_signup"   on public.launch_waitlist;
drop policy if exists "anyone_can_insert" on public.launch_waitlist;
drop policy if exists "public_can_insert" on public.launch_waitlist;

-- One permissive INSERT policy targeting `public` role
-- (covers anon + authenticated, no role-mismatch surprises).
create policy "public_can_insert"
  on public.launch_waitlist
  as permissive
  for insert
  to public
  with check (true);

-- Required: explicit table grant. RLS policies are necessary but not
-- sufficient — the anon role also needs the underlying INSERT privilege.
grant usage on schema public to anon, authenticated;
grant insert on public.launch_waitlist to anon, authenticated;

-- ── Verify (run this after, results should show the policy + grants) ──
-- select policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies where tablename = 'launch_waitlist';
-- select grantee, privilege_type
--   from information_schema.role_table_grants
--   where table_name = 'launch_waitlist';

-- ────────────────────────────────────────────────────────────
-- Reading the list (run from the Supabase SQL Editor anytime):
--   select email, source, created_at from public.launch_waitlist order by created_at desc;
--
-- Exporting for launch day email blast:
--   copy (select email from public.launch_waitlist order by created_at) to stdout with csv;
-- ────────────────────────────────────────────────────────────
