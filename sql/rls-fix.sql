-- ============================================================================
-- MNC v53 — RLS FIX: nuke all existing policies, then install correct ones
-- ============================================================================
-- The first pass left pre-existing permissive policies in place, which were
-- overriding the new restrictive ones. This script:
--   1. Drops every policy on each target table (regardless of name)
--   2. Reinstalls the correct set from scratch
--
-- Safe to re-run. Won't touch data, only policies.
-- ============================================================================

-- ── Helpers (idempotent) ────────────────────────────────────────────────────
create or replace function public.is_admin() returns boolean
language sql stable security definer as $$
  select coalesce(
    (auth.jwt() ->> 'email') in (
      'annewilson1021@gmail.com'
      -- add more admin emails here
    ),
    false
  );
$$;

create or replace function public.current_email() returns text
language sql stable as $$
  select lower(auth.jwt() ->> 'email');
$$;

-- ── Drop-all-policies helper ────────────────────────────────────────────────
do $$
declare
  t text;
  p record;
begin
  for t in
    select unnest(array[
      'techs','board_posts','bookings','push_subscriptions','user_inspo',
      'user_favorites','users','archived_techs','app_settings',
      'nail_techs','tech_photos','conversations','messages'
    ])
  loop
    for p in
      select polname
      from pg_policy
      where polrelid = ('public.' || t)::regclass
    loop
      execute format('drop policy if exists %I on public.%I', p.polname, t);
    end loop;
  end loop;
end $$;

-- ============================================================================
-- LIVE / ACTIVE TABLES
-- ============================================================================

-- TECHS — public SELECT, tech updates own row, admin all
alter table public.techs enable row level security;
create policy techs_select_all   on public.techs for select using (true);
create policy techs_update_self  on public.techs for update to authenticated
  using  (lower(email) = public.current_email())
  with check (lower(email) = public.current_email());
create policy techs_admin_update on public.techs for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy techs_insert_admin on public.techs for insert to authenticated
  with check (public.is_admin());
create policy techs_delete_admin on public.techs for delete to authenticated
  using (public.is_admin());

-- BOARD_POSTS — public SELECT, tech inserts/updates/deletes own posts
alter table public.board_posts enable row level security;
create policy board_select_all  on public.board_posts for select using (true);
create policy board_insert_self on public.board_posts for insert to authenticated
  with check (lower(tech_id) = public.current_email() or public.is_admin());
create policy board_update_self on public.board_posts for update to authenticated
  using  (lower(tech_id) = public.current_email() or public.is_admin())
  with check (lower(tech_id) = public.current_email() or public.is_admin());
create policy board_delete_self on public.board_posts for delete to authenticated
  using (lower(tech_id) = public.current_email() or public.is_admin());

-- BOOKINGS — UUID client_id / tech_id
alter table public.bookings enable row level security;
create policy bookings_select_involved on public.bookings for select to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );
create policy bookings_insert_client on public.bookings for insert to authenticated
  with check (client_id = auth.uid() or public.is_admin());
create policy bookings_update_involved on public.bookings for update to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  )
  with check (
    client_id = auth.uid()
    or tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );
create policy bookings_delete_involved on public.bookings for delete to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

-- PUSH_SUBSCRIPTIONS — user_id is text (email)
alter table public.push_subscriptions enable row level security;
create policy push_select_self on public.push_subscriptions for select to authenticated
  using (lower(user_id) = public.current_email() or public.is_admin());
create policy push_insert_self on public.push_subscriptions for insert to authenticated
  with check (lower(user_id) = public.current_email() or public.is_admin());
create policy push_update_self on public.push_subscriptions for update to authenticated
  using  (lower(user_id) = public.current_email() or public.is_admin())
  with check (lower(user_id) = public.current_email() or public.is_admin());
create policy push_delete_self on public.push_subscriptions for delete to authenticated
  using (lower(user_id) = public.current_email() or public.is_admin());

-- USER_INSPO — owner only (user_email column)
alter table public.user_inspo enable row level security;
create policy inspo_select_self on public.user_inspo for select to authenticated
  using (lower(user_email) = public.current_email() or public.is_admin());
create policy inspo_insert_self on public.user_inspo for insert to authenticated
  with check (lower(user_email) = public.current_email() or public.is_admin());
create policy inspo_update_self on public.user_inspo for update to authenticated
  using  (lower(user_email) = public.current_email() or public.is_admin())
  with check (lower(user_email) = public.current_email() or public.is_admin());
create policy inspo_delete_self on public.user_inspo for delete to authenticated
  using (lower(user_email) = public.current_email() or public.is_admin());

-- USER_FAVORITES — ASSUMING user_email column; edit if different
alter table public.user_favorites enable row level security;
create policy fav_select_self on public.user_favorites for select to authenticated
  using (lower(user_email) = public.current_email() or public.is_admin());
create policy fav_insert_self on public.user_favorites for insert to authenticated
  with check (lower(user_email) = public.current_email() or public.is_admin());
create policy fav_delete_self on public.user_favorites for delete to authenticated
  using (lower(user_email) = public.current_email() or public.is_admin());

-- USERS — assuming 'email' column
alter table public.users enable row level security;
create policy users_select_self on public.users for select to authenticated
  using (lower(email) = public.current_email() or public.is_admin());
create policy users_insert_self on public.users for insert to authenticated
  with check (lower(email) = public.current_email() or public.is_admin());
create policy users_update_self on public.users for update to authenticated
  using  (lower(email) = public.current_email() or public.is_admin())
  with check (lower(email) = public.current_email() or public.is_admin());

-- ============================================================================
-- ADMIN-ONLY TABLES
-- ============================================================================
alter table public.archived_techs enable row level security;
create policy arch_admin_all on public.archived_techs for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.app_settings enable row level security;
create policy settings_admin_all on public.app_settings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================================
-- LEGACY / DEPRECATED — admin-only lockdown
-- ============================================================================
alter table public.nail_techs enable row level security;
create policy nt_admin_all on public.nail_techs for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.tech_photos enable row level security;
create policy tp_admin_all on public.tech_photos for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.conversations enable row level security;
create policy conv_admin_all on public.conversations for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.messages enable row level security;
create policy msg_admin_all on public.messages for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================================
-- VERIFICATION — should show only the policies named above
-- ============================================================================
-- select c.relname as table_name, p.polname as policy_name
-- from pg_policy p join pg_class c on c.oid = p.polrelid
-- join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public'
-- order by c.relname, p.polname;
-- ============================================================================
