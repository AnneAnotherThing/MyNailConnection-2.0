-- ========================================================================
-- MNC Test Account Wipe  (2026-04-27)
-- ========================================================================
-- Hard-deletes all DB rows tied to a list of test/personal emails so
-- Anne can re-test signup from a clean state. Targets:
--   * auth.users
--   * public.users / public.techs / public.archived_techs
--   * public.tech_comps (in case any of these were comped)
--   * public.user_favorites (both user_email and tech_email sides)
--   * public.user_inspo (saved looks)
--   * public.board_posts (feed posts; tech_id is the lower-cased email)
--   * public.push_subscriptions (FK on public.users.id)
--
-- Email match is case-insensitive on every table — catches rows left
-- behind from the email-casing bug where techs/users had capital-S
-- emails while auth.users was lowercase.
--
-- Order matters because of FK constraints: child tables first, then
-- public.techs/users, then auth.users last.
--
-- NOT cleaned up by this script:
--   * Storage objects in the `tech-photos` bucket — Supabase blocks
--     DELETE on storage.objects from SQL (the protect_delete trigger).
--     Clean those via the Supabase dashboard's Storage tab, or by
--     calling the storage REST API. The orphaned files are harmless
--     for the re-test, just unsightly.
--   * Stripe customers / subscriptions — those live in Stripe, not
--     Supabase. If you've test-subscribed with one of these emails in
--     test mode, delete the customer in the Stripe Dashboard (Test
--     Data) or it'll resurface on next subscribe.
--
-- Safe to re-run; every DELETE is keyed on email so re-running is a
-- no-op once the rows are gone.
-- ========================================================================


-- ────────────────────────────────────────────────────────────────────────
-- The hit list. Edit here to add/remove emails. All matched
-- case-insensitively. lower(btrim(...)) on both sides.
-- ────────────────────────────────────────────────────────────────────────

with emails (e) as (values
  ('amwhite1971@gmail.com'),
  ('annewilson1021@gmail.com'),
  ('annewhite1021@gmail.com'),
  ('evad3333@gmail.com'),
  ('anne@hive-rise.com'),
  ('sonoransunappliancerepair@gmail.com')
)
-- ────────────────────────────────────────────────────────────────────────
-- BEFORE — show what exists across every relevant table.
-- Run this CTE+SELECT first as a dry-run; it doesn't change anything.
-- ────────────────────────────────────────────────────────────────────────
select 'auth.users'           as table_name, count(*) as rows from auth.users           where lower(email) in (select lower(btrim(e)) from emails)
union all
select 'public.users',          count(*)              from public.users                where lower(email) in (select lower(btrim(e)) from emails)
union all
select 'public.techs',          count(*)              from public.techs                where lower(email) in (select lower(btrim(e)) from emails)
union all
select 'public.archived_techs', count(*)              from public.archived_techs       where lower(coalesce(email,'')) in (select lower(btrim(e)) from emails)
union all
select 'public.tech_comps',     count(*)              from public.tech_comps           where email in (select lower(btrim(e)) from emails)
union all
select 'public.user_favorites (user side)', count(*) from public.user_favorites      where lower(user_email) in (select lower(btrim(e)) from emails)
union all
select 'public.user_favorites (tech side)', count(*) from public.user_favorites      where lower(tech_email) in (select lower(btrim(e)) from emails)
union all
select 'public.user_inspo',     count(*)              from public.user_inspo           where lower(user_email) in (select lower(btrim(e)) from emails)
union all
select 'public.board_posts',    count(*)              from public.board_posts          where lower(tech_id)    in (select lower(btrim(e)) from emails)
union all
select 'public.push_subscriptions', count(*) from public.push_subscriptions
 where user_id::text in (
   select id::text from public.users where lower(email) in (select lower(btrim(e)) from emails)
 )
;


-- ════════════════════════════════════════════════════════════════════════
-- DELETES — comment the BEFORE select above out, uncomment this whole
-- block, run. Order is child → parent → auth so FKs don't trip.
-- ════════════════════════════════════════════════════════════════════════

-- Uncomment from here ↓ to actually run the wipe.
--
-- with emails (e) as (values
--   ('amwhite1971@gmail.com'),
--   ('annewilson1021@gmail.com'),
--   ('annewhite1021@gmail.com'),
--   ('evad3333@gmail.com'),
--   ('anne@hive-rise.com'),
--   ('sonoransunappliancerepair@gmail.com')
-- ),
-- email_set as (select lower(btrim(e)) as e from emails)
--
-- -- Children first (anything keyed on email or user_id).
-- , del_favs_user as (
--   delete from public.user_favorites
--    where lower(user_email) in (select e from email_set)
--   returning 1
-- )
-- , del_favs_tech as (
--   delete from public.user_favorites
--    where lower(tech_email) in (select e from email_set)
--   returning 1
-- )
-- , del_inspo as (
--   delete from public.user_inspo
--    where lower(user_email) in (select e from email_set)
--   returning 1
-- )
-- , del_board as (
--   delete from public.board_posts
--    where lower(tech_id) in (select e from email_set)
--   returning 1
-- )
-- , del_push as (
--   delete from public.push_subscriptions
--    where user_id::text in (
--      select id::text from public.users where lower(email) in (select e from email_set)
--    )
--   returning 1
-- )
-- , del_comps as (
--   delete from public.tech_comps
--    where email in (select e from email_set)
--   returning 1
-- )
-- -- Now the main rows.
-- , del_techs as (
--   delete from public.techs
--    where lower(email) in (select e from email_set)
--   returning 1
-- )
-- , del_arch as (
--   delete from public.archived_techs
--    where lower(coalesce(email,'')) in (select e from email_set)
--   returning 1
-- )
-- , del_users as (
--   delete from public.users
--    where lower(email) in (select e from email_set)
--   returning 1
-- )
-- -- Auth last so FK references from public.* don't fight us. Requires
-- -- service-role / SQL editor (which runs as postgres) — won't work
-- -- from a normal app session. That's intentional.
-- , del_auth as (
--   delete from auth.users
--    where lower(email) in (select e from email_set)
--   returning 1
-- )
-- select
--   (select count(*) from del_favs_user) as favorites_user_side,
--   (select count(*) from del_favs_tech) as favorites_tech_side,
--   (select count(*) from del_inspo)     as user_inspo,
--   (select count(*) from del_board)     as board_posts,
--   (select count(*) from del_push)      as push_subscriptions,
--   (select count(*) from del_comps)     as tech_comps,
--   (select count(*) from del_techs)     as techs,
--   (select count(*) from del_arch)      as archived_techs,
--   (select count(*) from del_users)     as users,
--   (select count(*) from del_auth)      as auth_users;


-- ════════════════════════════════════════════════════════════════════════
-- AFTER — re-run the BEFORE block to confirm everything zeroed out.
-- ════════════════════════════════════════════════════════════════════════
