-- ============================================================================
-- DEFAULT NEW TECHS TO "THIS WEEK" + "NEW CLIENTS" ON  (2026-09-06, Anne)
-- ============================================================================
-- "Let's default to taking new clients and taking clients this week."
--
-- A brand-new tech showed up with all three availability chips OFF —
-- invisible in every availability filter until she found the chips herself.
-- Now she starts visible:
--   * accepting_new_clients → true (never auto-resets; hers to turn off)
--   * is_same_day ("This week") → true (still auto-resets Sunday midnight,
--     so it stays honest — one week of default visibility, then she owns it)
--   * is_available ("Open today") stays default FALSE on purpose: it resets
--     nightly and means "chair time TODAY" — that one is the daily ritual
--     the in-app popup now teaches, never a default.
--
-- The signup RPC inserts into public.techs WITHOUT naming these columns,
-- so column defaults apply to every new signup path automatically.
--
-- Run in the Supabase SQL editor (nwqnakoongrorbwnrqzc). Idempotent.
-- ============================================================================

alter table public.techs alter column accepting_new_clients set default true;
alter table public.techs alter column is_same_day           set default true;

-- ── OPTIONAL BACKFILL — existing techs ──────────────────────────────────────
-- Uncomment to also flip every CURRENT tech to "This week" + "New clients".
-- Tradeoff: "This week" claims she has openings in the next few days, which
-- nobody asked her — but it self-corrects Sunday at midnight, and being
-- findable for a week beats being invisible forever. Anne's call.
--
-- update public.techs
--    set accepting_new_clients = true,
--        is_same_day = true
--  where accepting_new_clients is distinct from true
--     or is_same_day is distinct from true;

-- Verify:
select column_name, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'techs'
  and column_name in ('is_available','is_same_day','accepting_new_clients');
