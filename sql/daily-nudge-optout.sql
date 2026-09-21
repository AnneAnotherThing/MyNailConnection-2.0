-- ============================================================================
-- daily-nudge-optout.sql  (2026-09-20)
--
-- Account-level opt-out for the daily "are you open today?" reminder. The
-- in-app nudge (maybeDailyAvailPrompt) had no off switch; this adds one that
-- lives on the tech's row, so it follows her across devices and will also
-- govern the future morning push.
--
-- Default false = reminder on (unchanged behavior for everyone today). The tech
-- already updates her own techs row (availability chips, booking toggles), so
-- no new RLS is needed to let her flip this.
--
-- Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc). Re-runnable.
-- ============================================================================

alter table public.techs
  add column if not exists daily_avail_nudge_off boolean not null default false;

comment on column public.techs.daily_avail_nudge_off is
  'When true, suppress the daily open-today reminder (the in-app prompt and the future morning push). Default false = reminder on.';
