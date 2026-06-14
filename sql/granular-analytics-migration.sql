-- ─────────────────────────────────────────────────────────────────────────
-- MNC, Granular analytics migration
--
-- Run once in Supabase → SQL Editor. Idempotent / safe to re-run.
--
-- Background:
--   The in-app admin "Stats" tab is being retired in favour of the single
--   web dashboard (admin-stats.html). To make that dashboard answer the
--   questions Anne actually asks, "how did people get to the page: QR,
--   phone, or web?" and "how many downloads on Apple vs Android?", we add
--   three things:
--
--     1. marketing_hits.entry_channel, coarse acquisition channel computed
--        in the browser at hit time (qr / social / search / referral /
--        campaign / direct). Lets us split traffic by how it arrived,
--        independent of the device_type (mobile/desktop) we already store.
--
--     2. public.store_clicks, one row every time a marketing
--        visitor taps the App Store or Google Play badge. This is a
--        first-party *download-intent* proxy split by platform. It is NOT a
--        literal install count (people tap and don't always install), but it
--        shows the Apple-vs-Android split and trend for free, today.
--
--     3. public.app_downloads, manual ledger for the TRUE install
--        totals you read out of App Store Connect / Play Console. Admins type
--        in the number for a period; the dashboard shows the latest per
--        platform. This is the source of truth for real downloads until/unless
--        we wire the App Store Connect + Play Developer Reporting APIs.
--
-- RLS model mirrors marketing_hits: anon can INSERT proxy events; only
-- admins (public.is_admin()) can SELECT. app_downloads is admin-only RW.
-- ─────────────────────────────────────────────────────────────────────────


-- ── 1. marketing_hits.entry_channel ──────────────────────────────────────
alter table public.marketing_hits
  add column if not exists entry_channel text;   -- qr|social|search|referral|campaign|direct

create index if not exists marketing_hits_channel_created_idx
  on public.marketing_hits (entry_channel, created_at desc);


-- ── 2. public.store_clicks (download-intent proxy) ───────────────────────
create table if not exists public.store_clicks (
  id            bigserial primary key,
  created_at    timestamptz not null default now(),
  session_id    text,                          -- random v4 UUID, browser-local
  platform      text not null,                 -- 'apple' | 'google'
  page          text,                          -- 'marketing' | 'tech-guide' | …
  entry_channel text,                          -- same vocab as marketing_hits
  device_type   text,                          -- 'mobile' | 'desktop'
  referrer      text,
  utm_source    text,
  utm_medium    text,
  utm_campaign  text
);

create index if not exists store_clicks_created_at_idx
  on public.store_clicks (created_at desc);
create index if not exists store_clicks_platform_created_idx
  on public.store_clicks (platform, created_at desc);

alter table public.store_clicks enable row level security;

drop policy if exists store_clicks_insert_anyone on public.store_clicks;
drop policy if exists store_clicks_select_admin  on public.store_clicks;

create policy store_clicks_insert_anyone
  on public.store_clicks
  as permissive
  for insert
  to anon, authenticated
  with check (true);

create policy store_clicks_select_admin
  on public.store_clicks
  as permissive
  for select
  to authenticated
  using (public.is_admin());


-- ── 3. public.app_downloads (manual true-install ledger) ─────────────────
--   One row per (platform, period) snapshot you key in from the consoles.
--   `total_installs` is the headline number; `period_label` is free text
--   (e.g. 'All-time', 'Week of Jun 1', 'May 2026') so you can record either
--   running totals or per-period deltas, whatever the console gives you.
create table if not exists public.app_downloads (
  id             bigserial primary key,
  created_at     timestamptz not null default now(),
  recorded_for   date not null default (now() at time zone 'utc')::date,
  platform       text not null,                -- 'apple' | 'google'
  period_label   text,                         -- 'All-time' | 'Week of …' | …
  total_installs integer not null default 0,
  note           text,
  recorded_by    text                          -- email of the admin who entered it
);

create index if not exists app_downloads_platform_recorded_idx
  on public.app_downloads (platform, recorded_for desc, created_at desc);

alter table public.app_downloads enable row level security;

drop policy if exists app_downloads_select_admin on public.app_downloads;
drop policy if exists app_downloads_insert_admin on public.app_downloads;
drop policy if exists app_downloads_update_admin on public.app_downloads;
drop policy if exists app_downloads_delete_admin on public.app_downloads;

create policy app_downloads_select_admin
  on public.app_downloads for select to authenticated using (public.is_admin());
create policy app_downloads_insert_admin
  on public.app_downloads for insert to authenticated with check (public.is_admin());
create policy app_downloads_update_admin
  on public.app_downloads for update to authenticated using (public.is_admin());
create policy app_downloads_delete_admin
  on public.app_downloads for delete to authenticated using (public.is_admin());


-- ── Grants ───────────────────────────────────────────────────────────────
grant usage on schema public to anon, authenticated;

grant insert on public.store_clicks to anon, authenticated;
grant select on public.store_clicks to authenticated;
grant usage, select on sequence public.store_clicks_id_seq to anon, authenticated;

grant select, insert, update, delete on public.app_downloads to authenticated;
grant usage, select on sequence public.app_downloads_id_seq to authenticated;


-- ── Verify ────────────────────────────────────────────────────────────────
-- select column_name from information_schema.columns
--   where table_name='marketing_hits' and column_name='entry_channel';
-- select policyname, cmd, roles from pg_policies where tablename='store_clicks';
-- select policyname, cmd, roles from pg_policies where tablename='app_downloads';
-- -- as admin:
-- select platform, count(*) from public.store_clicks group by platform;
-- select * from public.app_downloads order by recorded_for desc;
