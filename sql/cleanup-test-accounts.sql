-- ============================================================================
-- MNC, CLEAN UP JUNK TEST ACCOUNTS  (2026-07-23)
-- ============================================================================
-- Removes the throwaway accounts created while testing signup, EMAIL and
-- PHONE ones. Supersedes the email-only wipe-test-accounts.sql: phone-first
-- signups have no email, so they can't be targeted by email alone.
--
-- HOW TO USE:
--   1. Run STEP 1 (the review). It changes nothing. It lists every auth
--      account newest-first so you can see exactly what's junk, phone and
--      email both, and which have a profile/role.
--   2. In STEP 2, fill the junk_emails and junk_phones lists with what you
--      saw in step 1. Anne's "+alias" gmails are auto-included.
--   3. Uncomment and run STEP 2 to delete.
--   4. Re-run STEP 1 to confirm they're gone.
--
-- SAFE: deletes only what the junk lists resolve to. Real techs (Leslie, the
--   onboarded 17) and real clients are never touched unless you list them.
--   Runs in the Supabase SQL editor (as postgres); won't work from the app.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════
-- STEP 1 — REVIEW (run this first, it only reads)
-- Every auth account, newest first, with its profile + role. Eyeball it and
-- note the junk emails/phones for step 2.
-- ════════════════════════════════════════════════════════════════════════
select
  a.created_at::timestamp(0)                              as created,
  a.email,
  a.phone,
  u.role                                                  as user_role,
  case when t.id is not null then 'YES' else '' end       as is_tech,
  u.name,
  case when lower(coalesce(a.email,'')) like 'annewilson1021+%@gmail.com'
       then 'auto-junk (alias)' else '' end               as note
from auth.users a
left join public.users u
       on lower(coalesce(u.email,'')) = lower(coalesce(a.email,''))
       or regexp_replace(coalesce(u.phone,''),'\D','','g') = regexp_replace(coalesce(a.phone,''),'\D','','g')
left join public.techs t
       on lower(coalesce(t.email,'')) = lower(coalesce(a.email,''))
       or regexp_replace(coalesce(t.phone,''),'\D','','g') = regexp_replace(coalesce(a.phone,''),'\D','','g')
order by a.created_at desc;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 2 — DELETE  (fill the lists, then uncomment the whole block and run)
-- ════════════════════════════════════════════════════════════════════════
--
-- with junk_emails (e) as (values
--   -- paste junk emails here, one per line, e.g.:
--   ('test1@example.com'),
--   ('annewilson1021+zztest@gmail.com')
-- ),
-- junk_phones (p) as (values
--   -- paste junk phone numbers here (any format), e.g.:
--   ('(602) 555-1234'),
--   ('+16025559999')
-- ),
-- -- Resolve every targeted auth account: matches an email in the list, a
-- -- phone in the list, OR one of Anne's +alias test gmails.
-- junk_auth as (
--   select a.id,
--          lower(coalesce(a.email,''))                            as email_l,
--          regexp_replace(coalesce(a.phone,''),'\D','','g')       as pdigits
--   from auth.users a
--   where lower(coalesce(a.email,'')) in (select lower(btrim(e)) from junk_emails)
--      or regexp_replace(coalesce(a.phone,''),'\D','','g')
--           in (select regexp_replace(btrim(p),'\D','','g') from junk_phones)
--      or lower(coalesce(a.email,'')) like 'annewilson1021+%@gmail.com'
-- ),
-- ids   as (select id from junk_auth),
-- mails as (select email_l from junk_auth where email_l <> ''),
-- fones as (select pdigits from junk_auth where pdigits <> '')
--
-- -- Children first. user_inspo / user_favorites cascade from auth.users via
-- -- their user_id FK, but legacy rows keyed only on email don't, so clear
-- -- both sides explicitly.
-- , d_fav_u as (delete from public.user_favorites
--     where lower(coalesce(user_email,'')) in (select email_l from mails)
--        or user_id in (select id from ids) returning 1)
-- , d_fav_t as (delete from public.user_favorites
--     where lower(coalesce(tech_email,'')) in (select email_l from mails) returning 1)
-- , d_inspo as (delete from public.user_inspo
--     where lower(coalesce(user_email,'')) in (select email_l from mails)
--        or user_id in (select id from ids) returning 1)
-- , d_book as (delete from public.bookings
--     where client_id in (select id from ids)
--        or tech_id in (select id from public.techs
--                        where lower(coalesce(email,'')) in (select email_l from mails)
--                           or regexp_replace(coalesce(phone,''),'\D','','g') in (select pdigits from fones))
--     returning 1)
-- , d_board as (delete from public.board_posts
--     where lower(coalesce(tech_id,'')) in (select email_l from mails) returning 1)
-- , d_push as (delete from public.push_subscriptions
--     where lower(coalesce(user_id,'')) in (select email_l from mails)
--        or regexp_replace(coalesce(user_id,''),'\D','','g') in (select pdigits from fones)
--     returning 1)
-- , d_comps as (delete from public.tech_comps
--     where lower(coalesce(email,'')) in (select email_l from mails) returning 1)
-- -- Main rows.
-- , d_techs as (delete from public.techs
--     where lower(coalesce(email,'')) in (select email_l from mails)
--        or regexp_replace(coalesce(phone,''),'\D','','g') in (select pdigits from fones)
--     returning 1)
-- , d_users as (delete from public.users
--     where lower(coalesce(email,'')) in (select email_l from mails)
--        or regexp_replace(coalesce(phone,''),'\D','','g') in (select pdigits from fones)
--     returning 1)
-- -- auth.users last (cascades any remaining user_id-keyed children).
-- , d_auth as (delete from auth.users where id in (select id from ids) returning 1)
-- select
--   (select count(*) from d_auth)  as auth_users_deleted,
--   (select count(*) from d_users) as users_deleted,
--   (select count(*) from d_techs) as techs_deleted,
--   (select count(*) from d_book)  as bookings_deleted,
--   (select count(*) from d_inspo) as inspo_deleted,
--   (select count(*) from d_fav_u) as favorites_deleted,
--   (select count(*) from d_board) as board_posts_deleted,
--   (select count(*) from d_push)  as push_subs_deleted,
--   (select count(*) from d_comps) as comps_deleted;


-- ════════════════════════════════════════════════════════════════════════
-- The one known junk TECH ("ZZ TEST, do not book") — safe to include above,
-- or delete on its own by adding its email to junk_emails:
--   annewilson1021+booktech@gmail.com
-- Its storage photos (tech-photos bucket) aren't removable from SQL; clear
-- those from the dashboard Storage tab if you want them gone too.
-- ════════════════════════════════════════════════════════════════════════
