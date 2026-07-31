-- ============================================================================
-- FIX LESLIE'S PHONE LOGIN  (2026-07-24)
-- ============================================================================
-- What happened: Leslie signed in with her phone BEFORE
-- phone-auth-normalize-existing-phones.sql was run. Her stored phone is bare
-- 10 digits, phone login compares E.164, no match, so Supabase minted a
-- brand-new EMPTY auth user for her number and sent her through new-user
-- signup. Her real tech profile is untouched.
--
-- That junk account must go BEFORE the normalize script runs, or it can
-- shadow her real profile (two rows would then match her phone).
--
-- ORDER OF OPERATIONS:
--   1. Replace LESLIE_DIGITS below with her 10-digit number (digits only).
--   2. Run STEP 1 (read-only review).
--   3. Run STEP 2 (deletes ONLY rows with her phone and NO email, her real
--      rows are keyed by email and are never touched).
--   4. Run phone-auth-normalize-existing-phones.sql.
--   5. Leslie signs in by phone again, she should land on her own dashboard.
--
-- This same recovery works for ANY existing tech who tried phone login
-- before the normalize: swap in their digits.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════
-- STEP 1 — REVIEW (reads only)
-- Her REAL rows show an email. The junk rows from the failed login show
-- email = null. Only the null-email rows get deleted in Step 2.
-- ════════════════════════════════════════════════════════════════════════
with target (digits) as (values ('LESLIE_DIGITS'))
select 'auth' as source,
       a.created_at::timestamp(0) as created,
       a.email, a.phone, null as name,
       case when a.email is null then 'JUNK, will delete' else 'real, kept' end as verdict
from auth.users a
where right(regexp_replace(coalesce(a.phone,''),'\D','','g'), 10) in (select digits from target)
union all
select 'users', null, u.email, u.phone, u.name,
       case when u.email is null then 'JUNK, will delete' else 'real, kept' end
from public.users u
where right(regexp_replace(coalesce(u.phone,''),'\D','','g'), 10) in (select digits from target)
union all
select 'techs', null, t.email, t.phone, t.name,
       case when t.email is null then 'JUNK, will delete' else 'real, kept' end
from public.techs t
where right(regexp_replace(coalesce(t.phone,''),'\D','','g'), 10) in (select digits from target)
order by 1;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 2 — DELETE the junk (null-email rows matching her number only)
-- ════════════════════════════════════════════════════════════════════════
with target (digits) as (values ('LESLIE_DIGITS'))
, d_techs as (delete from public.techs
    where email is null
      and right(regexp_replace(coalesce(phone,''),'\D','','g'), 10) in (select digits from target)
    returning 1)
, d_users as (delete from public.users
    where email is null
      and right(regexp_replace(coalesce(phone,''),'\D','','g'), 10) in (select digits from target)
    returning 1)
, d_auth as (delete from auth.users
    where email is null
      and right(regexp_replace(coalesce(phone,''),'\D','','g'), 10) in (select digits from target)
    returning 1)
select
  (select count(*) from d_auth)  as junk_auth_deleted,
  (select count(*) from d_users) as junk_users_deleted,
  (select count(*) from d_techs) as junk_techs_deleted;


-- ════════════════════════════════════════════════════════════════════════
-- STEP 3 — now run phone-auth-normalize-existing-phones.sql, then have
-- Leslie sign in by phone again.
-- ════════════════════════════════════════════════════════════════════════
