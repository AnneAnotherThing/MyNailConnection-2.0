-- ============================================================================
-- tech-signup-trial-migration.sql  (2026-09-20)
--
-- Card-free founding free month. Every brand-new tech gets 30 days of full
-- booking access the moment they sign up, server-side, no card, no store.
-- When it lapses they go unbookable and subscribe through the store (card
-- then). This replaces the card-required App Store / Play intro offer as the
-- default free month.
--
-- DECISION (Anne, 2026-09-18/19): "we'll lose them if we require a card for
-- them to try it." At this stage adoption beats conversion and the tech is
-- the scarce side, so kill the signup card wall. Tradeoff accepted: no card
-- means no auto-conversion; the tech must actively subscribe at day 30.
-- Reverses part of the Aug 17 model (booking behind a card-required store
-- trial). STORE STEP FOR ANNE: after this is live, REMOVE the 30-day free
-- intro offer in App Store Connect and Play Console so nobody double-dips
-- (30 free from us + 30 from the store). Do that only AFTER this ships, or
-- new techs would get no free month at all.
--
-- Mechanism: a BEFORE INSERT trigger on public.techs, named to sort AFTER
-- apply_pending_comp_on_tech_insert_trg so it can see whether a comp already
-- made the tech 'paid'. A comped/founding tech keeps their comp (lifetime,
-- expires null); everyone else gets the 30-day trial. Gated so it never
-- clobbers an admin/restore insert that set a subscription explicitly.
--
-- Bookability: tech_bookable_calc reads period_reset_at, so a trial with
-- period_reset_at = now()+30d is bookable for 30 days, then unbookable after
-- the 3-day grace, exactly like a lapsed paid sub.
--
-- Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc). Re-runnable.
-- Only affects NEW tech rows; existing techs are untouched (reconcile those
-- separately per the listing_paused/bookability item).
-- ============================================================================

create or replace function public.grant_signup_trial_on_tech_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Grant the free month only to a genuine new signup: not already made
  -- 'paid' by the comp trigger, and with no subscription explicitly set by
  -- an admin/restore insert.
  if coalesce(new.subscription_tier, 'free') <> 'paid'
     and new.subscription_source is null
     and new.subscription_expires_at is null then
    new.subscription_tier       := 'paid';
    new.subscription_source     := 'trial';
    new.subscription_expires_at := now() + interval '30 days';
    new.period_upload_count     := coalesce(new.period_upload_count, 0);
    new.period_reset_at         := now() + interval '30 days';
  end if;
  return new;
end;
$$;

drop trigger if exists grant_signup_trial_on_tech_insert_trg on public.techs;
create trigger grant_signup_trial_on_tech_insert_trg
  before insert on public.techs
  for each row
  execute function public.grant_signup_trial_on_tech_insert();

-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- Trigger fire order (apply_pending_comp must come first):
--   select tgname from pg_trigger
--    where tgrelid='public.techs'::regclass and not tgisinternal order by tgname;
-- A fresh, non-comped tech row should land as:
--   subscription_tier='paid', subscription_source='trial',
--   subscription_expires_at ~ now()+30d, period_reset_at ~ now()+30d.
-- A comped tech (email in tech_comps) should stay expires_at=null (lifetime).
