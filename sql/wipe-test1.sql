-- ============================================================================
-- Wipe + reset test1@gmail.com  (2026-04-30)
-- ============================================================================
-- Test account got tangled from toggling free/paid/comp states during
-- store-listing testing. App crashes post-login on this account, but session
-- persists and reopen succeeds — classic poisoned-account-data symptom.
-- This script obliterates every DB row tied to test1@gmail.com (case-
-- insensitive) so a fresh signup via the app starts from zero.
--
-- Tables hit (matches canonical wipe-test-accounts.sql, plus three the
-- canonical script is missing — flagged at the bottom for backport):
--   * auth.users
--   * public.users
--   * public.techs
--   * public.archived_techs
--   * public.tech_comps
--   * public.user_favorites (both user_email and tech_email sides)
--   * public.user_inspo
--   * public.board_posts (tech_id is the lower-cased email)
--   * public.push_subscriptions (FK on public.users.id)
--   * public.contact_anne_messages   ← NOT in wipe-test-accounts.sql
--   * public.feedback                ← NOT in wipe-test-accounts.sql
--   * public.launch_waitlist         ← NOT in wipe-test-accounts.sql
--
-- NOT touched (intentional, not bugs):
--   * storage.objects in tech-photos bucket — protect_delete trigger blocks
--     SQL deletes. If you want test1's photo files gone, clean them via the
--     Supabase dashboard → Storage → tech-photos. They're orphaned and
--     harmless otherwise.
--   * Stripe customers — if test1 ever did a test-mode subscribe, delete the
--     Stripe customer in Stripe Dashboard (Test Data) before re-signing up
--     or RevenueCat may re-attach a tier on the new account. For free-tier
--     testing this is usually a no-op.
--
-- After running: on the device, hit "Create a Free Account" in the app and
-- sign up with test1@gmail.com / TestUser1. Free tier with 5 free post slots
-- is the default — don't toggle anything afterward, that's the whole point.
--
-- Run blocks 1, 2, 3 in order in the Supabase SQL editor.
-- ============================================================================


-- ── 1. BEFORE — show what's there ───────────────────────────────────────────
select 'auth.users'                    as table_name, count(*) as rows from auth.users                  where lower(email) = 'test1@gmail.com'
union all
select 'public.users',                 count(*)              from public.users                 where lower(email) = 'test1@gmail.com'
union all
select 'public.techs',                 count(*)              from public.techs                 where lower(email) = 'test1@gmail.com'
union all
select 'public.archived_techs',        count(*)              from public.archived_techs        where lower(coalesce(email,'')) = 'test1@gmail.com'
union all
select 'public.tech_comps',            count(*)              from public.tech_comps            where email = 'test1@gmail.com'
union all
select 'public.user_favorites (user)', count(*)              from public.user_favorites        where lower(user_email) = 'test1@gmail.com'
union all
select 'public.user_favorites (tech)', count(*)              from public.user_favorites        where lower(tech_email) = 'test1@gmail.com'
union all
select 'public.user_inspo',            count(*)              from public.user_inspo            where lower(user_email) = 'test1@gmail.com'
union all
select 'public.board_posts',           count(*)              from public.board_posts           where lower(tech_id)    = 'test1@gmail.com'
union all
select 'public.push_subscriptions',    count(*)              from public.push_subscriptions
  where user_id::text in (select id::text from public.users where lower(email) = 'test1@gmail.com')
union all
select 'public.contact_anne_messages', count(*)              from public.contact_anne_messages where lower(user_email) = 'test1@gmail.com'
union all
select 'public.feedback',              count(*)              from public.feedback              where lower(user_email) = 'test1@gmail.com'
union all
select 'public.launch_waitlist',       count(*)              from public.launch_waitlist       where lower(email) = 'test1@gmail.com'
;


-- ── 2. DELETE — single WITH so all FK checks happen at end-of-statement ─────
with email_set (e) as (values ('test1@gmail.com'))
, del_favs_user as (
  delete from public.user_favorites
   where lower(user_email) in (select e from email_set)
  returning 1
)
, del_favs_tech as (
  delete from public.user_favorites
   where lower(tech_email) in (select e from email_set)
  returning 1
)
, del_inspo as (
  delete from public.user_inspo
   where lower(user_email) in (select e from email_set)
  returning 1
)
, del_board as (
  delete from public.board_posts
   where lower(tech_id) in (select e from email_set)
  returning 1
)
, del_push as (
  delete from public.push_subscriptions
   where user_id::text in (
     select id::text from public.users where lower(email) in (select e from email_set)
   )
  returning 1
)
, del_comps as (
  delete from public.tech_comps
   where email in (select e from email_set)
  returning 1
)
, del_msgs as (
  delete from public.contact_anne_messages
   where lower(user_email) in (select e from email_set)
  returning 1
)
, del_fb as (
  delete from public.feedback
   where lower(user_email) in (select e from email_set)
  returning 1
)
, del_wait as (
  delete from public.launch_waitlist
   where lower(email) in (select e from email_set)
  returning 1
)
, del_techs as (
  delete from public.techs
   where lower(email) in (select e from email_set)
  returning 1
)
, del_arch as (
  delete from public.archived_techs
   where lower(coalesce(email,'')) in (select e from email_set)
  returning 1
)
, del_users as (
  delete from public.users
   where lower(email) in (select e from email_set)
  returning 1
)
-- auth last so FK references from public.* don't fight us. Requires
-- service-role / SQL editor (which runs as postgres). Cascades through
-- auth.identities / auth.sessions / auth.refresh_tokens automatically.
, del_auth as (
  delete from auth.users
   where lower(email) in (select e from email_set)
  returning 1
)
select
  (select count(*) from del_favs_user) as favorites_user_side,
  (select count(*) from del_favs_tech) as favorites_tech_side,
  (select count(*) from del_inspo)     as user_inspo,
  (select count(*) from del_board)     as board_posts,
  (select count(*) from del_push)      as push_subscriptions,
  (select count(*) from del_comps)     as tech_comps,
  (select count(*) from del_msgs)      as contact_anne_messages,
  (select count(*) from del_fb)        as feedback,
  (select count(*) from del_wait)      as launch_waitlist,
  (select count(*) from del_techs)     as techs,
  (select count(*) from del_arch)      as archived_techs,
  (select count(*) from del_users)     as users,
  (select count(*) from del_auth)      as auth_users
;


-- ── 3. AFTER — re-run block 1 above to confirm every row count is 0. ────────


-- ── BACKLOG ─────────────────────────────────────────────────────────────────
-- Three tables added since wipe-test-accounts.sql was written are now wiped
-- here but not in the canonical script:
--   * public.contact_anne_messages
--   * public.feedback
--   * public.launch_waitlist
-- Worth backporting into wipe-test-accounts.sql so future bulk wipes don't
-- leave orphaned message/feedback/waitlist rows pinned to deleted users.
-- ────────────────────────────────────────────────────────────────────────────
