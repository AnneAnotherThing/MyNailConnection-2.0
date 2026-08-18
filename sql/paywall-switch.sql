-- ========================================================================
-- PAYWALL ON/OFF SWITCH
-- ========================================================================
-- The whole tech paywall hangs off ONE function, tech_live_calc(). Flipping
-- it does not require an app change, a rebuild, or a store submission —
-- get_open_slots(), _booking_gate(), the is_live computed column and every
-- client-side filter all read through it.
--
-- OFF (this file as written): a tech is visible unless SHE paused herself.
--   Exactly the pre-paywall behaviour. Ship this for launch, because the
--   purchase sheet does not exist yet and an enforced gate with no way to
--   pay is a dead end for every new signup.
--
-- ON: uncomment the marked block. Do that in the same release that ships
--   the purchase sheet, never before.
--
-- Idempotent. Safe to re-run. Takes effect immediately for bookings, and
-- within the hour for listing_paused (the pg_cron sync), or instantly if you
-- run sync_tech_visibility() yourself — which the bottom of this file does.
-- ========================================================================

create or replace function public.tech_live_calc(
  p_paused_by_tech boolean,
  p_founder_free   boolean,
  p_tier           text,
  p_period_reset   timestamptz
) returns boolean
language sql stable
as $$
  select not coalesce(p_paused_by_tech, false)
  -- ── PAYWALL: ON ──────────────────────────────────────────────────────
  -- Delete the ";" above and uncomment the block below to start charging.
  -- Ship this ONLY alongside the purchase sheet.
  --
  --   and (
  --        coalesce(p_founder_free, false)
  --     or (   p_tier = 'paid'
  --        and coalesce(p_period_reset, now() + interval '100 years')
  --            > now() - interval '3 days')
  --   )
  -- ─────────────────────────────────────────────────────────────────────
  ;
$$;

-- Apply immediately rather than waiting for the hourly cron.
select public.sync_tech_visibility() as rows_resynced;

-- VERIFY: every tech's visibility and why. With the paywall OFF, live_now
-- should be true for everyone who has not paused herself.
select
  t.name,
  t.paused_by_tech            as paused_herself,
  t.founder_free,
  t.subscription_tier,
  t.listing_paused            as effective_hidden,
  public.tech_is_live(t.id)   as live_now
from public.techs t
order by live_now, t.name;

-- Must be 0.
select count(*) as rows_out_of_sync
  from public.techs t
 where t.listing_paused is distinct from not public.tech_is_live(t.id);
