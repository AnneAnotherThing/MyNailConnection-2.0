-- ============================================================================
-- push-check-by-phone.sql  (2026-08-27)
--
-- "Why is this phone not getting notifications?" for ANY account -- tech,
-- client, or an auth record with no profile. Three small queries rather than
-- one clever one, so a wrong answer is obvious instead of hidden.
--
-- EDIT THE NUMBER IN EACH QUERY (it appears once per query, marked <<<).
-- 10 digits, no punctuation. READ-ONLY.
--
-- Column note: push_subscriptions has updated_at, NOT created_at. The row is
-- rewritten on every device re-registration, so it is a "last seen
-- registering" timestamp, not a signup date.
-- ============================================================================


-- ── 1. WHO IS THIS NUMBER? ──────────────────────────────────────────────────
-- Any of the three rows can be missing. auth = can sign in. users/techs =
-- has a profile. The email column is what decides the push key below.
select 'auth.users' as source, a.id::text as id, a.email, a.phone,
       null as name, null as role
from auth.users a
where right(public.phone_digits(a.phone), 10) = '4806996166'          -- <<<
union all
select 'public.users', u.id::text, u.email, u.phone, u.name, u.role
from public.users u
where right(public.phone_digits(u.phone), 10) = '4806996166'          -- <<<
union all
select 'public.techs', t.id::text, t.email, t.phone, t.name, 'tech'
from public.techs t
where right(public.phone_digits(t.phone), 10) = '4806996166';         -- <<<


-- ── 2. IS THERE A PUSH ROW UNDER *ANY* KEY THIS PERSON COULD HAVE? ──────────
-- Matches the E.164 phone key and every email the number resolves to, so a
-- row filed under the "wrong" one still shows up. A row under a key the
-- senders do not use is invisible to send-push and looks exactly like having
-- no row at all -- that distinction is the whole point of this query.
select
  ps.user_id                       as key_it_is_stored_under,
  ps.auth                          as platform,
  case when ps.p256dh = 'native' then 'native token' else 'web push' end as kind,
  left(ps.endpoint, 20) || '…'     as token_head,
  ps.updated_at                    as last_registered
from public.push_subscriptions ps
where right(public.phone_digits(ps.user_id), 10) = '4806996166'       -- <<<
   or lower(ps.user_id) in (
        select lower(email) from public.users
         where email is not null
           and right(public.phone_digits(phone), 10) = '4806996166'   -- <<<
        union
        select lower(email) from public.techs
         where email is not null
           and right(public.phone_digits(phone), 10) = '4806996166'   -- <<<
        union
        select lower(email) from auth.users
         where email is not null
           and right(public.phone_digits(phone), 10) = '4806996166'   -- <<<
      );
-- No rows here = nothing ever registered. The setup checkbox reads this same
-- table, so that is also why it will not tick. Fix registration, not delivery.
--
-- Rows here = copy key_it_is_stored_under into the send-push curl. If the
-- senders address a different string (a tech with an email on techs but not
-- on auth is the classic), that mismatch IS the bug.


-- ── 3. IS IT THIS PERSON, OR EVERY iPHONE? ──────────────────────────────────
-- If ios is absent entirely, Leslie is not special: no iPhone has ever
-- registered, and the cause is the build or the APNs secrets, not her account.
select
  coalesce(auth, 'web/unknown')  as platform,
  count(*)                       as rows,
  count(distinct user_id)        as people,
  max(updated_at)                as newest
from public.push_subscriptions
group by 1
order by 2 desc;
