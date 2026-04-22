-- ============================================================================
-- MNC Stripe Billing Migration (2026-04-21)
-- ============================================================================
-- Sets up everything the stripe-webhook edge function depends on:
--
--   1. Billing columns on public.techs (subscription_tier, photo_credits,
--      subscription_expires_at). The README previously listed these as a
--      copy-paste block; this formalizes them.
--   2. stripe_customer_id on public.techs — set on first checkout, then
--      used by customer.subscription.updated / .deleted events so the
--      webhook can find the right tech row without an extra Stripe API
--      call.
--   3. public.stripe_events — dedupe table, primary key on event.id.
--      The webhook inserts every event's id before processing; if insert
--      fails with unique_violation, we know it's a retry and skip it.
--      Prevents double-crediting on Stripe retries.
--
-- Safe to re-run. All statements are IF NOT EXISTS.
-- ============================================================================


-- ── BLOCK 1 — Billing columns on techs ───────────────────────────────────────
alter table public.techs
  add column if not exists subscription_tier       text default 'free',
  add column if not exists photo_credits           int  default 0,
  add column if not exists subscription_expires_at timestamptz,
  add column if not exists stripe_customer_id      text;

create index if not exists techs_stripe_customer_idx
  on public.techs (stripe_customer_id)
  where stripe_customer_id is not null;


-- ── BLOCK 2 — Webhook idempotency table ─────────────────────────────────────
-- stripe_events exists purely to dedupe webhook deliveries. We insert
-- event.id before processing; duplicates fail with unique_violation and
-- the webhook short-circuits. 90-day TTL is managed by the cleanup job
-- at the bottom (run manually or via pg_cron if you wire that up).
create table if not exists public.stripe_events (
  event_id    text primary key,
  type        text,
  received_at timestamptz not null default now()
);

-- Only the service role writes to this table (edge function uses the
-- service role key). Lock it down from everything else.
alter table public.stripe_events enable row level security;

drop policy if exists stripe_events_noread on public.stripe_events;
create policy stripe_events_noread on public.stripe_events
  for all using (false) with check (false);
-- Note: the service role bypasses RLS entirely, so the webhook can still
-- insert/read. This policy just blocks anon/authenticated callers.


-- ── BLOCK 3 — (Optional) cleanup of old event records ───────────────────────
-- Keep ~90 days of dedupe history. Stripe's automatic retry window is
-- well under that. Run this ad-hoc in SQL Editor occasionally, or wire
-- it into pg_cron if you want it automatic.
--
-- delete from public.stripe_events where received_at < now() - interval '90 days';
