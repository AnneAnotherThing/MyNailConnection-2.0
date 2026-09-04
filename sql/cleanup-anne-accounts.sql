-- ============================================================================
-- MNC, DELETE ALL "ANNE" ACCOUNTS — PHONE-AWARE, EVERYTHING-RELATED
-- (rewritten 2026-09-04; original 2026-07-23 was email-only)
-- ============================================================================
-- Wipes every Anne-owned account so signup can be re-tested from scratch:
--   * every auth email containing "anne" (annewilson1021@gmail.com, its
--     +aliases, anne@mynailconnection.com, anne@hive-rise.com, ...)
--   * every auth/users/techs row matching the phone numbers you list in
--     extra_phones below
--   * and EVERYTHING attached to those identities: bookings (both as client
--     and as tech), standing appointments, services, hours, time off,
--     booking notes, blocklist rows, favorites, inspo, board posts, push
--     subscriptions, notification history, push log, comps, analytics events.
--
-- WHY THE REWRITE: the 2026-07-23 version keyed everything off
-- email LIKE '%anne%'. After the phone-only cutover Anne's test accounts are
-- often PHONE-keyed (email null), so the script matched nothing, the old
-- techs/users rows survived, and the next phone signup re-attached to the
-- old tech row — old appointments and all. "Deleted" accounts kept their
-- calendars. This version matches by phone too and deletes bookings by
-- client_phone/client_email as well as by id, so nothing rides through.
--
-- HEADS UP:
--   * annewilson1021@gmail.com is the ADMIN email in is_admin(). Deleting the
--     account row does NOT remove admin rights from the function, so
--     re-signing-up with that email makes you admin again. A phone-only
--     account will NOT be admin until we add your phone/email to is_admin().
--   * The tech "Anne MyNailConnection" uses email monica@mynailconnection.com,
--     which does NOT contain "anne", so it is NOT auto-included. Add it to
--     extra_emails if you want it gone.
--   * If the account had an ACTIVE Apple subscription, deleting the row does
--     not cancel it — Apple keeps billing your Apple ID. Cancel in iOS
--     Settings → Apple ID → Subscriptions. On the next signup RevenueCat
--     fires a TRANSFER event and the webhook re-grants paid to the new row.
--
-- Runs in the Supabase SQL editor (as postgres). Safe to re-run.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════
-- STEP 0 — EDIT YOUR TARGETS.
-- extra_phones: digits only, 10 digits is fine ('4805551234'). Any account
-- (auth, users, or techs) whose phone ends in those 10 digits is included.
-- extra_emails: exact emails that don't contain "anne" but should die too.
-- These two lists are pasted into BOTH the review and the delete below,
-- keep them identical in both places.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- STEP 1 — REVIEW (run first; reads only). Shows every account that WILL be
-- deleted — auth rows AND orphaned users/techs rows with no auth left.
-- ════════════════════════════════════════════════════════════════════════
with extra_emails (e) as (values
  ('__none__')
  -- , ('monica@mynailconnection.com')
),
extra_phones (p) as (values
  ('__none__')
  -- , ('4805551234')      -- ← Anne: put your real number(s) here
),
tp as (select right(regexp_replace(p,'\D','','g'),10) as d from extra_phones
        where length(regexp_replace(p,'\D','','g')) >= 10)
select
  coalesce(a.created_at, u.joined::timestamptz)::timestamp(0) as created,
  coalesce(a.email, u.email, t.email)  as email,
  coalesce(a.phone, u.phone, t.phone)  as phone,
  u.role                               as user_role,
  case when t.id is not null then 'YES' else '' end as is_tech,
  coalesce(u.name, t.name)             as name,
  case when a.id is null then 'ORPHAN (no auth row — old delete missed it)'
       else 'will delete' end          as decision
from public.users u
full outer join auth.users a
       on lower(coalesce(u.email,'')) = lower(coalesce(a.email,''))
       or (right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10) <> ''
           and right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10)
             = right(regexp_replace(coalesce(a.phone,''),'\D','','g'),10))
full outer join public.techs t
       on lower(coalesce(t.email,'')) = lower(coalesce(a.email,'') )
       or lower(coalesce(t.email,'')) = lower(coalesce(u.email,''))
       or (right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10) <> ''
           and right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10)
              in (right(regexp_replace(coalesce(a.phone,''),'\D','','g'),10),
                  right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10)))
where lower(coalesce(a.email, u.email, t.email, '')) like '%anne%'
   or lower(coalesce(a.email, u.email, t.email, '')) in (select lower(btrim(e)) from extra_emails)
   or right(regexp_replace(coalesce(a.phone, u.phone, t.phone, ''),'\D','','g'),10) in (select d from tp)
   or lower(coalesce(u.name, t.name, '')) like '%anne%'
order by created desc nulls last;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 2 — DELETE  (uncomment the whole block and run).
-- Builds the full identity set (auth ids + every email + every phone from
-- ALL matched rows, so a phone-only techs row contributes its email and
-- vice versa), then deletes children before parents.
-- ════════════════════════════════════════════════════════════════════════
--
-- with extra_emails (e) as (values
--   ('__none__')
--   -- , ('monica@mynailconnection.com')
-- ),
-- extra_phones (p) as (values
--   ('__none__')
--   -- , ('4805551234')      -- ← keep identical to STEP 1
-- ),
--
-- -- ── Identity closure ────────────────────────────────────────────────
-- tp as (select right(regexp_replace(p,'\D','','g'),10) as d from extra_phones
--         where length(regexp_replace(p,'\D','','g')) >= 10),
-- junk_auth as (
--   select a.id,
--          lower(coalesce(a.email,''))                                 as email_l,
--          right(regexp_replace(coalesce(a.phone,''),'\D','','g'),10)  as p10
--   from auth.users a
--   where lower(coalesce(a.email,'')) like '%anne%'
--      or lower(coalesce(a.email,'')) in (select lower(btrim(e)) from extra_emails)
--      or right(regexp_replace(coalesce(a.phone,''),'\D','','g'),10) in (select d from tp)
-- ),
-- ids as (select id from junk_auth),
-- mails0 as (
--   select email_l from junk_auth where email_l <> ''
--   union select lower(btrim(e)) from extra_emails where e <> '__none__'
-- ),
-- fones0 as (
--   select p10 as d from junk_auth where p10 <> ''
--   union select d from tp
-- ),
-- junk_users as (
--   select u.id, lower(coalesce(u.email,'')) as email_l,
--          right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10) as p10
--   from public.users u
--   where u.id in (select id from ids)
--      or lower(coalesce(u.email,'')) in (select email_l from mails0)
--      or right(regexp_replace(coalesce(u.phone,''),'\D','','g'),10) in (select d from fones0)
-- ),
-- junk_techs as (
--   select t.id, lower(coalesce(t.email,'')) as email_l,
--          right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10) as p10
--   from public.techs t
--   where lower(coalesce(t.email,'')) in (select email_l from mails0)
--      or right(regexp_replace(coalesce(t.phone,''),'\D','','g'),10) in (select d from fones0)
-- ),
-- mails as (
--   select email_l from mails0
--   union select email_l from junk_users where email_l <> ''
--   union select email_l from junk_techs where email_l <> ''
-- ),
-- fones as (
--   select d from fones0
--   union select p10 from junk_users where p10 <> ''
--   union select p10 from junk_techs where p10 <> ''
-- ),
-- -- push_subscriptions.user_id / notifications.recipient shapes:
-- -- lowercased email OR '+1' + last-10 digits (push_identity()).
-- push_keys as (
--   select email_l as k from mails
--   union select '+1' || d from fones
--   union select '1'  || d from fones
--   union select d         from fones
-- ),
--
-- -- ── Booking engine ──────────────────────────────────────────────────
-- -- Bookings die whether she was the CLIENT (id, email, or phone on the
-- -- row) or the TECH. This is the fix for "it's holding on to these
-- -- appointments": rows whose client_id pointed at some other/old auth id
-- -- but carry her phone in client_phone now match too.
-- d_book as (delete from public.bookings
--     where client_id in (select id from ids)
--        or lower(coalesce(client_email,'')) in (select email_l from mails)
--        or right(regexp_replace(coalesce(client_phone,''),'\D','','g'),10) in (select d from fones)
--        or tech_id in (select id from junk_techs)
--     returning 1),
-- d_standing as (delete from public.standing_appointments
--     where tech_id in (select id from junk_techs)
--        or client_id in (select id from ids)
--        or lower(coalesce(client_email,'')) in (select email_l from mails)
--     returning 1),
-- d_notes as (delete from public.booking_notes
--     where tech_id in (select id from junk_techs) returning 1),
-- d_svcs as (delete from public.tech_services
--     where tech_id in (select id from junk_techs) returning 1),
-- d_avail as (delete from public.tech_availability
--     where tech_id in (select id from junk_techs) returning 1),
-- d_timeoff as (delete from public.tech_time_off
--     where tech_id in (select id from junk_techs) returning 1),
-- d_block as (delete from public.blocked_clients
--     where tech_id in (select id from junk_techs)
--        or lower(coalesce(client_email,'')) in (select email_l from mails)
--     returning 1),
--
-- -- ── Social / content ────────────────────────────────────────────────
-- d_fav_u as (delete from public.user_favorites
--     where lower(coalesce(user_email,'')) in (select email_l from mails)
--        or user_id in (select id from ids) returning 1),
-- d_fav_t as (delete from public.user_favorites
--     where lower(coalesce(tech_email,'')) in (select email_l from mails) returning 1),
-- d_inspo as (delete from public.user_inspo
--     where lower(coalesce(user_email,'')) in (select email_l from mails)
--        or user_id in (select id from ids) returning 1),
-- d_board as (delete from public.board_posts
--     where lower(coalesce(tech_id,'')) in (select email_l from mails) returning 1),
--
-- -- ── Push / notifications / analytics ────────────────────────────────
-- d_push as (delete from public.push_subscriptions
--     where lower(coalesce(user_id,'')) in (select k from push_keys) returning 1),
-- d_notif as (delete from public.notifications
--     where lower(coalesce(recipient,'')) in (select k from push_keys) returning 1),
-- d_plog as (delete from public.push_log
--     where lower(coalesce(recipient,'')) in (select k from push_keys) returning 1),
-- d_tevents as (delete from public.tech_events
--     where lower(coalesce(tech_email,''))  in (select email_l from mails)
--        or lower(coalesce(actor_email,'')) in (select email_l from mails) returning 1),
--
-- -- ── Billing / misc ──────────────────────────────────────────────────
-- d_comps as (delete from public.tech_comps
--     where lower(coalesce(email,'')) in (select email_l from mails) returning 1),
-- d_feedback as (delete from public.feedback
--     where lower(coalesce(user_email,'')) in (select email_l from mails) returning 1),
--
-- -- ── Parents last ────────────────────────────────────────────────────
-- d_techs as (delete from public.techs
--     where id in (select id from junk_techs) returning 1),
-- d_users as (delete from public.users
--     where id in (select id from junk_users) returning 1),
-- d_auth as (delete from auth.users where id in (select id from ids) returning 1)
--
-- select
--   (select count(*) from d_auth)     as auth_users,
--   (select count(*) from d_users)    as users,
--   (select count(*) from d_techs)    as techs,
--   (select count(*) from d_book)     as bookings,
--   (select count(*) from d_standing) as standing_appts,
--   (select count(*) from d_notes)    as booking_notes,
--   (select count(*) from d_svcs)     as services,
--   (select count(*) from d_avail)    as availability,
--   (select count(*) from d_timeoff)  as time_off,
--   (select count(*) from d_block)    as blocklist,
--   (select count(*) from d_fav_u) + (select count(*) from d_fav_t) as favorites,
--   (select count(*) from d_inspo)    as inspo,
--   (select count(*) from d_board)    as board_posts,
--   (select count(*) from d_push)     as push_subs,
--   (select count(*) from d_notif)    as notifications,
--   (select count(*) from d_plog)     as push_log,
--   (select count(*) from d_tevents)  as tech_events,
--   (select count(*) from d_comps)    as comps,
--   (select count(*) from d_feedback) as feedback;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 3 — re-run STEP 1 to confirm everything reads "0 rows".
-- Storage photos aren't removable from SQL; clear from the dashboard Storage
-- tab if any Anne tech had uploads.
-- ════════════════════════════════════════════════════════════════════════
