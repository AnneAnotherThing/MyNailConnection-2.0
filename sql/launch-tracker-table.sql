-- ============================================================================
-- launch-tracker-table.sql
-- ----------------------------------------------------------------------------
-- Internal post-launch enhancement tracker for Anne + Leslie.
-- Lives alongside founders_feedback on the admin-feedback page; admin-only
-- read/write via RLS.
--
-- Each item:
--   title, short label
--   details, optional longer description
--   priority, high | medium | low
--   status, open | done
--   added_by_*, denormalized author info (so the UI can show
--                    "Added by Anne" without a join on every render)
--
-- ASSUMPTION: public.users has a `role` column where admins are 'admin'.
-- ============================================================================


create table if not exists public.launch_tracker (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  title text not null check (length(trim(title)) > 0),
  details text,
  priority text not null check (priority in ('high','medium','low')) default 'medium',
  status text not null check (status in ('open','done')) default 'open',
  added_by_user_id uuid references auth.users(id) on delete set null,
  added_by_name text,
  done_at timestamptz,
  done_note text,
  updated_at timestamptz not null default now()
);

create index if not exists idx_launch_tracker_status_priority
  on public.launch_tracker (status, priority, created_at desc);


-- Trigger: keep updated_at fresh
create or replace function public.touch_launch_tracker_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_touch_launch_tracker_updated on public.launch_tracker;
create trigger trg_touch_launch_tracker_updated
  before update on public.launch_tracker
  for each row execute function public.touch_launch_tracker_updated_at();


-- ----------------------------------------------------------------------------
-- RLS, admins only, full read/write
-- ----------------------------------------------------------------------------
alter table public.launch_tracker enable row level security;

drop policy if exists "launch_tracker_select_admin" on public.launch_tracker;
create policy "launch_tracker_select_admin"
  on public.launch_tracker for select to authenticated
  using (
    exists (select 1 from public.users u where u.id = auth.uid() and u.role = 'admin')
  );

drop policy if exists "launch_tracker_insert_admin" on public.launch_tracker;
create policy "launch_tracker_insert_admin"
  on public.launch_tracker for insert to authenticated
  with check (
    exists (select 1 from public.users u where u.id = auth.uid() and u.role = 'admin')
  );

drop policy if exists "launch_tracker_update_admin" on public.launch_tracker;
create policy "launch_tracker_update_admin"
  on public.launch_tracker for update to authenticated
  using (
    exists (select 1 from public.users u where u.id = auth.uid() and u.role = 'admin')
  )
  with check (
    exists (select 1 from public.users u where u.id = auth.uid() and u.role = 'admin')
  );

drop policy if exists "launch_tracker_delete_admin" on public.launch_tracker;
create policy "launch_tracker_delete_admin"
  on public.launch_tracker for delete to authenticated
  using (
    exists (select 1 from public.users u where u.id = auth.uid() and u.role = 'admin')
  );
