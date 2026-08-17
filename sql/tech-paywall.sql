-- ========================================================================
-- MNC 3.0 — TECHS PAY TO BE SEEN  (2026-08-15)
-- ========================================================================
-- Companion to CHANGESET-tech-paywall.md. Run in the Supabase SQL editor
-- (project nwqnakoongrorbwnrqzc). Idempotent, safe to re-run.
--
-- THE MODEL
--   Clients: free forever.
--   Techs: sign up, build a gallery, set hours — all free, no time limit.
--   BEING SEEN (Map, Gallery, bookable) requires an active subscription.
--   First month free via the STORE intro offer, so the trial is a real
--   subscription as far as this database is concerned — no trial state here.
--   The founding techs are free for life.
--
-- ── DESIGN NOTE, READ THIS ──────────────────────────────────────────────
-- This migration deliberately does NOT rewrite get_open_slots() or
-- create_booking(). Those are long functions whose live definitions are the
-- union of four prior migrations, and sql/booking-min-notice.sql documents
-- what happens when someone rebuilds one from an older base:
--
--   "rev 1 of this file was built from the tier-1 version of get_open_slots
--    and silently DROPPED stage D's blocklist and listing_paused checks."
--
-- Not repeating that. Instead:
--
--   * techs.listing_paused stays THE flag every existing function already
--     reads. Nothing that reads it has to change.
--   * A new column, paused_by_tech, records the tech's OWN intent.
--   * listing_paused becomes DERIVED: paused_by_tech OR not-paid. A BEFORE
--     trigger recomputes it on every write; an hourly pg_cron job catches
--     subscriptions that expire while nobody is touching the row.
--   * _booking_gate() IS patched (it is short and self-contained) so the
--     write path is exact with zero lag, belt and braces over the trigger.
--
-- Net effect: an unpaid tech is invisible and unbookable through every path
-- that already honoured the pause switch, and no long function was touched.
-- ========================================================================


-- ── 1. Columns ──────────────────────────────────────────────────────────
alter table public.techs
  add column if not exists paused_by_tech boolean not null default false,
  add column if not exists founder_free   boolean not null default false;

comment on column public.techs.paused_by_tech is
  'The tech''s own "not taking new clients" switch. listing_paused is derived from this plus subscription state — write THIS, never listing_paused.';
comment on column public.techs.founder_free is
  'Grandfathered founding tech: permanently live without a subscription.';

-- Backfill intent from the current effective flag, once.
update public.techs
   set paused_by_tech = coalesce(listing_paused, false)
 where paused_by_tech = false
   and coalesce(listing_paused, false) = true;


-- ── 2. The one calculation ──────────────────────────────────────────────
-- Uses only columns the RevenueCat webhook already maintains
-- (subscription_tier, period_reset_at), so no webhook change is needed.
-- The 3-day grace covers Apple/Google billing retries: a card that fails on
-- renewal should not make a tech vanish from the Gallery the same hour.
create or replace function public.tech_live_calc(
  p_paused_by_tech boolean,
  p_founder_free   boolean,
  p_tier           text,
  p_period_reset   timestamptz
) returns boolean
language sql stable
as $$
  select not coalesce(p_paused_by_tech, false)
     and (
          coalesce(p_founder_free, false)
       or (   p_tier = 'paid'
          and coalesce(p_period_reset, now() + interval '100 years')
              > now() - interval '3 days')
     );
$$;

-- Row-level convenience wrapper, for callers that only have an id.
create or replace function public.tech_is_live(p_tech_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((
    select public.tech_live_calc(t.paused_by_tech, t.founder_free,
                                 t.subscription_tier, t.period_reset_at)
      from public.techs t where t.id = p_tech_id), false);
$$;


-- ── 3. Keep listing_paused derived ──────────────────────────────────────
-- BEFORE trigger so the value is correct the instant it is written, with no
-- second UPDATE and no recursion.
--
-- The legacy-write branch matters: the shipped app still does
-- tbPatchTech({ listing_paused }) (index.html ~14406). Until that ships as
-- paused_by_tech, a direct listing_paused write is treated as the tech's
-- intent and mirrored across — so this migration is safe to run BEFORE the
-- app change, which is the order CLAUDE.md requires.
create or replace function public.techs_derive_listing_paused()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and new.listing_paused is distinct from old.listing_paused
     and new.paused_by_tech is not distinct from old.paused_by_tech then
    new.paused_by_tech := coalesce(new.listing_paused, false);
  end if;

  new.listing_paused := not public.tech_live_calc(
    new.paused_by_tech, new.founder_free,
    new.subscription_tier, new.period_reset_at);

  return new;
end $$;

drop trigger if exists trg_techs_derive_listing_paused on public.techs;
create trigger trg_techs_derive_listing_paused
  before insert or update on public.techs
  for each row execute function public.techs_derive_listing_paused();


-- ── 4. Catch expiries when nobody touches the row ───────────────────────
create or replace function public.sync_tech_visibility()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare v_n integer;
begin
  update public.techs t
     set listing_paused = not public.tech_live_calc(
           t.paused_by_tech, t.founder_free, t.subscription_tier, t.period_reset_at)
   where t.listing_paused is distinct from not public.tech_live_calc(
           t.paused_by_tech, t.founder_free, t.subscription_tier, t.period_reset_at);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- pg_cron is already running booking-reminders (*/15) and standing-extend
-- (daily 9am). Hourly is plenty here; the 3-day grace above absorbs the lag.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('tech-visibility-sync')
      where exists (select 1 from cron.job where jobname = 'tech-visibility-sync');
    perform cron.schedule('tech-visibility-sync', '7 * * * *',
                          $inner$ select public.sync_tech_visibility(); $inner$);
  else
    raise notice 'pg_cron not installed — run sync_tech_visibility() another way';
  end if;
end $$;


-- ── 5. Exact enforcement on the write path ──────────────────────────────
-- Full body carried over from sql/phone-auth-stage-d-blocklist-phone.sql;
-- ONLY the listing_paused test changed. The blocklist half is untouched —
-- diff this against pg_get_functiondef before running if you are unsure.
create or replace function public._booking_gate(p_tech_id uuid) returns void
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_caller    text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_caller_ph text := coalesce(public.current_phone(), '');
begin
  -- was: coalesce(listing_paused, false)
  if not public.tech_is_live(p_tech_id) then
    raise exception 'This tech is not taking bookings right now.';
  end if;
  if exists (
    select 1 from blocked_clients bc
     where bc.tech_id = p_tech_id
       and (   (v_caller <> ''    and bc.client_email = v_caller)
            or (v_caller_ph <> '' and public.phone_digits(bc.client_email) = v_caller_ph))
  ) then
    raise exception 'This tech is not taking bookings right now.';
  end if;
end $$;


-- ── 6. Computed column for the client ───────────────────────────────────
-- Same PostgREST pattern as photos_count. The app filters the Map and the
-- Gallery on is_live instead of listing_paused.
create or replace function public.is_live(public.techs)
returns boolean
language sql stable
as $$
  select public.tech_live_calc($1.paused_by_tech, $1.founder_free,
                               $1.subscription_tier, $1.period_reset_at);
$$;


-- ── 7. Grandfather the founding techs ───────────────────────────────────
-- REVIEW THE SELECT BELOW BEFORE RUNNING THE UPDATE. Deliberately NOT using
-- tech_comps: that table is looked up by email (see loadTechTier), and a
-- phone-only tech has no email, so she could never be comped.

-- ⚠ DO NOT filter this on `joined`. The first version of this file used
--   `where joined < '2026-08-15'`, and NULL < date evaluates to NULL, not
--   true — so every tech with a clobbered/absent joined date was skipped,
--   computed as not-live, and became unbookable the moment _booking_gate
--   started calling tech_is_live(). That hit 21 of Anne's techs on
--   2026-08-15. `joined` is known-unreliable in this database; one of the
--   repo's own commits is "Profile save no longer clobbers availability /
--   joined date". Never gate anything on it.
--
--   Every tech already in this table predates the paywall by definition,
--   so the correct filter is "all of them".

-- Who is about to become free for life:
select id, name, coalesce(email, phone) as identity, joined, founder_free
  from public.techs
 order by joined nulls first;

-- Then, once that list looks right:
update public.techs
   set founder_free = true
 where founder_free = false;


-- ── VERIFY ──────────────────────────────────────────────────────────────
-- Every tech, why she is or is not visible. Read this before shipping.
select
  t.name,
  coalesce(t.email, t.phone)                       as identity,
  t.founder_free,
  t.subscription_tier,
  t.period_reset_at,
  t.paused_by_tech                                 as paused_herself,
  t.listing_paused                                 as effective_hidden,
  public.tech_is_live(t.id)                        as live_now,
  case
    when t.paused_by_tech                              then 'tech paused herself'
    when t.founder_free                                then 'founder, free for life'
    when t.subscription_tier = 'paid'                  then 'paid'
    else                                                    'NOT PAID — hidden'
  end                                              as reason
from public.techs t
order by live_now desc, t.name;

-- Sanity: derived flag must agree with the calculation for every row.
select count(*) as rows_out_of_sync
  from public.techs t
 where t.listing_paused is distinct from not public.tech_is_live(t.id);
-- Expect 0. If not, run: select public.sync_tech_visibility();
