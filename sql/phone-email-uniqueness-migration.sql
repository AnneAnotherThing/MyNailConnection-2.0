-- ────────────────────────────────────────────────────────────────────────
-- MNC phone + email uniqueness migration  (v2 — phone REQUIRED)
-- ────────────────────────────────────────────────────────────────────────
-- Purpose: prevent one person from creating multiple accounts to game the
-- "5 free photos" benefit. Enforces uniqueness at the DATABASE level, not
-- just in JS — so no client-side bypass is possible.
--
-- Policy:
--   • Phone is REQUIRED and UNIQUE on both users + techs.
--   • Email is UNIQUE (case-insensitive) on both users + techs.
--   • Email is already REQUIRED in auth.users (Supabase); the public tables
--     mirror that requirement via the unique index.
--
-- SAFE TO RE-RUN: uses IF NOT EXISTS and skips already-normalized rows.
--
-- HOW TO APPLY (run these four blocks in order):
--   0. ADD COLUMNS → adds public.users.phone (+ other missing profile cols)
--   1. DIAGNOSTIC  → see what's null and what's duplicated
--   2. BACKFILL    → copy phones from techs → users, fix dupes by hand
--   3. CONSTRAINTS → locks in uniqueness + required-ness
-- ────────────────────────────────────────────────────────────────────────


-- ========================================================================
-- BLOCK 0 — ADD MISSING COLUMNS
-- public.users didn't have a phone column (unlike public.techs). Add it
-- now so the rest of the migration works. Nullable for now; Block 3 will
-- enforce NOT NULL once data's clean. Also add other profile columns the
-- signup flow POSTs so client signups don't silently drop data.
-- Safe to re-run.
-- ========================================================================

alter table public.users
  add column if not exists phone text,
  add column if not exists address text,
  add column if not exists city text,
  add column if not exists state text,
  add column if not exists zip text,
  add column if not exists bio text,
  add column if not exists image_url text,
  add column if not exists joined date;


-- ========================================================================
-- BLOCK 1 — DIAGNOSTIC
-- Run this after Block 0. If any of the four queries return rows, resolve
-- those before running Block 3. Block 2 helps with the first two.
-- ========================================================================

-- 1a. Users with missing phone — these will block NOT NULL if left alone.
-- select email, name, phone from public.users
--  where phone is null or phone = '' order by email;

-- 1b. Techs with missing phone.
-- select email, name, phone from public.techs
--  where phone is null or phone = '' order by email;

-- 1c. Phone duplicates in users (after normalization).
-- select regexp_replace(phone, '\D', '', 'g') as clean_phone, count(*)
--   from public.users where phone is not null and phone <> ''
--   group by regexp_replace(phone, '\D', '', 'g') having count(*) > 1;

-- 1d. Phone duplicates in techs (after normalization).
-- select regexp_replace(phone, '\D', '', 'g') as clean_phone, count(*)
--   from public.techs where phone is not null and phone <> ''
--   group by regexp_replace(phone, '\D', '', 'g') having count(*) > 1;


-- ========================================================================
-- BLOCK 2 — NORMALIZE + BACKFILL
-- Normalizes all phones to digits-only, then copies techs.phone into the
-- matching public.users row for any user whose phone is still null
-- (typically the 17 techs who were backfilled into users earlier without
--  phones). Idempotent — safe to re-run.
-- ========================================================================

-- Normalize phones to digits-only in BOTH tables.
update public.users
   set phone = regexp_replace(phone, '\D', '', 'g')
 where phone is not null
   and phone <> regexp_replace(phone, '\D', '', 'g');

update public.techs
   set phone = regexp_replace(phone, '\D', '', 'g')
 where phone is not null
   and phone <> regexp_replace(phone, '\D', '', 'g');

-- Copy techs.phone → users.phone where the user row is missing a phone.
update public.users u
   set phone = t.phone
  from public.techs t
 where lower(u.email) = lower(t.email)
   and (u.phone is null or u.phone = '')
   and t.phone is not null and t.phone <> '';

-- After running the above: re-run Block 1 diagnostics. If users/techs
-- still have rows with null or empty phones, you need to either collect
-- those phones manually and UPDATE them, or delete those rows before
-- Block 3 will succeed.


-- ========================================================================
-- BLOCK 3 — CONSTRAINTS
-- Only run this once Block 1 returns zero rows for 1a–1d. These changes
-- are hard to reverse and will fail noisily if your data isn't clean.
-- ========================================================================

-- Phone: NOT NULL + UNIQUE on both tables.
alter table public.users  alter column phone set not null;
alter table public.techs  alter column phone set not null;

create unique index if not exists users_phone_unique_idx on public.users (phone);
create unique index if not exists techs_phone_unique_idx on public.techs (phone);

-- Email: case-insensitive UNIQUE on both tables. (auth.users already has
-- a case-sensitive unique; this mirrors the JS check and blocks direct
-- inserts from edge functions / SQL that would otherwise bypass it.)
create unique index if not exists users_email_unique_ci on public.users (lower(email));
create unique index if not exists techs_email_unique_ci on public.techs (lower(email));
