-- ============================================================================
-- MNC, FULL TEST RESET FOR ANNE — 2026-09-06 (pre-3.0.4 end-to-end test)
-- ============================================================================
-- Successor to cleanup-anne-accounts.sql. Two differences:
--   1. Anne's phone (480-699-6166) is FILLED IN, not '__none__'. The likely
--      reason the last cleanup left orphaned appointments: the script keys
--      phone matches off the extra_phones list, and the placeholder matches
--      nothing, so every phone-keyed row (which is all of them since the
--      phone-only cutover) sailed through.
--   2. Adds the tables the old script missed: contact_anne_messages,
--      founders_feedback, events (analytics), and the TECH side of
--      user_inspo (rows where other people hearted her photos).
--
-- HEADS UP:
--   * ADMIN DIES WITH THE RESET. Since sweep-fixes-2026-09-04, is_admin()
--     means "a public.users row with role 'Admin' matching your email or
--     phone" — and this script deletes that row. Re-signup does NOT restore
--     it (the old "hardcoded email = always admin" behavior is gone). After
--     re-signing up, run STEP 4 below or the admin dashboards will show
--     empty/flat data while looking signed-in.
--   * The Apple subscription survives account deletion by design — Apple
--     bills the Apple ID, not the MNC account. Yours is CANCELLED and active
--     until Oct 4. When the fresh account taps Subscribe (or restores),
--     RevenueCat fires TRANSFER and the (now correctly-pointed!) webhook
--     re-grants paid to the new row. That transfer IS part of the test.
--   * Storage photos can't be deleted from SQL (protect_delete trigger);
--     sweep the Storage tab manually if you want the files gone too.
--
-- Runs in the Supabase SQL editor (project nwqnakoongrorbwnrqzc, as
-- postgres). Safe to re-run.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════
-- STEP 1 — REVIEW (reads only). Every account this will delete, including
-- orphaned users/techs rows with no auth row left.
-- ════════════════════════════════════════════════════════════════════════
-- (2026-09-06: rewritten as a UNION. The old FULL OUTER JOIN version dies
-- with "FULL JOIN is only supported with merge-joinable or hash-joinable
-- join conditions" — Postgres refuses full joins over OR-conditions — which
-- also means the old script's review step never actually ran.)
with extra_emails (e) as (values
  ('__none__')
  -- , ('monica@mynailconnection.com')   -- "Anne MyNailConnection" test tech
),
extra_phones (p) as (values
  ('4806996166')
),
tp as (select right(regexp_replace(p,'\D','','g'),10) as d from extra_phones
        where length(regexp_replace(p,'\D','','g')) >= 10),
m as (select lower(btrim(e)) as e from extra_emails where e <> '__none__')
select 'auth.users' as source, a.created_at::timestamp(0) as created,
       a.email, a.phone::text as phone, null::text as name, null::text as role,
       'will delete' as note
from auth.users a
where lower(coalesce(a.email,'')) like '%anne%'
   or lower(coalesce(a.email,'')) in (select e from m)
   or right(regexp_replace(coalesce(a.phone::text,''),'\D','','g'),10) in (select d from tp)
union all
select 'public.users', u.joined::timestamptz::timestamp(0),
       u.email, u.phone, u.name, u.role,
       case when exists (select 1 from auth.users a
              where lower(coalesce(a.email,'')) = lower(coalesce(u.email,'*'))
                 or (right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10) <> ''
                     and right(regexp_replace(coalesce(a.phone::text,''),'\D','','g'),10)
                       = right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10)))
            then 'will delete'
            else 'ORPHAN (no auth row — old delete missed it)' end
from public.users u
where lower(coalesce(u.email,'')) like '%anne%'
   or lower(coalesce(u.email,'')) in (select e from m)
   or right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10) in (select d from tp)
   or lower(coalesce(u.name,'')) like '%anne%'
union all
select 'public.techs', t.created_at::timestamp(0),
       t.email, t.phone, t.name, 'tech',
       case when exists (select 1 from auth.users a
              where lower(coalesce(a.email,'')) = lower(coalesce(t.email,'*'))
                 or (right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10) <> ''
                     and right(regexp_replace(coalesce(a.phone::text,''),'\D','','g'),10)
                       = right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10)))
            then 'will delete'
            else 'ORPHAN (no auth row — old delete missed it)' end
from public.techs t
where lower(coalesce(t.email,'')) like '%anne%'
   or lower(coalesce(t.email,'')) in (select e from m)
   or right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10) in (select d from tp)
   or lower(coalesce(t.name,'')) like '%anne%'
order by source, created desc nulls last;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 2 — DELETE. Review STEP 1's output first, then run this block.
-- Builds the identity closure (auth ids + every email + every phone from
-- ALL matched rows), then deletes children before parents.
-- ════════════════════════════════════════════════════════════════════════

with extra_emails (e) as (values
  ('__none__')
  -- , ('monica@mynailconnection.com')
),
extra_phones (p) as (values
  ('4806996166')
),

-- ── Identity closure ────────────────────────────────────────────────
tp as (select right(regexp_replace(p,'\D','','g'),10) as d from extra_phones
        where length(regexp_replace(p,'\D','','g')) >= 10),
junk_auth as (
  select a.id,
         lower(coalesce(a.email,''))                                 as email_l,
         right(regexp_replace(coalesce(a.phone,''),'\D','','g'),10)  as p10
  from auth.users a
  where lower(coalesce(a.email,'')) like '%anne%'
     or lower(coalesce(a.email,'')) in (select lower(btrim(e)) from extra_emails)
     or right(regexp_replace(coalesce(a.phone,''),'\D','','g'),10) in (select d from tp)
),
ids as (select id from junk_auth),
mails0 as (
  select email_l from junk_auth where email_l <> ''
  union select lower(btrim(e)) from extra_emails where e <> '__none__'
),
fones0 as (
  select p10 as d from junk_auth where p10 <> ''
  union select d from tp
),
junk_users as (
  select u.id, lower(coalesce(u.email,'')) as email_l,
         right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10) as p10
  from public.users u
  where u.id in (select id from ids)
     or lower(coalesce(u.email,'')) in (select email_l from mails0)
     or right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10) in (select d from fones0)
),
junk_techs as (
  select t.id, lower(coalesce(t.email,'')) as email_l,
         right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10) as p10
  from public.techs t
  where lower(coalesce(t.email,'')) in (select email_l from mails0)
     or right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10) in (select d from fones0)
),
mails as (
  select email_l from mails0
  union select email_l from junk_users where email_l <> ''
  union select email_l from junk_techs where email_l <> ''
),
fones as (
  select d from fones0
  union select p10 from junk_users where p10 <> ''
  union select p10 from junk_techs where p10 <> ''
),
-- push_subscriptions.user_id / notifications.recipient shapes:
-- lowercased email OR '+1' + last-10 digits (push_identity()).
push_keys as (
  select email_l as k from mails
  union select '+1' || d from fones
  union select '1'  || d from fones
  union select d         from fones
),

-- ── Booking engine ──────────────────────────────────────────────────
-- Bookings die whether she was the CLIENT (id, email, or phone on the
-- row) or the TECH. This is the fix for orphaned appointments: rows whose
-- client_id points at an old deleted auth id but carry her phone in
-- client_phone match too.
d_book as (delete from public.bookings
    where client_id in (select id from ids)
       or lower(coalesce(client_email,'')) in (select email_l from mails)
       or right(regexp_replace(coalesce(client_phone,''),'\D','','g'),10) in (select d from fones)
       or tech_id in (select id from junk_techs)
    returning 1),
d_standing as (delete from public.standing_appointments
    where tech_id in (select id from junk_techs)
       or client_id in (select id from ids)
       or lower(coalesce(client_email,'')) in (select email_l from mails)
    returning 1),
d_notes as (delete from public.booking_notes
    where tech_id in (select id from junk_techs) returning 1),
d_svcs as (delete from public.tech_services
    where tech_id in (select id from junk_techs) returning 1),
d_avail as (delete from public.tech_availability
    where tech_id in (select id from junk_techs) returning 1),
d_timeoff as (delete from public.tech_time_off
    where tech_id in (select id from junk_techs) returning 1),
d_block as (delete from public.blocked_clients
    where tech_id in (select id from junk_techs)
       or lower(coalesce(client_email,'')) in (select email_l from mails)
    returning 1),

-- ── Social / content ────────────────────────────────────────────────
d_fav_u as (delete from public.user_favorites
    where lower(coalesce(user_email,'')) in (select email_l from mails)
       or user_id in (select id from ids) returning 1),
d_fav_t as (delete from public.user_favorites
    where lower(coalesce(tech_email,'')) in (select email_l from mails) returning 1),
-- BOTH sides of inspo now (new 2026-09-06): rows SHE saved (user side) and
-- rows where anyone hearted HER photos (tech side) — the latter were the
-- old script's blind spot, stale hearts pointing at dead photo URLs.
d_inspo as (delete from public.user_inspo
    where lower(coalesce(user_email,'')) in (select email_l from mails)
       or user_id in (select id from ids)
       or lower(coalesce(tech_email,'')) in (select email_l from mails)
       or tech_id in (select id from junk_techs)
    returning 1),
d_board as (delete from public.board_posts
    where lower(coalesce(tech_id,'')) in (select email_l from mails)
       or tech_uuid in (select id from junk_techs) returning 1),

-- ── Push / notifications / analytics ────────────────────────────────
d_push as (delete from public.push_subscriptions
    where lower(coalesce(user_id,'')) in (select k from push_keys) returning 1),
d_notif as (delete from public.notifications
    where lower(coalesce(recipient,'')) in (select k from push_keys) returning 1),
d_plog as (delete from public.push_log
    where lower(coalesce(recipient,'')) in (select k from push_keys) returning 1),
d_tevents as (delete from public.tech_events
    where lower(coalesce(tech_email,''))  in (select email_l from mails)
       or lower(coalesce(actor_email,'')) in (select email_l from mails) returning 1),
-- events: granular analytics rows tied to her identity (new 2026-09-06)
d_events as (delete from public.events
    where lower(coalesce(user_email,'')) in (select email_l from mails) returning 1),

-- ── Messages / feedback (new 2026-09-06) ────────────────────────────
d_contact as (delete from public.contact_anne_messages
    where lower(coalesce(user_email,'')) in (select email_l from mails)
       or right(regexp_replace(coalesce(phone,''),'\D','','g'),10) in (select d from fones)
    returning 1),
d_ffb as (delete from public.founders_feedback
    where lower(coalesce(email,'')) in (select email_l from mails) returning 1),
d_feedback as (delete from public.feedback
    where lower(coalesce(user_email,'')) in (select email_l from mails) returning 1),

-- ── Billing ─────────────────────────────────────────────────────────
d_comps as (delete from public.tech_comps
    where lower(coalesce(email,'')) in (select email_l from mails) returning 1),

-- ── Parents last ────────────────────────────────────────────────────
d_techs as (delete from public.techs
    where id in (select id from junk_techs) returning 1),
d_users as (delete from public.users
    where id in (select id from junk_users) returning 1),
d_auth as (delete from auth.users where id in (select id from ids) returning 1)

select
  (select count(*) from d_auth)     as auth_users,
  (select count(*) from d_users)    as users,
  (select count(*) from d_techs)    as techs,
  (select count(*) from d_book)     as bookings,
  (select count(*) from d_standing) as standing_appts,
  (select count(*) from d_notes)    as booking_notes,
  (select count(*) from d_svcs)     as services,
  (select count(*) from d_avail)    as availability,
  (select count(*) from d_timeoff)  as time_off,
  (select count(*) from d_block)    as blocklist,
  (select count(*) from d_fav_u) + (select count(*) from d_fav_t) as favorites,
  (select count(*) from d_inspo)    as inspo,
  (select count(*) from d_board)    as board_posts,
  (select count(*) from d_push)     as push_subs,
  (select count(*) from d_notif)    as notifications,
  (select count(*) from d_plog)     as push_log,
  (select count(*) from d_tevents)  as tech_events,
  (select count(*) from d_events)   as analytics_events,
  (select count(*) from d_contact)  as contact_msgs,
  (select count(*) from d_ffb)      as founders_feedback,
  (select count(*) from d_feedback) as feedback,
  (select count(*) from d_comps)    as comps;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 3 — re-run STEP 1: every row should be gone (0 rows).
-- Then optionally: Storage tab → clear any of Anne's uploaded photos.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- STEP 4 — RE-GRANT ADMIN (run AFTER you re-sign up in the app).
-- The reset deleted the users row that made you admin; your fresh signup
-- came back as a plain tech/client. This flips it back. is_admin() matches
-- by email OR phone, so the phone leg makes your phone-only session admin
-- too. Expect "UPDATE 1" (or 2 if you made both an email and a phone
-- account).
-- ════════════════════════════════════════════════════════════════════════
update public.users
   set role = 'Admin'
 where lower(coalesce(email,'')) = 'annewilson1021@gmail.com'
    or right(public.phone_digits(coalesce(phone,'')),10) = '4806996166';
-- Then sign OUT and back IN on admin-stats.html / admin-feedback.html so
-- the session re-evaluates is_admin(), and the numbers come back.
