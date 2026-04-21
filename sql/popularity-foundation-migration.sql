-- ========================================================================
-- MNC Popularity Foundation  (2026-04-21)
-- ========================================================================
-- Schema + helper functions that power the popularity surfaces:
--   • ⭐ Tech favorite count   — on tech profile header + browse cards
--   • ♥ Tech heart-total count — same (sum of hearts across all their photos)
--   • ♥ Per-photo heart count  — on each inspo feed card
--   • Profile views this week  — on tech's own dashboard (retention hook)
--   • 🌸 "New on MNC" decay    — uses users.joined, no schema change
--
-- Design notes:
--   • Aggregate queries use SECURITY DEFINER RPC functions so anonymous
--     browsers can see counts without needing SELECT access on the
--     underlying tables (which have row-level RLS). The functions return
--     only scalar counts or (url, count) pairs — never individual
--     user saves, which would be a privacy leak.
--   • Batch variants (tech_fav_counts, tech_heart_counts, photo_heart_counts)
--     take an array of ids so the browse grid can fetch N cards' counts
--     in ONE request, not N.
--   • tech_events is private — admin-only SELECT, plus a private RPC
--     (tech_events_count) that only the tech themselves or an admin can
--     invoke meaningfully. Prevents competing techs from spying on each
--     other's view counts.
--
-- Safe to re-run — all DDL is idempotent; functions use CREATE OR REPLACE.
-- ========================================================================


-- ========================================================================
-- BLOCK 1 — tech_events table
-- ========================================================================
-- Event log for techs. Every meaningful interaction (profile open,
-- Book Now tap, anything we add later) gets a row here. The client
-- writes directly via PostgREST; aggregates come out via RPC.
-- ========================================================================

create table if not exists public.tech_events (
  id           uuid primary key default gen_random_uuid(),
  tech_email   text not null,
  event_type   text not null,
  actor_email  text,
  created_at   timestamptz not null default now(),
  metadata     jsonb
);

-- Primary lookup: "events for this tech in the last N days"
create index if not exists tech_events_tech_email_created_at_idx
  on public.tech_events (tech_email, created_at desc);

-- Secondary: "all events of this type" (analytics / anti-abuse scans)
create index if not exists tech_events_event_type_idx
  on public.tech_events (event_type);


-- ========================================================================
-- BLOCK 2 — tech_events RLS
-- ========================================================================
-- • Authenticated users can INSERT any event (needed for anonymous-ish
--   profile-view logging). Intentionally permissive; worst abuse is a
--   tech inflating their own counts, which just misleads themselves.
-- • SELECT is admin-only. Techs get counts via tech_events_count() RPC
--   below which enforces access rules inside the function body.
-- ========================================================================

alter table public.tech_events enable row level security;

drop policy if exists tech_events_insert on public.tech_events;
create policy tech_events_insert on public.tech_events
  for insert to authenticated
  with check (true);

drop policy if exists tech_events_select_admin on public.tech_events;
create policy tech_events_select_admin on public.tech_events
  for select to authenticated
  using (is_admin());


-- ========================================================================
-- BLOCK 3 — Public popularity count RPCs (safe to expose broadly)
-- ========================================================================
-- Scalar counts for a single tech / photo, and batch variants for browse
-- grids. SECURITY DEFINER so they work for anon visitors — only scalar
-- counts leave the function, never individual save rows.
-- ========================================================================

-- ⭐ Single tech's fav count
create or replace function public.tech_fav_count(p_tech_email text)
  returns bigint
  language sql
  security definer
  set search_path = public
as $$
  select count(*)
    from public.user_favorites
   where lower(btrim(tech_email)) = lower(btrim(p_tech_email));
$$;

-- ⭐ Batch: fav counts for a list of tech emails (for browse grid)
create or replace function public.tech_fav_counts(p_tech_emails text[])
  returns table(tech_email text, cnt bigint)
  language sql
  security definer
  set search_path = public
as $$
  select lower(btrim(tech_email)) as tech_email, count(*)::bigint
    from public.user_favorites
   where lower(btrim(tech_email)) = any(
     select lower(btrim(e)) from unnest(p_tech_emails) e
   )
   group by lower(btrim(tech_email));
$$;

-- ♥ Single tech's total heart count (all their photos summed)
create or replace function public.tech_heart_count(p_tech_email text)
  returns bigint
  language sql
  security definer
  set search_path = public
as $$
  select count(*)
    from public.user_inspo
   where lower(btrim(tech_email)) = lower(btrim(p_tech_email));
$$;

-- ♥ Batch: heart totals for a list of tech emails
create or replace function public.tech_heart_counts(p_tech_emails text[])
  returns table(tech_email text, cnt bigint)
  language sql
  security definer
  set search_path = public
as $$
  select lower(btrim(tech_email)) as tech_email, count(*)::bigint
    from public.user_inspo
   where lower(btrim(tech_email)) = any(
     select lower(btrim(e)) from unnest(p_tech_emails) e
   )
   group by lower(btrim(tech_email));
$$;

-- ♥ Single photo's heart count
create or replace function public.photo_heart_count(p_photo_url text)
  returns bigint
  language sql
  security definer
  set search_path = public
as $$
  select count(*)
    from public.user_inspo
   where photo_url = p_photo_url;
$$;

-- ♥ Batch: heart counts for a list of photo URLs (for inspo feed load)
create or replace function public.photo_heart_counts(p_photo_urls text[])
  returns table(photo_url text, cnt bigint)
  language sql
  security definer
  set search_path = public
as $$
  select photo_url, count(*)::bigint
    from public.user_inspo
   where photo_url = any(p_photo_urls)
   group by photo_url;
$$;

grant execute on function public.tech_fav_count(text)          to anon, authenticated;
grant execute on function public.tech_fav_counts(text[])       to anon, authenticated;
grant execute on function public.tech_heart_count(text)        to anon, authenticated;
grant execute on function public.tech_heart_counts(text[])     to anon, authenticated;
grant execute on function public.photo_heart_count(text)       to anon, authenticated;
grant execute on function public.photo_heart_counts(text[])    to anon, authenticated;


-- ========================================================================
-- BLOCK 4 — Private tech_events count RPC (tech-only / admin-only)
-- ========================================================================
-- Unlike popularity counts (which are social proof visible to everyone),
-- profile-view counts are private to the tech themselves — no other tech
-- should see "how many people viewed Leslie's profile this week." This
-- function enforces that rule inside the function body so the public
-- anon role can't bypass it.
-- ========================================================================

create or replace function public.tech_events_count(
  p_tech_email text,
  p_event_type text,
  p_since      timestamptz default (now() - interval '7 days')
) returns bigint
  language sql
  security definer
  set search_path = public
as $$
  select count(*)
    from public.tech_events
   where lower(btrim(tech_email)) = lower(btrim(p_tech_email))
     and event_type = p_event_type
     and created_at >= p_since
     and (
       is_admin()
       or lower(btrim(tech_email)) = lower(btrim(coalesce(auth.email(), '')))
     );
$$;

grant execute on function public.tech_events_count(text, text, timestamptz)
  to authenticated;


-- ========================================================================
-- BLOCK 5 — SMOKE TEST (optional)
-- ========================================================================
-- Run after the DDL above. These should all return counts, not errors.
-- ========================================================================

-- select public.tech_fav_count('some-tech@example.com');        -- scalar bigint
-- select * from public.tech_fav_counts(array['a@b.com','c@d.com']);  -- (tech_email, cnt) rows
-- select public.photo_heart_count('https://...some.jpg');
-- select * from public.photo_heart_counts(
--   array(select photo_url from public.user_inspo limit 5)
-- );
-- Should succeed and return 0 (no tech_events yet):
-- select public.tech_events_count('some-tech@example.com', 'profile_open');
