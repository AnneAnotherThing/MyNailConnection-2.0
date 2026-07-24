-- ============================================================================
-- MNC, DELETE ALL "ANNE" ACCOUNTS  (2026-07-23)
-- ============================================================================
-- Wipes every Anne-owned account so signup can be re-tested from scratch:
--   * every auth email containing "anne"  (annewilson1021@gmail.com, its
--     +aliases, anne@mynailconnection.com, anne@hive-rise.com, ...)
--   * plus any phone accounts tied to those emails
--
-- HEADS UP:
--   * annewilson1021@gmail.com is the ADMIN email in is_admin(). Deleting the
--     account row does NOT remove admin rights from the function, so
--     re-signing-up with that email makes you admin again. A phone-only
--     account will NOT be admin until we add your phone/email to is_admin().
--   * The tech "Anne MyNailConnection" uses email monica@mynailconnection.com,
--     which does NOT contain "anne", so it is NOT auto-included. If you want
--     it gone too, add 'monica@mynailconnection.com' to extra_emails below.
--
-- Runs in the Supabase SQL editor (as postgres). Safe to re-run.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════
-- STEP 1 — REVIEW (run first; reads only). Shows every account that WILL be
-- deleted, plus the monica@ tech flagged separately so you can decide.
-- ════════════════════════════════════════════════════════════════════════
select
  a.created_at::timestamp(0) as created,
  a.email,
  a.phone,
  u.role  as user_role,
  case when t.id is not null then 'YES' else '' end as is_tech,
  u.name,
  case
    when lower(coalesce(a.email,'')) like '%anne%' then 'will delete'
    when lower(coalesce(u.name,'')) like '%anne%' or lower(coalesce(t.name,'')) like '%anne%'
      then 'NAME says Anne, email does not -> add email below if you want it gone'
    else ''
  end as decision
from auth.users a
left join public.users u
       on lower(coalesce(u.email,'')) = lower(coalesce(a.email,''))
       or regexp_replace(coalesce(u.phone,''),'\D','','g') = regexp_replace(coalesce(a.phone,''),'\D','','g')
left join public.techs t
       on lower(coalesce(t.email,'')) = lower(coalesce(a.email,''))
       or regexp_replace(coalesce(t.phone,''),'\D','','g') = regexp_replace(coalesce(a.phone,''),'\D','','g')
where lower(coalesce(a.email,'')) like '%anne%'
   or lower(coalesce(u.name,'')) like '%anne%'
   or lower(coalesce(t.name,'')) like '%anne%'
order by a.created_at desc;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 2 — DELETE  (uncomment the whole block and run)
-- Targets every auth account whose email contains "anne", plus anything you
-- add to extra_emails (e.g. the monica@ tech).
-- ════════════════════════════════════════════════════════════════════════
--
-- with extra_emails (e) as (values
--   -- add specific non-"anne" emails to also delete, or leave the dummy row:
--   ('__none__')
--   -- , ('monica@mynailconnection.com')
-- ),
-- junk_auth as (
--   select a.id,
--          lower(coalesce(a.email,''))                        as email_l,
--          regexp_replace(coalesce(a.phone,''),'\D','','g')   as pdigits
--   from auth.users a
--   where lower(coalesce(a.email,'')) like '%anne%'
--      or lower(coalesce(a.email,'')) in (select lower(btrim(e)) from extra_emails)
-- ),
-- ids   as (select id from junk_auth),
-- mails as (select email_l from junk_auth where email_l <> ''),
-- fones as (select pdigits from junk_auth where pdigits <> '')
--
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
-- , d_techs as (delete from public.techs
--     where lower(coalesce(email,'')) in (select email_l from mails)
--        or regexp_replace(coalesce(phone,''),'\D','','g') in (select pdigits from fones)
--     returning 1)
-- , d_users as (delete from public.users
--     where lower(coalesce(email,'')) in (select email_l from mails)
--        or regexp_replace(coalesce(phone,''),'\D','','g') in (select pdigits from fones)
--     returning 1)
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
-- STEP 3 — re-run STEP 1 to confirm the "anne" rows are gone.
-- Storage photos aren't removable from SQL; clear from the dashboard Storage
-- tab if any Anne tech had uploads.
-- ════════════════════════════════════════════════════════════════════════
