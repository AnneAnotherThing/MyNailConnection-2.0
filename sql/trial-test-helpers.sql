-- ============================================================================
-- trial-test-helpers.sql  (2026-09-20)
--
-- Two deliberate, one-tech snippets for testing the booking free-month ON A
-- REAL DEVICE against prod. Unlike trial-selftest.sql these DO persist -- they
-- act on the one tech whose phone you paste. Use them on a test tech you own,
-- not a real customer.
--
-- Set the phone once (E.164, e.g. '+14805551234') and run only the block you
-- want. Both print the tech's before/after so you can see the change.
-- ============================================================================

-- ── A. RESET a tech to "never trialed" so you can test go-live again ─────────
-- Clears the trial + subscription back to a brand-new free tech with booking
-- off. After this, opening the app as that tech and turning booking on should
-- start a fresh 30-day free month. Never run on a real paying/comped tech.
update public.techs
   set booking_enabled         = false,
       subscription_tier       = 'free',
       subscription_source     = null,
       subscription_expires_at = null,
       trial_started_at        = null,
       period_reset_at         = null
 where phone = '+14805551234'          -- <<< your test tech's E.164 phone
   and coalesce(subscription_source,'') in ('','trial')  -- guard: skip real paid/comp
returning name, phone, booking_enabled, subscription_tier, subscription_source,
          trial_started_at, period_reset_at;

-- ── B. FORCE-EXPIRE a live trial so the paywall returns now (no 30-day wait) ─
-- Pushes the window 4 days past its grace. The tech's Book button disappears
-- and their next tap on booking should show the subscribe sheet. Only touches
-- a tech currently on the trial.
update public.techs
   set subscription_expires_at = now() - interval '4 days',
       period_reset_at         = now() - interval '4 days'
 where phone = '+14805551234'          -- <<< your test tech's E.164 phone
   and subscription_source = 'trial'
returning name, phone, subscription_tier, subscription_source,
          subscription_expires_at, period_reset_at,
          public.tech_is_bookable(id) as bookable_now;

-- ── C. PEEK at a tech's current trial state (read-only, safe) ────────────────
select name, phone, booking_enabled, subscription_tier, subscription_source,
       trial_started_at, subscription_expires_at, period_reset_at,
       public.tech_is_bookable(id) as bookable_now
  from public.techs
 where phone = '+14805551234';         -- <<< your test tech's E.164 phone
