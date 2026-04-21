-- ─────────────────────────────────────────────────────────────────────────
-- MNC — Admin management refactor
--
-- Moves is_admin() off the hardcoded SQL email list onto the existing
-- public.users.role column, so the Admin Settings screen (the "Admins"
-- section with the + Add admin by email button) is the single source of
-- truth. No more SQL edits required to grant / revoke admin access.
--
-- Safe to run on top of the previous migrations. Re-runnable.
-- ─────────────────────────────────────────────────────────────────────────

-- ── 1. Rewrite is_admin() to read from users.role ────────────────────────
create or replace function public.is_admin() returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where lower(u.email) = lower(auth.jwt() ->> 'email')
      and u.role = 'Admin'
  );
$$;

-- Important: keep security definer + explicit search_path so this runs
-- consistently regardless of the caller's session settings and can read
-- public.users even when RLS would otherwise block the caller.


-- ── 2. Bootstrap Anne as an admin (no-op if already set) ──────────────────
-- If Anne's users row doesn't exist yet (e.g., she hasn't signed in through
-- the app since migrations were introduced), this also safely inserts it.
insert into public.users (email, role, name, created_at)
values ('annewilson1021@gmail.com', 'Admin', 'Anne Wilson', now())
on conflict (email) do update set role = 'Admin';


-- ── 3. Seed Leslie (EDIT her email before running) ───────────────────────
-- Swap the placeholder for her actual email. If her users row doesn't
-- exist yet, she'll be created as an Admin; if it does, her role is
-- updated. She still needs a Supabase Auth account with this email to
-- actually sign in.
insert into public.users (email, role, name, created_at)
values ('leslie@mynailconnection.com', 'Admin', 'Leslie', now())
on conflict (email) do update set role = 'Admin';


-- ── 4. RLS so admins can promote/demote other users from the UI ──────────
-- The in-app "+ Add admin" button issues an UPDATE to users.role. That
-- only works if the calling JWT has permission.
drop policy if exists users_admin_update_role on public.users;
create policy users_admin_update_role
  on public.users
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Admins also need to SELECT other users to populate the "Admins" list.
drop policy if exists users_admin_select_all on public.users;
create policy users_admin_select_all
  on public.users
  for select
  to authenticated
  using (public.is_admin() or lower(email) = public.current_email());


-- ── 5. Self-lockout guard ────────────────────────────────────────────────
-- Prevent an admin from accidentally demoting themselves (which would lock
-- them out of the admin UI until another admin promotes them back).
create or replace function public.prevent_self_demote()
returns trigger
language plpgsql
as $$
begin
  if lower(new.email) = lower(auth.jwt() ->> 'email')
     and old.role = 'Admin' and new.role is distinct from 'Admin' then
    raise exception 'You cannot remove your own admin role. Ask another admin to do it for you.';
  end if;
  return new;
end;
$$;

drop trigger if exists users_no_self_demote on public.users;
create trigger users_no_self_demote
  before update of role on public.users
  for each row
  when (old.role is distinct from new.role)
  execute function public.prevent_self_demote();


-- ── 6. Verify ────────────────────────────────────────────────────────────
-- Run these after the migration:
--   select public.is_admin();
--     → true when signed in as any user whose role = 'Admin'
--   select email, role from public.users where role = 'Admin' order by email;
--     → every admin, one row each
-- ─────────────────────────────────────────────────────────────────────────
