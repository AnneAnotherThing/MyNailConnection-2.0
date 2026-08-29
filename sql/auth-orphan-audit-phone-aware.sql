-- ============================================================================
-- auth-orphan-audit-phone-aware.sql  (2026-08-27)
--
-- ⚠ REPLACES BUCKET A OF auth-orphan-audit.sql. DO NOT DELETE ANYTHING BASED
--   ON THAT FILE ANY MORE.
--
-- That audit was written 2026-06-13. Phone auth landed 2026-07-23. It finds
-- profiles with:
--
--     left join public.users u on lower(u.email) = lower(au.email)
--     where u.email is null
--
-- For a phone signup au.email is NULL, so lower(au.email) is NULL, so the
-- comparison is NULL, so the join never matches -- and EVERY phone account
-- is reported as an orphan whether or not it has a perfectly good profile
-- row keyed by phone. Acting on that list would delete real, active users.
-- One row in the 2026-08-27 run had signed in that same minute.
--
-- This version resolves the profile by email OR by the last ten digits of
-- the phone, which is how the app actually identifies people.
--
-- READ-ONLY.
-- ============================================================================


-- ── 1. WHO IS ACTUALLY AN ORPHAN ────────────────────────────────────────────
select
  au.id                                   as auth_id,
  coalesce(pu.name, t.name)               as name,
  au.email                                as auth_email,
  au.phone                                as auth_phone,
  coalesce(pu.role, case when t.id is not null then 'tech' end) as role,
  au.created_at,
  au.last_sign_in_at,
  case
    when pu.id is not null or t.id is not null
      then 'HAS A PROFILE — not an orphan, leave alone'
    when coalesce(nullif(btrim(au.phone), ''), '') = '' and au.email is null
      then 'no phone AND no email — unreachable shell'
    when au.last_sign_in_at is null
      then 'never verified a code — abandoned signup, safe to remove'
    else 'TRUE ORPHAN — signed in, never got a profile row'
  end                                     as verdict
from auth.users au
left join lateral (
  select u.id, u.name, u.role
  from public.users u
  where (au.email is not null and lower(u.email) = lower(au.email))
     or (public.phone_digits(au.phone) is not null
         and right(public.phone_digits(u.phone), 10) = right(public.phone_digits(au.phone), 10))
  limit 1
) pu on true
left join lateral (
  select tt.id, tt.name
  from public.techs tt
  where (au.email is not null and lower(tt.email) = lower(au.email))
     or (public.phone_digits(au.phone) is not null
         and right(public.phone_digits(tt.phone), 10) = right(public.phone_digits(au.phone), 10))
  limit 1
) t on true
where pu.id is null and t.id is null          -- comment out to see EVERY account
order by au.last_sign_in_at desc nulls last, au.created_at desc;


-- ── 2. DUPLICATE AUTH RECORDS FOR ONE PHONE ─────────────────────────────────
-- This is the fix-leslie-phone-login.sql failure mode: a sign-in that does not
-- match an existing record makes Supabase mint a SECOND, empty auth user for
-- the same number. The 2026-08-27 data shows the shape -- one account last
-- signed in at 19:54:22 and another was created for the same session at
-- 19:54:37, fifteen seconds later. If anything comes back here, the newer
-- empty row is the junk one and the older one is the real person.
select
  right(public.phone_digits(au.phone), 10)          as last10,
  count(*)                                          as auth_rows,
  array_agg(au.id order by au.created_at)           as ids_oldest_first,
  array_agg(coalesce(au.email, '(no email)') order by au.created_at) as emails,
  array_agg(au.created_at::timestamp(0) order by au.created_at)      as created,
  array_agg(coalesce(au.last_sign_in_at::timestamp(0)::text, 'never')
            order by au.created_at)                 as last_seen
from auth.users au
where public.phone_digits(au.phone) is not null
group by 1
having count(*) > 1
order by 2 desc;


-- ── 3. THE TWILIO BILL FOR ABANDONED SIGNUPS ────────────────────────────────
-- created but never verified = a code was texted and never entered. Each one
-- is a real Twilio Verify charge. Worth watching as a rate, not a cleanup job.
select
  date_trunc('week', created_at)::date               as week,
  count(*)                                           as codes_never_verified
from auth.users
where last_sign_in_at is null
group by 1
order by 1 desc;


-- ── 2B. THE SPLIT IDENTITY SECTION 2 CANNOT SEE  (added 2026-08-28) ─────────
-- Section 2 groups on public.phone_digits(au.phone) and drops every row where
-- that is null. But the Leslie 2026-07-24 case had exactly ONE row with a
-- phone. Her other row was the 2.0-era EMAIL account, and og-auth-bulk-create
-- .sql never wrote a phone column at all -- grep it, there is no `phone` in
-- the insert. So her two rows could never group together, and section 2 is
-- structurally blind to the failure mode it is named after.
--
-- This also explains why section 2 may well return nothing while the problem
-- is real: auth.users carries a UNIQUE constraint on phone, so two LIVE rows
-- can never hold the identical phone string. A same-number duplicate can only
-- exist if the two rows disagree on format, or if one of them has phone NULL.
-- The NULL case is the common one, and it is this query.
--
-- Reads: an email-era auth row and a phone-era auth row that resolve to the
-- SAME human, via a profile row carrying both an email and a phone.
select
  p.name,
  p.email                                    as profile_email,
  p.phone                                    as profile_phone,
  a_mail.id                                  as email_auth_id,
  a_mail.created_at::timestamp(0)            as email_row_created,
  coalesce(a_mail.last_sign_in_at::timestamp(0)::text, 'never') as email_row_last_seen,
  a_phone.id                                 as phone_auth_id,
  a_phone.created_at::timestamp(0)           as phone_row_created,
  coalesce(a_phone.last_sign_in_at::timestamp(0)::text, 'never') as phone_row_last_seen,
  'TWO auth rows, one person — phone login could not see the email row'
                                             as verdict
from (
  select name, email, phone from public.users where email is not null and phone is not null
  union all
  select name, email, phone from public.techs where email is not null and phone is not null
) p
join auth.users a_mail
  on lower(a_mail.email) = lower(p.email)
 and a_mail.phone is null
join auth.users a_phone
  on a_phone.email is null
 and right(public.phone_digits(a_phone.phone), 10) = right(public.phone_digits(p.phone), 10)
order by a_phone.created_at desc;

-- If this returns rows, do NOT blind-delete the phone row: on a normalized
-- database the app resolves the profile by email OR phone (loadOwnUserRow),
-- so the person is probably landing on their real dashboard already, just
-- under a second auth id. Deleting the WRONG one takes their history with it.
-- Decide per row by which id owns their bookings and push_subscriptions.
