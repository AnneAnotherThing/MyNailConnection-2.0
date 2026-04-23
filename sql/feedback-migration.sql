-- feedback table — user-submitted bug reports, ideas, questions
--
-- Captured from the floating "Send feedback" button on every signed-in
-- screen. RLS: anyone signed in can INSERT, only admins can SELECT. This
-- lets us gather reports without exposing one user's feedback to another.
--
-- Apply by pasting into Supabase → SQL Editor and running. Idempotent —
-- the create/policy statements each guard for existence.
-- 2026-04-22.

create table if not exists public.feedback (
  id              uuid        primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  user_email      text,
  user_role       text,
  category        text        not null,
  message         text        not null,
  current_screen  text,
  user_agent      text,
  app_version     text,
  -- Rolling last ~20 console errors/warnings captured client-side. Stored
  -- as JSONB so Anne can query specific fields later if a debugging
  -- pattern emerges (e.g. "all reports mentioning Stripe").
  console_snapshot jsonb default '[]'::jsonb,
  screenshot_url  text,
  -- Triage status for when Anne + Leslie start working through reports.
  -- Free text so we can evolve the vocabulary without schema churn.
  status          text        not null default 'new'
);

-- Fast triage queries: "show me new ones" and "show me recent".
create index if not exists feedback_status_created_idx
  on public.feedback (status, created_at desc);
create index if not exists feedback_created_idx
  on public.feedback (created_at desc);

-- RLS — lock down by default, then open narrow lanes.
alter table public.feedback enable row level security;

-- Anyone authenticated can submit. Admin-only SELECT means one tech
-- can't read another tech's bug report (which might mention credentials
-- or other sensitive flow details).
drop policy if exists feedback_insert_any_authed on public.feedback;
create policy feedback_insert_any_authed
  on public.feedback for insert
  to authenticated
  with check (true);

drop policy if exists feedback_select_admin on public.feedback;
create policy feedback_select_admin
  on public.feedback for select
  to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.email = auth.jwt() ->> 'email'
        and u.role  = 'admin'
    )
  );

-- Optional: admin-only UPDATE so triage state can move without fresh
-- inserts. SELECT covers the read side; this covers status edits.
drop policy if exists feedback_update_admin on public.feedback;
create policy feedback_update_admin
  on public.feedback for update
  to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.email = auth.jwt() ->> 'email'
        and u.role  = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.users u
      where u.email = auth.jwt() ->> 'email'
        and u.role  = 'admin'
    )
  );

-- No DELETE policy on purpose. If a report needs removal (e.g. contains
-- a password someone typed into the message), do it manually from the
-- Supabase dashboard so it's a deliberate act, not a one-tap.
