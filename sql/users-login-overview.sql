-- ============================================================================
-- users-login-overview.sql  (2026-08-25)
--
-- Every account, newest login first. Phone-driven: auth.users.phone is what
-- the SMS flow verifies, so it is the one identifier every 3.0 account has.
-- public.users.phone is NOT NULL and public.users.email is nullable, so
-- joining on email would silently drop every phone-only signup.
--
-- READ-ONLY. Safe to re-run. Run in: Supabase dashboard → nwqnakoongrorbwnrqzc
-- → SQL editor (needs to read the auth schema, so the editor, not the app).
--
-- ── ON "FIRST LOGIN" ────────────────────────────────────────────────────────
-- GoTrue does not store one. auth.users has created_at and last_sign_in_at
-- and nothing in between. For a phone-only account created_at IS effectively
-- the first login, because the auth row is written the moment the first SMS
-- code verifies -- there is no separate signup step to drift from it. For the
-- older email accounts, created_at is when they registered, which may predate
-- their first actual sign-in. Section 4 gets the true first login from the
-- audit log where it is still retained.
--
-- ── ON PHONE MATCHING ───────────────────────────────────────────────────────
-- auth.users.phone is stored without the leading + (15551234567); the profile
-- tables are E.164 (+15551234567) via the format trigger. phone_digits()
-- strips both to digits, and comparing the last 10 handles any row that
-- predates the trigger and is missing its country code. phone_digits() returns
-- NULL rather than '' for a blank, so a null phone can never join to another
-- null phone -- no accidental collisions.
-- ============================================================================


-- ── 1. THE OVERVIEW ─────────────────────────────────────────────────────────
with auth_people as (
  select
    au.id                          as auth_id,
    au.phone                       as auth_phone,
    au.email                       as auth_email,
    public.phone_digits(au.phone)  as auth_digits,
    au.created_at                  as first_seen,
    au.last_sign_in_at             as last_login
  from auth.users au
)
select
  coalesce(pu.name, t.name, '— no profile row —')            as name,
  coalesce(pu.phone, t.phone, ap.auth_phone)                 as phone,
  coalesce(pu.role,
           case when t.id is not null then 'tech' end,
           '—')                                              as role,
  coalesce(pu.email, t.email)                                as email,

  -- The two dates she asked for, plus the gap between them.
  ap.last_login,
  ap.first_seen,
  case when ap.last_login is null then null
       else (current_date - ap.last_login::date) end         as days_since_last_login,
  (current_date - ap.first_seen::date)                       as account_age_days,

  -- Two timestamps is enough to tell a tourist from a real user: if the last
  -- login is essentially the same moment as the first, they signed up and
  -- never came back.
  case
    when ap.last_login is null                                    then 'never signed in'
    when ap.last_login - ap.first_seen < interval '5 minutes'      then 'signed up, never returned'
    when ap.last_login > now() - interval '7 days'                then 'active'
    when ap.last_login > now() - interval '30 days'               then 'slipping'
    else                                                               'dormant'
  end                                                        as engagement,

  -- Can this person actually get in? No phone on the AUTH row means the SMS
  -- flow has nothing to verify and there is no email login any more.
  case when coalesce(nullif(btrim(ap.auth_phone), ''), '') = ''
       then 'LOCKED OUT — no auth phone' end                 as login_blocker,

  -- Tech-only columns; null for clients.
  t.subscription_tier,
  t.subscription_expires_at,
  t.is_visible,
  t.is_bookable,

  ap.auth_id
from auth_people ap

-- One profile row each, deterministically, so a duplicate phone cannot
-- multiply this report's row count. Section 3 surfaces any duplicates.
left join lateral (
  select u.*
  from public.users u
  where right(public.phone_digits(u.phone), 10) = right(ap.auth_digits, 10)
  order by u.joined desc nulls last
  limit 1
) pu on true

-- Techs match on phone first, falling back to email for the pre-cutover
-- accounts whose techs.email is set but whose phone was added later.
-- is_visible / is_bookable on public.techs are PostgREST computed fields,
-- declared as function(public.techs). They only resolve against a real
-- techs row, not against a subquery's expanded record, so this calls the
-- uuid-taking functions those computed fields wrap.
left join lateral (
  select tt.id, tt.name, tt.phone, tt.email,
         tt.subscription_tier, tt.subscription_expires_at,
         public.tech_is_visible(tt.id)  as is_visible,
         public.tech_is_bookable(tt.id) as is_bookable
  from public.techs tt
  where right(public.phone_digits(tt.phone), 10) = right(ap.auth_digits, 10)
     or (tt.email is not null and ap.auth_email is not null
         and lower(tt.email) = lower(ap.auth_email))
  order by (right(public.phone_digits(tt.phone), 10) = right(ap.auth_digits, 10)) desc
  limit 1
) t on true

order by ap.last_login desc nulls last,
         ap.first_seen desc;


-- ── 2. THE ONE-LINE ROLLUP ──────────────────────────────────────────────────
select
  count(*)                                                          as accounts,
  count(*) filter (where last_sign_in_at is null)                   as never_signed_in,
  count(*) filter (where last_sign_in_at > now() - interval '7 days')  as active_7d,
  count(*) filter (where last_sign_in_at > now() - interval '30 days') as active_30d,
  count(*) filter (where last_sign_in_at - created_at < interval '5 minutes')
                                                                    as one_and_done,
  count(*) filter (where coalesce(nullif(btrim(phone), ''), '') = '') as locked_out,
  min(created_at)                                                   as first_account_ever,
  max(last_sign_in_at)                                              as most_recent_login
from auth.users;


-- ── 3. DUPLICATE-PHONE CHECK ────────────────────────────────────────────────
-- Section 1 picks one profile per auth row. If this returns anything, two
-- profile rows share a number and section 1 is hiding one of them.
select right(public.phone_digits(phone), 10) as last10,
       count(*) as rows, array_agg(name order by name) as names
from public.users
where public.phone_digits(phone) is not null
group by 1 having count(*) > 1
union all
select right(public.phone_digits(phone), 10), count(*), array_agg(name order by name)
from public.techs
where public.phone_digits(phone) is not null
group by 1 having count(*) > 1;


-- ── 4. TRUE FIRST LOGIN (optional) ──────────────────────────────────────────
-- The real first/last login and a login count, from GoTrue's audit log.
-- CAVEAT: audit_log_entries is not retained forever, so an old account can
-- show a first_login later than its created_at simply because the original
-- entry has aged out. Trust section 1's first_seen for "when did this account
-- come into being"; trust this for "how often do they actually come back".
select
  (e.payload->>'actor_id')::uuid  as auth_id,
  min(e.created_at)               as first_login_logged,
  max(e.created_at)               as last_login_logged,
  count(*)                        as login_events
from auth.audit_log_entries e
where e.payload->>'action' = 'login'
group by 1
order by max(e.created_at) desc;
