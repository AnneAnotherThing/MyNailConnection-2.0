-- ─────────────────────────────────────────────────────────────────────────
-- MNC, Marketing site hit tracker
--
-- Run this once in Supabase → SQL Editor. Safe to re-run (idempotent).
--
-- Background:
--   The app's admin Stats tab needs visibility into traffic to the public
--   marketing pages (marketing.html → mynailconnection.com/, plus
--   tech-guide.html). Rather than wire in a third-party analytics SaaS,
--   we log lightweight first-party "hits" into Supabase so Anne / Leslie
--   can see them right next to all the other admin metrics.
--
-- What this migration does:
--   1. Creates public.marketing_hits, one row per "session" (per-page,
--      30-minute cooldown enforced client-side via localStorage).
--   2. Sets up RLS so anonymous visitors can INSERT (the marketing pages
--      are unauthenticated), and only admins can SELECT (relies on the
--      existing public.is_admin() function from admin-stats-migration.sql).
--
-- Privacy notes:
--   - We do NOT store IP addresses or precise geo. session_id is a random
--     v4 UUID generated in the browser; it's not tied to any account.
--   - user_agent is captured raw mainly so we can spot obvious bot
--     patterns later, and so we can debug "why is the count weird".
--     If you'd rather not keep raw UA, drop the column, the device_type
--     summary (mobile/desktop) is enough for the dashboard.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.marketing_hits (
  id            bigserial primary key,
  created_at    timestamptz not null default now(),
  session_id    text,                          -- random v4 UUID, browser-local
  page          text not null,                 -- 'marketing' | 'tech-guide' | …
  referrer      text,                          -- document.referrer (may be empty)
  device_type   text,                          -- 'mobile' | 'desktop'
  user_agent    text,                          -- raw UA for debugging
  utm_source    text,
  utm_medium    text,
  utm_campaign  text
);

create index if not exists marketing_hits_created_at_idx
  on public.marketing_hits (created_at desc);
create index if not exists marketing_hits_page_created_idx
  on public.marketing_hits (page, created_at desc);
create index if not exists marketing_hits_session_idx
  on public.marketing_hits (session_id);

alter table public.marketing_hits enable row level security;

drop policy if exists marketing_hits_insert_anyone on public.marketing_hits;
drop policy if exists marketing_hits_select_admin  on public.marketing_hits;

-- Anyone (anon visitor on the marketing page) can log a hit.
create policy marketing_hits_insert_anyone
  on public.marketing_hits
  as permissive
  for insert
  to anon, authenticated
  with check (true);

-- Only admins (per public.is_admin()) can read hits.
create policy marketing_hits_select_admin
  on public.marketing_hits
  as permissive
  for select
  to authenticated
  using (public.is_admin());

grant usage on schema public to anon, authenticated;
grant insert on public.marketing_hits to anon, authenticated;
grant select on public.marketing_hits to authenticated;
grant usage, select on sequence public.marketing_hits_id_seq to anon, authenticated;

-- ── Verify ────────────────────────────────────────────────────────────────
-- After running:
--   select policyname, cmd, roles from pg_policies where tablename='marketing_hits';
--   select count(*) from public.marketing_hits;            -- as admin
--   select page, count(*) from public.marketing_hits group by page;
