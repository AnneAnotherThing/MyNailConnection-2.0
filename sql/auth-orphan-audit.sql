-- ============================================================================
-- auth-orphan-audit.sql
-- ----------------------------------------------------------------------------
-- Source of truth: auth.users.
-- Surfaces every state in public.techs / public.users that won't behave
-- correctly because the auth side and the profile side are out of sync.
--
-- The two failure modes you've actually hit:
--   1. "Orphan auth" — auth user with NO matching public.techs / public.users
--      row. App PATCHes silently match 0 rows; UI claims success.
--   2. "ID mismatch" — auth.users.id is supposed to equal public.users.id
--      (and likely public.techs.id). When they drift, RLS that keys off
--      auth.uid() blocks users from their own row.
--
-- All queries are SELECT-only. Run them in Supabase → SQL Editor.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- BUCKET A — ORPHAN AUTH  (auth user with NO profile in techs OR users)
-- These accounts can sign in but have nothing in the app tables.
-- This is the silent-PATCH-no-op failure mode.
-- ----------------------------------------------------------------------------
select
  au.id    as auth_id,
  au.email,
  au.created_at,
  au.last_sign_in_at,
  (au.email_confirmed_at is not null) as email_confirmed
from auth.users au
left join public.techs t on lower(t.email) = lower(au.email)
left join public.users u on lower(u.email) = lower(au.email)
where t.email is null
  and u.email is null
order by au.created_at desc;


-- ----------------------------------------------------------------------------
-- BUCKET B — IN BOTH  (auth user matched to BOTH techs and users by email)
-- techs/users are meant to be mutually exclusive. A row in both means
-- ambiguous identity at sign-in — app might pick the wrong profile.
-- ----------------------------------------------------------------------------
select
  au.id    as auth_id,
  au.email,
  t.id     as techs_id,
  u.id     as users_id
from auth.users au
join public.techs t on lower(t.email) = lower(au.email)
join public.users u on lower(u.email) = lower(au.email)
order by au.email;


-- ----------------------------------------------------------------------------
-- BUCKET C — ID MISMATCH on public.users
-- Convention: public.users.id == auth.users.id for the same email.
-- If they drift, RLS policies keyed on auth.uid() will hide the user's
-- own row from them.
-- ----------------------------------------------------------------------------
select
  au.email   as auth_email,
  au.id      as auth_id,
  u.id       as users_id_actual,
  u.email    as users_email
from auth.users au
join public.users u on lower(u.email) = lower(au.email)
where u.id <> au.id
order by au.email;


-- ----------------------------------------------------------------------------
-- BUCKET D — ID MISMATCH on public.techs
-- Same idea. Comment out if your public.techs uses a different id scheme
-- (e.g., a separate uuid joined via auth_user_id instead of id).
-- ----------------------------------------------------------------------------
select
  au.email   as auth_email,
  au.id      as auth_id,
  t.id       as techs_id_actual,
  t.email    as techs_email
from auth.users au
join public.techs t on lower(t.email) = lower(au.email)
where t.id <> au.id
order by au.email;


-- ----------------------------------------------------------------------------
-- BUCKET E — DUPLICATE AUTH on the same email (case-insensitive)
-- Two auth.users rows sharing a normalized email. Sign-in becomes
-- non-deterministic and one row will become unreachable.
-- ----------------------------------------------------------------------------
select
  lower(email) as email_norm,
  count(*)     as auth_rows,
  array_agg(id order by created_at) as auth_ids,
  array_agg(created_at order by created_at) as created_ats
from auth.users
group by lower(email)
having count(*) > 1
order by auth_rows desc, email_norm;


-- ----------------------------------------------------------------------------
-- BUCKET F — UNCONFIRMED AUTH USERS
-- Per your launch config (Confirm-email OFF as of 2026-04-28) this should
-- be a small set — anything created before that date that never confirmed,
-- plus anyone created via flows that didn't pre-stamp email_confirmed_at.
-- These users may hit "email not confirmed" if the project setting flips back.
-- ----------------------------------------------------------------------------
select
  au.id,
  au.email,
  au.created_at,
  case
    when t.email is not null then 'has tech profile'
    when u.email is not null then 'has user profile'
    else 'no profile'
  end as profile_state
from auth.users au
left join public.techs t on lower(t.email) = lower(au.email)
left join public.users u on lower(u.email) = lower(au.email)
where au.email_confirmed_at is null
order by au.created_at desc;


-- ----------------------------------------------------------------------------
-- BUCKET G — PROFILE ROWS WITH NO AUTH  (informational, often intentional)
-- public.techs / public.users rows that have no matching auth.users row.
-- Often by design (archived techs awaiting re-onboarding). Listed here so
-- you can verify which are intentional vs accidental.
-- ----------------------------------------------------------------------------
select 'techs' as table_name, t.id as profile_id, t.email
from public.techs t
left join auth.users au on lower(au.email) = lower(t.email)
where au.id is null

union all

select 'users' as table_name, u.id as profile_id, u.email
from public.users u
left join auth.users au on lower(au.email) = lower(u.email)
where au.id is null

order by table_name, email;


-- ----------------------------------------------------------------------------
-- ROLLUP — counts only, for an at-a-glance health check
-- ----------------------------------------------------------------------------
select 'A: orphan auth (no profile)'           as bucket, count(*) from auth.users au
  left join public.techs t on lower(t.email) = lower(au.email)
  left join public.users u on lower(u.email) = lower(au.email)
  where t.email is null and u.email is null
union all
select 'B: auth in both techs AND users'       as bucket, count(*) from auth.users au
  join public.techs t on lower(t.email) = lower(au.email)
  join public.users u on lower(u.email) = lower(au.email)
union all
select 'C: id mismatch on public.users'        as bucket, count(*) from auth.users au
  join public.users u on lower(u.email) = lower(au.email) where u.id <> au.id
union all
select 'D: id mismatch on public.techs'        as bucket, count(*) from auth.users au
  join public.techs t on lower(t.email) = lower(au.email) where t.id <> au.id
union all
select 'E: duplicate auth (same lower email)'  as bucket,
       coalesce(sum(c - 1), 0)::bigint
  from (select count(*) c from auth.users group by lower(email) having count(*) > 1) x
union all
select 'F: auth not email-confirmed'           as bucket, count(*) from auth.users where email_confirmed_at is null
union all
select 'G: techs with no auth'                 as bucket, count(*) from public.techs t
  left join auth.users au on lower(au.email) = lower(t.email) where au.id is null
union all
select 'G: users with no auth'                 as bucket, count(*) from public.users u
  left join auth.users au on lower(au.email) = lower(u.email) where au.id is null;
