-- ─────────────────────────────────────────────────────────────────────────
-- subscription-source-tracking-migration.sql
--
-- Adds platform-source tracking to public.techs so we can tell apart
-- subscribers who came in via Stripe (web/Android), Apple IAP (iOS), or
-- Google Play IAP (Android, future). Plus the IAP-specific identifiers
-- we need to reconcile with the App Store / Play Store / RevenueCat APIs
-- when handling renewals, cancellations, and refunds.
--
-- Why this matters now (2026-04-28):
--   We're about to ship Apple In-App Purchase support for the iOS build
--   (Glow Up, Spotlight 1, Spotlight 10). Apple takes 15-30%; Stripe
--   takes ~3%. The blended margin reporting requires knowing where each
--   subscriber came from. Refund/cancellation handling also has to call
--   the right backend (Stripe API vs Apple StoreKit vs Google Play
--   Developer API), so we need to know which one to call.
--
-- Schema decisions:
--   - subscription_source is a TEXT column with a CHECK constraint instead
--     of a Postgres ENUM, so we can add new sources later (e.g.
--     'paddle', 'razorpay') without doing a type migration.
--   - apple_original_transaction_id is Apple's stable subscription ID
--     (originalTransactionId) — survives renewals and re-subscriptions,
--     and is what RevenueCat keys off internally.
--   - google_purchase_token is the Play Billing purchase token, used to
--     query the Play Developer API for subscription state.
--   - revenuecat_app_user_id ties the techs row back to RevenueCat's
--     dashboard so support investigations can cross-reference.
--
-- Backfill rules:
--   - Existing techs with stripe_customer_id IS NOT NULL → 'stripe'
--   - Existing paid techs in tech_comps (comped/grandfathered) → 'comp'
--   - Everyone else (free tier) → NULL (source only meaningful for paid)
--
-- Idempotent: re-running this migration is safe. ADD COLUMN uses
-- IF NOT EXISTS, indexes use IF NOT EXISTS, the backfill UPDATE is gated
-- on subscription_source IS NULL.
-- ─────────────────────────────────────────────────────────────────────────

-- ── Add the columns ─────────────────────────────────────────────────────
ALTER TABLE public.techs
  ADD COLUMN IF NOT EXISTS subscription_source TEXT
    CHECK (subscription_source IN ('stripe', 'apple_iap', 'google_play', 'comp'))
    DEFAULT NULL;

ALTER TABLE public.techs
  ADD COLUMN IF NOT EXISTS apple_original_transaction_id TEXT;

ALTER TABLE public.techs
  ADD COLUMN IF NOT EXISTS google_purchase_token TEXT;

ALTER TABLE public.techs
  ADD COLUMN IF NOT EXISTS revenuecat_app_user_id TEXT;

-- ── Document the columns so future-Anne (and dbt / Supabase Studio)
--    sees the intent without reading this file ──────────────────────────
COMMENT ON COLUMN public.techs.subscription_source IS
  'Where this subscription was purchased. NULL for free-tier techs. Set by webhook (stripe-webhook for stripe; revenuecat-webhook for apple_iap and google_play) or by tech_comps trigger (comp). Used for revenue attribution, cancellation routing, and analytics splits.';

COMMENT ON COLUMN public.techs.apple_original_transaction_id IS
  'Apple StoreKit originalTransactionId — stable across renewals. Set by RevenueCat receipt validation. Use this (NOT the per-renewal transaction_id) when reconciling with App Store Connect or RevenueCat APIs.';

COMMENT ON COLUMN public.techs.google_purchase_token IS
  'Google Play Billing purchase token. Set by RevenueCat receipt validation when the subscriber came from Google Play. Use to query Play Developer API for subscription state.';

COMMENT ON COLUMN public.techs.revenuecat_app_user_id IS
  'RevenueCat App User ID — the identifier RevenueCat uses to track this customer across their lifetime. We pass our own user ID (Supabase auth.users.id) as the App User ID, so this column should equal the techs.email-derived user_id in normal cases. Diverges only if a re-attribution happened.';

-- ── Indexes for lookups ─────────────────────────────────────────────────
-- Partial indexes (WHERE not null) keep the index small since most rows
-- have NULL for these IAP-specific fields.
CREATE INDEX IF NOT EXISTS idx_techs_subscription_source
  ON public.techs(subscription_source)
  WHERE subscription_source IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_techs_apple_original_txn
  ON public.techs(apple_original_transaction_id)
  WHERE apple_original_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_techs_google_purchase_token
  ON public.techs(google_purchase_token)
  WHERE google_purchase_token IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_techs_revenuecat_app_user
  ON public.techs(revenuecat_app_user_id)
  WHERE revenuecat_app_user_id IS NOT NULL;

-- ── Backfill existing rows ──────────────────────────────────────────────
-- Only touch rows where subscription_source is still NULL, so re-running
-- the migration doesn't overwrite explicit values written by webhooks
-- in the meantime.
UPDATE public.techs t
   SET subscription_source = 'stripe'
 WHERE t.subscription_source IS NULL
   AND t.stripe_customer_id IS NOT NULL;

-- Comped techs — anyone whose lowercase email appears in tech_comps gets
-- 'comp' as their source. The tech_comps table is the source of truth for
-- grandfathered grants per project_mnc_comps_system memory.
UPDATE public.techs t
   SET subscription_source = 'comp'
 WHERE t.subscription_source IS NULL
   AND t.subscription_tier = 'paid'
   AND lower(t.email) IN (SELECT lower(email) FROM public.tech_comps);

-- ── Lifetime purchase counters ──────────────────────────────────────────
-- Tracks the running total of each product the tech has ever purchased,
-- regardless of source. Useful for "how many Spotlight 10s has this tech
-- bought?" dashboards without scanning a transaction log.
--
-- Updated by webhooks (stripe-webhook for Stripe, revenuecat-webhook for
-- Apple/Google) on every successful purchase event. NOT tied to current
-- credit balance — these are LIFETIME counts that only go up.
--   - glow_up_months_purchased increments on each successful renewal
--   - spotlight_*_purchased_count increments on each one-time purchase
--
-- Decision to denormalize onto techs (rather than only logging to a
-- separate transactions table): keeps the tech dashboard / admin tech
-- detail view a single-row read, which is what those screens actually
-- need. A full per-purchase audit ledger (purchases table) is a smart
-- follow-up if/when we need transaction-level analytics; for now the
-- counters cover "lifetime value per product" reporting.

ALTER TABLE public.techs
  ADD COLUMN IF NOT EXISTS glow_up_months_purchased INT NOT NULL DEFAULT 0;

ALTER TABLE public.techs
  ADD COLUMN IF NOT EXISTS spotlight_1_purchased_count INT NOT NULL DEFAULT 0;

ALTER TABLE public.techs
  ADD COLUMN IF NOT EXISTS spotlight_10_purchased_count INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.techs.glow_up_months_purchased IS
  'Lifetime count of Glow Up subscription months billed. Increments by 1 on every successful renewal (initial purchase = 1, every monthly renewal adds 1). Independent of subscription_source — tallies Stripe + Apple + Google together. Use to compute lifetime sub revenue per tech.';

COMMENT ON COLUMN public.techs.spotlight_1_purchased_count IS
  'Lifetime count of Spotlight 1 Photo one-time bundles purchased. Increments by 1 on each successful purchase regardless of source.';

COMMENT ON COLUMN public.techs.spotlight_10_purchased_count IS
  'Lifetime count of Spotlight 10 Photos one-time bundles purchased. Increments by 1 on each successful purchase regardless of source.';

-- Backfill: techs who have an active Stripe sub today have presumably
-- been billed at least once. Best we can do without an audit log is set
-- the counter to 1 for currently-paid techs as a starting point — true
-- counts will be exact going forward as webhooks fire.
UPDATE public.techs
   SET glow_up_months_purchased = 1
 WHERE subscription_tier = 'paid'
   AND subscription_source = 'stripe'
   AND glow_up_months_purchased = 0;

-- ── Sanity reports — uncomment to see the breakdown after running ──────
-- SELECT subscription_source, count(*) FROM public.techs GROUP BY 1 ORDER BY 2 DESC;
-- SELECT count(*) FILTER (WHERE glow_up_months_purchased > 0)  AS glow_up_subs,
--        sum(glow_up_months_purchased)                          AS total_glow_up_months,
--        sum(spotlight_1_purchased_count)                       AS total_spotlight_1,
--        sum(spotlight_10_purchased_count)                      AS total_spotlight_10
--   FROM public.techs;
