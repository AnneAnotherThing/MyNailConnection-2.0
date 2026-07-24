-- ============================================================================
-- MNC, DELETE TWO TEST PHONE ACCOUNTS  (2026-07-24)
-- ============================================================================
-- Removes every trace of Anne's two test numbers so phone signup can be
-- re-tested from scratch:
--     (480) 699-6166   and   (480) 440-2314
--
-- Matching is on the LAST 10 DIGITS of any stored phone, so it catches
-- every format: +14804402314, 14804402314, 4804402314, (480) 440-2314.
--
-- NOTE: the "no tech profile" error these accounts hit was a REAL app bug
-- (the Bookings screen looked techs up by email only), fixed in the app on
-- 2026-07-24. Deleting these accounts is still fine, they are test junk,
-- but the error was not their fault.
--
-- Runs in the Supabase SQL editor (as postgres). Safe to re-run.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════
-- STEP 1 — REVIEW (reads only). Everything the delete below will touch.
-- ════════════════════════════════════════════════════════════════════════
with targets (digits) as (values ('4806996166'), ('4804402314'))
select
  a.created_at::timestamp(0) as created,
  a.email,
  a.phone,
  u.role  as user_role,
  case when t.id is not null then 'YES' else '' end as is_tech,
  coalesce(u.name, t.name) as name
from auth.users a
left join public.users u
       on right(regexp_replace(coalesce(u.phone,''),'\D','','g'), 10)
        = right(regexp_replace(coalesce(a.phone,''),'\D','','g'), 10)
left join public.techs t
       on right(regexp_replace(coalesce(t.phone,''),'\D','','g'), 10)
        = right(regexp_replace(coalesce(a.phone,''),'\D','','g'), 10)
where right(regexp_replace(coalesce(a.phone,''),'\D','','g'), 10)
      in (select digits from targets)
order by a.created_at desc;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 2 — DELETE. Removes the accounts plus every row keyed to them.
-- ════════════════════════════════════════════════════════════════════════
with targets (digits) as (values ('4806996166'), ('4804402314')),
junk_auth as (
  select a.id,
         lower(coalesce(a.email,''))                                   as email_l,
         right(regexp_replace(coalesce(a.phone,''),'\D','','g'), 10)   as pdigits
  from auth.users a
  where right(regexp_replace(coalesce(a.phone,''),'\D','','g'), 10)
        in (select digits from targets)
),
ids   as (select id from junk_auth),
mails as (select email_l from junk_auth where email_l <> ''),
fones as (select digits as pdigits from targets)

, d_fav_u as (delete from public.user_favorites
    where lower(coalesce(user_email,'')) in (select email_l from mails)
       or user_id in (select id from ids)
       or right(regexp_replace(coalesce(user_email,''),'\D','','g'), 10) in (select pdigits from fones)
    returning 1)
, d_inspo as (delete from public.user_inspo
    where lower(coalesce(user_email,'')) in (select email_l from mails)
       or user_id in (select id from ids)
       or right(regexp_replace(coalesce(user_email,''),'\D','','g'), 10) in (select pdigits from fones)
    returning 1)
, d_book as (delete from public.bookings
    where client_id in (select id from ids)
       or right(regexp_replace(coalesce(client_phone,''),'\D','','g'), 10) in (select pdigits from fones)
       or tech_id in (select id from public.techs
                       where right(regexp_replace(coalesce(phone,''),'\D','','g'), 10) in (select pdigits from fones))
    returning 1)
, d_push as (delete from public.push_subscriptions
    where lower(coalesce(user_id,'')) in (select email_l from mails)
       or right(regexp_replace(coalesce(user_id,''),'\D','','g'), 10) in (select pdigits from fones)
    returning 1)
, d_techs as (delete from public.techs
    where right(regexp_replace(coalesce(phone,''),'\D','','g'), 10) in (select pdigits from fones)
    returning 1)
, d_users as (delete from public.users
    where right(regexp_replace(coalesce(phone,''),'\D','','g'), 10) in (select pdigits from fones)
    returning 1)
, d_auth as (delete from auth.users where id in (select id from ids) returning 1)
select
  (select count(*) from d_auth)  as auth_users_deleted,
  (select count(*) from d_users) as users_deleted,
  (select count(*) from d_techs) as techs_deleted,
  (select count(*) from d_book)  as bookings_deleted,
  (select count(*) from d_inspo) as inspo_deleted,
  (select count(*) from d_fav_u) as favorites_deleted,
  (select count(*) from d_push)  as push_subs_deleted;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 3 — re-run STEP 1; it should return zero rows.
-- ════════════════════════════════════════════════════════════════════════
