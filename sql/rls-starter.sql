-- ============================================================================
-- MNC v53 — Row-Level Security Starter Policies (REAL SCHEMA VERSION)
-- ============================================================================
-- Run this in Supabase → SQL Editor. Safe to re-run — all policies use
-- DROP IF EXISTS before CREATE.
--
-- Admin is currently hardcoded to annewilson1021@gmail.com. Edit IS_ADMIN()
-- to add more admins later.
--
-- Legacy / deprecated tables (nail_techs, tech_photos, conversations,
-- messages) are locked down — only admin can touch them. If you're sure you
-- don't need them anymore, you can DROP them in a separate cleanup step.
-- ============================================================================

-- ── Helper: is the caller an admin? ─────────────────────────────────────────
create or replace function public.is_admin() returns boolean
language sql stable security definer as $$
  select coalesce(
    (auth.jwt() ->> 'email') in (
      'annewilson1021@gmail.com'
      -- add more admin emails here, comma-separated
    ),
    false
  );
$$;

-- ── Helper: is the caller a tech with this email? ──────────────────────────
create or replace function public.current_email() returns text
language sql stable as $$
  select lower(auth.jwt() ->> 'email');
$$;

-- ============================================================================
-- LIVE / ACTIVE TABLES
-- ============================================================================

-- ── TECHS — public directory ────────────────────────────────────────────────
alter table public.techs enable row level security;

drop policy if exists techs_select_all    on public.techs;
drop policy if exists techs_update_self   on public.techs;
drop policy if exists techs_insert_admin  on public.techs;
drop policy if exists techs_delete_admin  on public.techs;
drop policy if exists techs_admin_update  on public.techs;

-- Anyone can browse the tech directory (needed for signed-out browsing)
create policy techs_select_all on public.techs
  for select using (true);

-- Techs can update their own row (matched by email)
create policy techs_update_self on public.techs
  for update to authenticated
  using  (lower(email) = public.current_email())
  with check (lower(email) = public.current_email());

-- Admins can do anything
create policy techs_insert_admin on public.techs
  for insert to authenticated
  with check (public.is_admin());

create policy techs_admin_update on public.techs
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy techs_delete_admin on public.techs
  for delete to authenticated
  using (public.is_admin());

-- ── BOARD_POSTS — tech posts, public read ───────────────────────────────────
-- Replaces two-way conversations: techs post updates, users read.
-- tech_id is stored as text (email).
alter table public.board_posts enable row level security;

drop policy if exists board_select_all    on public.board_posts;
drop policy if exists board_insert_self   on public.board_posts;
drop policy if exists board_update_self   on public.board_posts;
drop policy if exists board_delete_self   on public.board_posts;
drop policy if exists board_admin_all     on public.board_posts;

create policy board_select_all on public.board_posts
  for select using (true);

create policy board_insert_self on public.board_posts
  for insert to authenticated
  with check (lower(tech_id) = public.current_email() or public.is_admin());

create policy board_update_self on public.board_posts
  for update to authenticated
  using  (lower(tech_id) = public.current_email() or public.is_admin())
  with check (lower(tech_id) = public.current_email() or public.is_admin());

create policy board_delete_self on public.board_posts
  for delete to authenticated
  using (lower(tech_id) = public.current_email() or public.is_admin());

-- ── BOOKINGS — client_id / tech_id are UUIDs ────────────────────────────────
-- client_id = auth.uid() of the client account.
-- tech_id = techs.id, and the tech account's email matches that techs row.
alter table public.bookings enable row level security;

drop policy if exists bookings_select_involved on public.bookings;
drop policy if exists bookings_insert_client   on public.bookings;
drop policy if exists bookings_update_involved on public.bookings;
drop policy if exists bookings_delete_involved on public.bookings;

-- Client or tech involved can SELECT; admin can see all
create policy bookings_select_involved on public.bookings
  for select to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

-- Client can create bookings for themselves
create policy bookings_insert_client on public.bookings
  for insert to authenticated
  with check (client_id = auth.uid() or public.is_admin());

-- Either party can update (e.g. tech accepts / cancels, client reschedules)
create policy bookings_update_involved on public.bookings
  for update to authenticated
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

create policy bookings_delete_involved on public.bookings
  for delete to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs where lower(email) = public.current_email())
    or public.is_admin()
  );

-- ── PUSH_SUBSCRIPTIONS — user_id is text (email) ───────────────────────────
alter table public.push_subscriptions enable row level security;

drop policy if exists push_select_self on public.push_subscriptions;
drop policy if exists push_insert_self on public.push_subscriptions;
drop policy if exists push_update_self on public.push_subscriptions;
drop policy if exists push_delete_self on public.push_subscriptions;

create policy push_select_self on public.push_subscriptions
  for select to authenticated
  using (lower(user_id) = public.current_email() or public.is_admin());

create policy push_insert_self on public.push_subscriptions
  for insert to authenticated
  with check (lower(user_id) = public.current_email() or public.is_admin());

create policy push_update_self on public.push_subscriptions
  for update to authenticated
  using  (lower(user_id) = public.current_email() or public.is_admin())
  with check (lower(user_id) = public.current_email() or public.is_admin());

create policy push_delete_self on public.push_subscriptions
  for delete to authenticated
  using (lower(user_id) = public.current_email() or public.is_admin());

-- ── USER_INSPO — saved inspiration photos ──────────────────────────────────
-- Columns: id, user_email, photo_url, tech_name, created_at
alter table public.user_inspo enable row level security;

drop policy if exists inspo_select_self on public.user_inspo;
drop policy if exists inspo_insert_self on public.user_inspo;
drop policy if exists inspo_update_self on public.user_inspo;
drop policy if exists inspo_delete_self on public.user_inspo;

create policy inspo_select_self on public.user_inspo
  for select to authenticated
  using (lower(user_email) = public.current_email() or public.is_admin());

create policy inspo_insert_self on public.user_inspo
  for insert to authenticated
  with check (lower(user_email) = public.current_email() or public.is_admin());

create policy inspo_update_self on public.user_inspo
  for update to authenticated
  using  (lower(user_email) = public.current_email() or public.is_admin())
  with check (lower(user_email) = public.current_email() or public.is_admin());

create policy inspo_delete_self on public.user_inspo
  for delete to authenticated
  using (lower(user_email) = public.current_email() or public.is_admin());

-- ── USER_FAVORITES ──────────────────────────────────────────────────────────
-- I don't have the column names yet — ASSUMING user_email column. If your
-- favorites table uses user_id (uuid) or something else, edit the policies
-- below. Alternatively drop and recreate this block after you confirm columns.
alter table public.user_favorites enable row level security;

drop policy if exists fav_select_self on public.user_favorites;
drop policy if exists fav_insert_self on public.user_favorites;
drop policy if exists fav_delete_self on public.user_favorites;

-- NOTE: edit 'user_email' below if the actual column is different.
create policy fav_select_self on public.user_favorites
  for select to authenticated
  using (lower(user_email) = public.current_email() or public.is_admin());

create policy fav_insert_self on public.user_favorites
  for insert to authenticated
  with check (lower(user_email) = public.current_email() or public.is_admin());

create policy fav_delete_self on public.user_favorites
  for delete to authenticated
  using (lower(user_email) = public.current_email() or public.is_admin());

-- ── USERS ───────────────────────────────────────────────────────────────────
-- Columns unknown — assuming an 'email' column. Edit if different.
alter table public.users enable row level security;

drop policy if exists users_select_self on public.users;
drop policy if exists users_insert_self on public.users;
drop policy if exists users_update_self on public.users;

create policy users_select_self on public.users
  for select to authenticated
  using (lower(email) = public.current_email() or public.is_admin());

create policy users_insert_self on public.users
  for insert to authenticated
  with check (lower(email) = public.current_email() or public.is_admin());

create policy users_update_self on public.users
  for update to authenticated
  using  (lower(email) = public.current_email() or public.is_admin())
  with check (lower(email) = public.current_email() or public.is_admin());

-- ============================================================================
-- ADMIN-ONLY TABLES
-- ============================================================================

-- ── ARCHIVED_TECHS — admin only (113 rows, was UNRESTRICTED!) ──────────────
alter table public.archived_techs enable row level security;

drop policy if exists arch_admin_all on public.archived_techs;

create policy arch_admin_all on public.archived_techs
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── APP_SETTINGS — admin only ───────────────────────────────────────────────
alter table public.app_settings enable row level security;

drop policy if exists settings_admin_all on public.app_settings;

create policy settings_admin_all on public.app_settings
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================================
-- LEGACY / DEPRECATED TABLES — locked down to admin only
-- ============================================================================
-- These tables are no longer used by the app but still contain (or could
-- contain) data. Locking down so anon can't read or write. You can DROP
-- them entirely later once you confirm nothing references them.
-- ============================================================================

-- nail_techs — legacy duplicate of techs
alter table public.nail_techs enable row level security;
drop policy if exists nt_admin_all on public.nail_techs;
create policy nt_admin_all on public.nail_techs
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- tech_photos — legacy, photos now live as JSONB on techs.photos
alter table public.tech_photos enable row level security;
drop policy if exists tp_admin_all on public.tech_photos;
create policy tp_admin_all on public.tech_photos
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- conversations — feature pulled (replaced by board_posts)
alter table public.conversations enable row level security;
drop policy if exists conv_admin_all on public.conversations;
create policy conv_admin_all on public.conversations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- messages — feature pulled (replaced by board_posts)
alter table public.messages enable row level security;
drop policy if exists msg_admin_all on public.messages;
create policy msg_admin_all on public.messages
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ============================================================================
-- VERIFICATION — run this after to confirm RLS is on everywhere
-- ============================================================================
-- select tablename, rowsecurity from pg_tables
-- where schemaname = 'public' order by tablename;
-- ============================================================================
