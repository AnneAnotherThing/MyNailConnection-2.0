-- ========================================================================
-- MNC 3.0 Cutover: restore ALL paused photos  (the relaunch gift)
-- ========================================================================
-- Run ONCE in the Supabase SQL editor at 3.0 cutover, after the updated
-- stripe-webhook (no more pause-on-cancel) is deployed.
--
-- 2.0 paused photos beyond the free limit when a Glow Up subscription
-- cancelled. 3.0's model is "every paid photo is a permanent ad", so at
-- launch we hand every tech their full portfolio back: paused photos
-- move back into public view with their tags intact, paused_at stripped.
--
-- Idempotent: skips any photo whose url already exists in photos, and
-- techs with nothing paused are untouched. Safe to re-run.
-- ========================================================================

-- Preview first: who gets photos back, and how many?
select email, name,
       jsonb_array_length(coalesce(paused_photos, '[]'::jsonb)) as paused_count
from public.techs
where jsonb_array_length(coalesce(paused_photos, '[]'::jsonb)) > 0
order by paused_count desc;

-- The restore:
update public.techs t
set photos = coalesce(t.photos, '[]'::jsonb) || (
      select coalesce(jsonb_agg(p - 'paused_at'), '[]'::jsonb)
      from jsonb_array_elements(coalesce(t.paused_photos, '[]'::jsonb)) p
      where not exists (
        select 1
        from jsonb_array_elements(coalesce(t.photos, '[]'::jsonb)) q
        where q ->> 'url' = p ->> 'url'
      )
    ),
    paused_photos = '[]'::jsonb
where jsonb_array_length(coalesce(t.paused_photos, '[]'::jsonb)) > 0;

-- Verify: should return zero rows.
select email from public.techs
where jsonb_array_length(coalesce(paused_photos, '[]'::jsonb)) > 0;
