-- ============================================================================
-- tech-booking-trial-migration.sql  (2026-09-20)
--
-- Card-free free month, tied to TURNING ON MNC BOOKING, not to signup.
--
-- The only techs who ever pay are the ones who turn MNC's own booking engine
-- on. A tech with just a profile, a gallery, and their own external booking
-- link pays nothing, ever -- and must have no trial clock, no countdown, no
-- paywall. So the 30-day free month starts the moment a tech first flips
-- booking_enabled on, once, and only for techs who are not comped and not
-- already subscribed. (Anne, 2026-09-20, correcting the signup-grant version:
-- "the only people who ever pay a thing are people who turn mnc booking on.
-- otherwise no pay, no countdown, nothing.")
--
-- Replaces sql/tech-signup-trial-migration.sql (the insert-time grant), which
-- this migration also removes so a tech who never turns booking on carries no
-- trial state at all.
--
-- Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc). Re-runnable.
-- Only affects techs going forward; nothing is backfilled.
-- ============================================================================

-- ── 0. Remove the old signup-time grant (if it was ever run) ────────────────
drop trigger  if exists grant_signup_trial_on_tech_insert_trg on public.techs;
drop function if exists public.grant_signup_trial_on_tech_insert();

-- ── 1. Mark when a tech's free month started (null = never) ──────────────────
alter table public.techs
  add column if not exists trial_started_at timestamptz;

comment on column public.techs.trial_started_at is
  'When this tech first turned MNC booking on and started their 30-day free month. Null = never turned booking on, so no trial and nothing to pay. Set once by grant_booking_trial.';

-- ── 2. Start the free month when booking is first turned on ──────────────────
-- Fires on INSERT (rare: booking on at creation) and UPDATE (the normal path:
-- booking_enabled false -> true). Named to sort AFTER
-- apply_pending_comp_on_tech_insert_trg so a comped tech is already 'paid'
-- and skipped here (they keep their lifetime comp). Once-only via
-- trial_started_at; never re-granted on a later toggle.
create or replace function public.grant_booking_trial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turning_on boolean;
begin
  if tg_op = 'INSERT' then
    v_turning_on := coalesce(new.booking_enabled, false);
  else
    v_turning_on := coalesce(new.booking_enabled, false)
                    and not coalesce(old.booking_enabled, false);
  end if;

  if v_turning_on
     and new.trial_started_at is null                        -- never trialed
     and coalesce(new.subscription_tier, 'free') <> 'paid'   -- not comped / subscribed
     and new.subscription_source is null then
    new.trial_started_at        := now();
    new.subscription_tier       := 'paid';
    new.subscription_source     := 'trial';
    new.subscription_expires_at := now() + interval '30 days';
    new.period_upload_count     := coalesce(new.period_upload_count, 0);
    new.period_reset_at         := now() + interval '30 days';
  end if;
  return new;
end;
$$;

drop trigger if exists grant_booking_trial_trg on public.techs;
create trigger grant_booking_trial_trg
  before insert or update on public.techs
  for each row
  execute function public.grant_booking_trial();

-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- A tech with booking off has trial_started_at = null and pays nothing.
-- Flip booking on (as the app does) and the same row should become:
--   booking_enabled=true, subscription_tier='paid', subscription_source='trial',
--   trial_started_at ~ now(), period_reset_at ~ now()+30d.
-- Toggling booking off then on again must NOT move trial_started_at or extend
-- the window. A comped tech (email in tech_comps) turning booking on stays
-- expires_at=null (lifetime), untouched.
