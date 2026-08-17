-- ============================================================================
-- PHOTO COUNTS WITHOUT DOWNLOADING THE PHOTOS (2026-08-15)
-- ============================================================================
-- Problem: public.techs.photos is a JSONB array, and three places in the app
-- wanted nothing but its length. PostgREST has no length operator in select,
-- so all three fetched the entire array and called .length on the client:
--
--   1. loadTechTier()  — select=...,photos,paused_photos  (runs on EVERY
--      upload, so a tech pays for their whole portfolio on every photo)
--   2. admin stats     — select=photos across ALL techs, twice
--
-- Invisible at 5 photos per tech. Real at 50. It also grows with the number
-- of techs on the admin screens, which is the direction the business is
-- supposed to go.
--
-- Fix: PostgREST computed columns. A function whose single argument is the
-- table's row type is selectable as if it were a column, so the count is
-- computed in Postgres and only the integer crosses the wire. No table
-- rewrite, no new storage, no change to any write path.
--
-- Safe to re-run. Run in: Supabase dashboard → nwqnakoongrorbwnrqzc → SQL editor.
-- ============================================================================

-- jsonb_array_length throws if the value is not an array, and these columns
-- are nullable, so guard on the type rather than trusting the shape. Both
-- branches are immutable, which is what lets PostgREST select this.
create or replace function public.photos_count(public.techs)
returns integer
language sql
immutable
as $$
  select case
           when jsonb_typeof($1.photos) = 'array' then jsonb_array_length($1.photos)
           else 0
         end
$$;

create or replace function public.paused_count(public.techs)
returns integer
language sql
immutable
as $$
  select case
           when jsonb_typeof($1.paused_photos) = 'array' then jsonb_array_length($1.paused_photos)
           else 0
         end
$$;

comment on function public.photos_count(public.techs) is
  'PostgREST computed column: length of techs.photos without shipping the array. Select as ?select=photos_count';
comment on function public.paused_count(public.techs) is
  'PostgREST computed column: length of techs.paused_photos without shipping the array. Select as ?select=paused_count';

grant execute on function public.photos_count(public.techs) to anon, authenticated;
grant execute on function public.paused_count(public.techs) to anon, authenticated;

-- PostgREST caches the schema; without this the new columns 404 until the
-- next restart.
notify pgrst, 'reload schema';

-- ========================================================================
-- VERIFY
--
-- The table MUST be aliased. These are functions, not real columns: Postgres
-- treats `t.photos_count` as `photos_count(t)`, which only works when there
-- is a row variable to pass. A bare `photos_count` with no alias fails with
-- 42703 column "photos_count" does not exist, which is not a sign the
-- migration failed. (Got this wrong the first time, 2026-08-15.)
--
--   select t.id,
--          t.photos_count,
--          jsonb_array_length(coalesce(t.photos, '[]'::jsonb))        as actual,
--          t.paused_count,
--          jsonb_array_length(coalesce(t.paused_photos, '[]'::jsonb)) as actual_paused
--     from public.techs t
--    order by t.photos_count desc
--    limit 10;
--
-- Then over the wire, which is the check that actually matters, because
-- PostgREST is the only consumer and it has its own schema cache:
--   GET /rest/v1/techs?select=id,photos_count,paused_count&limit=3
-- Verified working 2026-08-15, HTTP 200 with integer counts.
-- ========================================================================
