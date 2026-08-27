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
