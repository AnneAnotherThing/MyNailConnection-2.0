-- ========================================================================
-- MNC Popularity Test Data Seed  (2026-04-21)
-- ========================================================================
-- Seeds 5 fake favorites + up to 5 fake heart saves against ONE chosen
-- tech so the ⭐ N and ♥ N chips render visibly during testing. All
-- fake users use the @mnc-seed.test domain so cleanup is trivial.
--
-- This script runs in Supabase SQL editor, which uses the superuser
-- role and bypasses RLS — so the fake inserts succeed even though a
-- real client couldn't impersonate another user.
--
-- HOW TO USE:
--   1) Run STEP 0 to see a list of techs + photo counts — pick one
--      with at least 5 photos so all heart chips seed cleanly
--   2) Edit the two occurrences of 'paste-tech-email-here' below to
--      that tech's email address
--   3) Run STEPS 1–3 together
--   4) Open that tech's profile in the app — you'll see ⭐ 5 and ♥ N
--      (where N ≤ 5 depending on how many photos they have)
--   5) When done testing, uncomment STEP 4 (CLEANUP) and run it
-- ========================================================================


-- ========================================================================
-- STEP 0 — Pick a tech (run alone first, inspect output)
-- ========================================================================
-- Sorted by photo count desc so techs with lots of photos float to the top.
select email, name, coalesce(jsonb_array_length(photos), 0) as n_photos
  from public.techs
 order by coalesce(jsonb_array_length(photos), 0) desc
 limit 10;


-- ========================================================================
-- STEP 1 — Insert 5 fake favorites against the target tech
-- ========================================================================

with target as (
  select email, name
    from public.techs
   where email = 'paste-tech-email-here'  -- ← EDIT THIS
   limit 1
)
insert into public.user_favorites (user_email, tech_email, tech_name, tech_image)
select
  'test-client-' || i || '@mnc-seed.test',
  t.email,
  t.name,
  ''
 from target t, generate_series(1, 5) as i;


-- ========================================================================
-- STEP 2 — Insert up to 5 fake heart saves on this tech's first photos
-- ========================================================================
-- Uses WITH ORDINALITY so each inserted heart maps to a distinct photo.
-- Gracefully handles techs with fewer than 5 photos (inserts only what
-- exists) or zero photos (inserts nothing — favorites still seed OK).

with target as (
  select email, name, photos
    from public.techs
   where email = 'paste-tech-email-here'  -- ← EDIT THIS (same email as step 1)
   limit 1
),
tech_photos as (
  select t.email, t.name,
         (photo->>'url') as photo_url,
         ord
   from target t,
        jsonb_array_elements(t.photos) with ordinality as x(photo, ord)
   where ord <= 5
)
insert into public.user_inspo (user_email, photo_url, tech_name, tech_email)
select
  'test-client-' || ord || '@mnc-seed.test',
  photo_url,
  name,
  email
 from tech_photos;


-- ========================================================================
-- STEP 3 — Verify
-- ========================================================================
-- Confirms how many seed rows landed. Expected: 5 favorites, up to 5 hearts.

select 'favorites' as kind, count(*) as n
  from public.user_favorites
 where user_email like '%@mnc-seed.test'
union all
select 'hearts' as kind, count(*) as n
  from public.user_inspo
 where user_email like '%@mnc-seed.test';


-- ========================================================================
-- STEP 4 — CLEANUP (uncomment when done testing)
-- ========================================================================
-- Removes every fake row seeded above. The @mnc-seed.test domain sentinel
-- keeps this safe — it can't match any real user.

-- delete from public.user_favorites where user_email like '%@mnc-seed.test';
-- delete from public.user_inspo     where user_email like '%@mnc-seed.test';
