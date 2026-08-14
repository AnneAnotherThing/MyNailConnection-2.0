-- ============================================================================
-- phone-only-cutover-audit.sql
--
-- RUN THIS BEFORE THE PHONE-ONLY BUILD REACHES REAL USERS.
--
-- As of 2026-08-14 the app has no email sign-in. The splash routes Sign In and
-- Create a Free Account straight to the SMS-code flow, and the #auth / #signup
-- screens (and the password-reset modal) are gone from index.html.
--
-- That is a one-way door for anyone whose account has no usable phone number:
-- they can no longer get in through any UI. This file tells you exactly who
-- that is, BEFORE they find out the hard way.
--
-- Nothing here modifies data. Read-only.
--
-- NOTE ON WHAT DID *NOT* CHANGE: lower(email) is still the internal identity
-- key. push_subscriptions.user_id is keyed on it, and every RLS policy calls
-- current_email(). Removing the login screen does not touch any of that, so
-- existing email-identity accounts keep working normally — they just need a
-- phone on their auth record to sign in.
-- ============================================================================

-- ── 1. THE LOCKOUT LIST ─────────────────────────────────────────────────────
-- Accounts that can authenticate ONLY by email. auth.users.phone is what the
-- SMS flow verifies against, so a null/blank phone there is the blocker —
-- a phone in public.users is NOT enough on its own.
select
  u.id,
  u.email,
  u.phone                       as auth_phone,
  pu.phone                      as profile_phone,
  pu.role,
  u.last_sign_in_at,
  u.created_at
from auth.users u
left join public.users pu on lower(pu.email) = lower(u.email)
where coalesce(nullif(btrim(u.phone), ''), '') = ''
order by u.last_sign_in_at desc nulls last;

-- ── 2. HOW BAD IS IT ────────────────────────────────────────────────────────
select
  count(*) filter (where coalesce(nullif(btrim(phone), ''), '') = '')       as locked_out,
  count(*) filter (where coalesce(nullif(btrim(phone), ''), '') <> '')      as can_sign_in,
  count(*)                                                                  as total
from auth.users;

-- ── 3. THE RECOVERABLE ONES ─────────────────────────────────────────────────
-- Locked out of auth, but we DO have a phone on their profile row. These can
-- be migrated: set auth.users.phone (+ phone_confirmed_at) from the profile and
-- they sign in normally. Do this from the Supabase dashboard or the Admin API —
-- do NOT hand-UPDATE auth.users in the SQL editor, GoTrue owns that table and
-- expects its own invariants (confirmation timestamps, identity rows).
select
  u.id, u.email, pu.phone as profile_phone, pu.role, u.last_sign_in_at
from auth.users u
join public.users pu on lower(pu.email) = lower(u.email)
where coalesce(nullif(btrim(u.phone), ''), '') = ''
  and coalesce(nullif(btrim(pu.phone), ''), '') <> ''
order by pu.role, u.last_sign_in_at desc nulls last;

-- ── 4. THE GENUINELY STRANDED ───────────────────────────────────────────────
-- No auth phone AND no profile phone. There is nothing to migrate; these
-- people need to be contacted out-of-band, or have their account recreated
-- against a phone number they give you. Techs matter most here — a stranded
-- tech loses their photos and bookings until it's sorted.
select
  u.id, u.email, pu.name, pu.role, u.last_sign_in_at,
  exists (select 1 from public.techs t where lower(t.email) = lower(u.email)) as has_tech_row
from auth.users u
left join public.users pu on lower(pu.email) = lower(u.email)
where coalesce(nullif(btrim(u.phone), ''), '') = ''
  and coalesce(nullif(btrim(pu.phone), ''), '') = ''
order by has_tech_row desc, u.last_sign_in_at desc nulls last;

-- ── 5. SANITY: nobody loses push ────────────────────────────────────────────
-- push_subscriptions is keyed on lower(email) for email accounts and E.164 for
-- phone accounts. Rows whose user_id matches neither an account email nor an
-- account phone are orphans that can never be delivered to.
select ps.user_id, ps.p256dh as kind, ps.auth as platform, ps.updated_at
from public.push_subscriptions ps
where not exists (select 1 from public.users u where lower(u.email) = ps.user_id)
  and not exists (select 1 from public.users u
                   where public.phone_digits(u.phone) = public.phone_digits(ps.user_id))
order by ps.updated_at desc;
