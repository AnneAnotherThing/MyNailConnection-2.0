-- ============================================================================
-- founders-feedback-table.sql
-- ----------------------------------------------------------------------------
-- Feedback collection from the public founders page (/founders.html).
-- Anyone hitting the page can submit; only admins can read.
--
-- Form prompts (any one is enough; all three is a gift):
--   wish_to_add  — "Something you'd add?"
--   annoyance    — "Something annoying?"
--   message      — "Anything else?"
--
-- The referral column ("Anyone we should reach out to?") was removed
-- from the form on 2026-05-04. The column is dropped below if present.
--
-- Idempotent: this script handles both fresh installs and existing tables
-- that were created with the earlier (category + required-message) schema.
--
-- ASSUMPTION: public.users has a `role` column where admins are 'admin'.
-- Adjust the SELECT/UPDATE policies if your schema uses a different column.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- TABLE — fresh install
-- ----------------------------------------------------------------------------
create table if not exists public.founders_feedback (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  email text not null,
  wish_to_add text,
  annoyance text,
  message text,
  user_agent text,
  resolved boolean not null default false,
  resolved_at timestamptz,
  resolved_note text,
  constraint at_least_one_field check (
    coalesce(nullif(trim(wish_to_add), ''), nullif(trim(annoyance), ''),
             nullif(trim(message),     '')) is not null
  )
);


-- ----------------------------------------------------------------------------
-- MIGRATE — bring an older table up to the new shape (no-op on fresh installs)
-- ----------------------------------------------------------------------------
-- Add the prompt columns if missing.
alter table public.founders_feedback add column if not exists wish_to_add text;
alter table public.founders_feedback add column if not exists annoyance   text;

-- Drop the referral column if it was previously created (form prompt removed 2026-05-04).
alter table public.founders_feedback drop column if exists referral;

-- message used to be NOT NULL — relax it now that it's a catch-all field.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'founders_feedback'
      and column_name  = 'message'
      and is_nullable  = 'NO'
  ) then
    execute 'alter table public.founders_feedback alter column message drop not null';
  end if;
end $$;

-- Drop the legacy category column + its check constraint (if either exists).
alter table public.founders_feedback drop constraint if exists founders_feedback_category_check;
alter table public.founders_feedback drop column if exists category;

-- (Re)install the "at least one field" check so it always reflects the current rules.
alter table public.founders_feedback drop constraint if exists at_least_one_field;
alter table public.founders_feedback add  constraint at_least_one_field check (
  coalesce(nullif(trim(wish_to_add), ''), nullif(trim(annoyance), ''),
           nullif(trim(message),     '')) is not null
);


-- ----------------------------------------------------------------------------
-- INDEXES
-- ----------------------------------------------------------------------------
create index if not exists idx_founders_feedback_created
  on public.founders_feedback (created_at desc);

create index if not exists idx_founders_feedback_unresolved
  on public.founders_feedback (created_at desc)
  where resolved = false;


-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.founders_feedback enable row level security;

-- Anon + authenticated can INSERT (so the public founders page can submit).
drop policy if exists "founders_feedback_insert_any" on public.founders_feedback;
create policy "founders_feedback_insert_any"
  on public.founders_feedback
  for insert
  to anon, authenticated
  with check (true);

-- Authenticated admins can SELECT.
drop policy if exists "founders_feedback_select_admin" on public.founders_feedback;
create policy "founders_feedback_select_admin"
  on public.founders_feedback
  for select
  to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = auth.uid()
        and u.role = 'admin'
    )
  );

-- Authenticated admins can UPDATE (mark resolved, add notes).
drop policy if exists "founders_feedback_update_admin" on public.founders_feedback;
create policy "founders_feedback_update_admin"
  on public.founders_feedback
  for update
  to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = auth.uid()
        and u.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.users u
      where u.id = auth.uid()
        and u.role = 'admin'
    )
  );

-- No DELETE policy. Service-role (Supabase dashboard) can purge if needed.


-- ----------------------------------------------------------------------------
-- VERIFY (commented; uncomment to smoke-test)
-- ----------------------------------------------------------------------------
-- insert into public.founders_feedback (name, email, wish_to_add)
--   values ('Smoke Test', 'test@example.com', 'remove me');
-- select * from public.founders_feedback order by created_at desc limit 5;
