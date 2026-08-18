-- ========================================================================
-- SPLIT: being SEEN is free, being BOOKED is paid   (2026-08-17)
-- ========================================================================
-- Supersedes the single is_live concept in sql/tech-paywall.sql. Run AFTER
-- that file and after sql/paywall-switch.sql. Idempotent, safe to re-run.
--
-- WHY
--   Gating visibility behind payment is self-defeating. A paid-only Gallery
--   is guaranteed to be thin; a thin Gallery means clients find nobody
--   nearby, so the client side never starts, so discovery never becomes
--   real, so the thing that would justify charging never arrives. The free
--   tier's job right now is to FILL the Gallery.
--
--   A tech who is seen and gets a phone call is a win: she is in the
--   Gallery, her work draws clients, and she costs about five cents a month
--   to host. Some of those techs will never pay. That leak is real, and it
--   is the wrong thing to optimise while adoption is the constraint. You
--   cannot leak revenue you were never going to collect.
--
-- THE SPLIT
--   is_visible  = she has not paused herself.              FREE.
--                 Gallery, Map, profile, Call / Text, and her external
--                 booking_link (a tech on Vagaro who lists MNC as her
--                 portfolio is still filling the Gallery).
--   is_bookable = is_visible AND (founding tech OR paid).  PAID.
--                 MNC's own booking engine: get_open_slots, create_booking.
--
--   listing_paused stays derived as NOT is_bookable, which is exactly what
--   get_open_slots() and create_booking() already read — so those two long
--   functions still need no edit. That was the point of deriving it. See
--   sql/booking-min-notice.sql for what happened the one time someone
--   rebuilt one of them from an older base.
-- ========================================================================


-- ── 1. The paywall master switch ────────────────────────────────────────
-- One function, one word. Flip to true in the SAME release that ships the
-- purchase sheet, never before. Replaces the commented-block approach in
-- sql/paywall-switch.sql.
create or replace function public.paywall_enabled()
returns boolean language sql immutable as $fn$
  select false;   -- <<< change to true when techs can actually pay
$fn$;


-- ── 2. The two calculations ─────────────────────────────────────────────
create or replace function public.tech_visible_calc(p_paused_by_tech boolean)
returns boolean language sql immutable as $fn$
  select not coalesce(p_paused_by_tech, false);
$fn$;

create or replace function public.tech_bookable_calc(
  p_paused_by_tech boolean,
  p_founder_free   boolean,
  p_tier           text,
  p_period_reset   timestamptz
) returns boolean language sql stable as $fn$
  select public.tech_visible_calc(p_paused_by_tech)
     and (
          not public.paywall_enabled()
       or coalesce(p_founder_free, false)
       or (   p_tier = 'paid'
          -- 3-day grace so a card that fails on renewal does not make her
          -- vanish the same hour Apple is still retrying.
          and coalesce(p_period_reset, now() + interval '100 years')
              > now() - interval '3 days')
     );
$fn$;

create or replace function public.tech_is_visible(p_tech_id uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select coalesce((select public.tech_visible_calc(t.paused_by_tech)
                     from public.techs t where t.id = p_tech_id), false);
$fn$;

create or replace function public.tech_is_bookable(p_tech_id uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select coalesce((select public.tech_bookable_calc(t.paused_by_tech, t.founder_free,
                                                    t.subscription_tier, t.period_reset_at)
                     from public.techs t where t.id = p_tech_id), false);
$fn$;

-- Back-compat. tech_live_calc / tech_is_live came from sql/tech-paywall.sql
-- and are what the CURRENTLY DEPLOYED app reads for its Gallery and Map
-- filters. Point them at VISIBILITY so the shipped build keeps behaving
-- correctly until the split-aware build replaces it. Do not drop these
-- until that build is live on both stores.
create or replace function public.tech_live_calc(
  p_paused_by_tech boolean, p_founder_free boolean,
  p_tier text, p_period_reset timestamptz
) returns boolean language sql stable as $fn$
  select public.tech_visible_calc(p_paused_by_tech);
$fn$;

create or replace function public.tech_is_live(p_tech_id uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select public.tech_is_visible(p_tech_id);
$fn$;


-- ── 3. Computed columns the client reads ────────────────────────────────
-- Reminder: PostgREST does NOT return computed columns for select=*. They
-- must be named explicitly, or they arrive undefined and every filter reads
-- the wrong answer. That would have hidden every tech at once.
create or replace function public.is_visible(public.techs)
returns boolean language sql stable as $fn$
  select public.tech_visible_calc($1.paused_by_tech);
$fn$;

create or replace function public.is_bookable(public.techs)
returns boolean language sql stable as $fn$
  select public.tech_bookable_calc($1.paused_by_tech, $1.founder_free,
                                   $1.subscription_tier, $1.period_reset_at);
$fn$;

-- Deprecated alias for the shipped build. Equals is_visible.
create or replace function public.is_live(public.techs)
returns boolean language sql stable as $fn$
  select public.tech_visible_calc($1.paused_by_tech);
$fn$;


-- ── 4. listing_paused stays derived, now from BOOKABILITY ────────────────
create or replace function public.techs_derive_listing_paused()
returns trigger language plpgsql as $fn$
begin
  -- Legacy-write branch: the shipped app still PATCHes listing_paused
  -- directly. Treat that as the tech's own intent until the new build lands.
  if tg_op = 'UPDATE'
     and new.listing_paused is distinct from old.listing_paused
     and new.paused_by_tech is not distinct from old.paused_by_tech then
    new.paused_by_tech := coalesce(new.listing_paused, false);
  end if;

  new.listing_paused := not public.tech_bookable_calc(
    new.paused_by_tech, new.founder_free,
    new.subscription_tier, new.period_reset_at);

  return new;
end $fn$;

create or replace function public.sync_tech_visibility()
returns integer language plpgsql security definer set search_path = public as $fn$
declare v_n integer;
begin
  update public.techs t
     set listing_paused = not public.tech_bookable_calc(
           t.paused_by_tech, t.founder_free, t.subscription_tier, t.period_reset_at)
   where t.listing_paused is distinct from not public.tech_bookable_calc(
           t.paused_by_tech, t.founder_free, t.subscription_tier, t.period_reset_at);
  get diagnostics v_n = row_count;
  return v_n;
end $fn$;


-- ── 5. The booking write path gates on BOOKABILITY ──────────────────────
-- Body carried over from sql/phone-auth-stage-d-blocklist-phone.sql; only
-- the pause test changed. The blocklist half is untouched.
create or replace function public._booking_gate(p_tech_id uuid) returns void
language plpgsql stable security definer set search_path = public as $fn$
declare
  v_caller    text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_caller_ph text := coalesce(public.current_phone(), '');
begin
  if not public.tech_is_bookable(p_tech_id) then
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
end $fn$;

select public.sync_tech_visibility() as rows_resynced;


-- ── VERIFY ──────────────────────────────────────────────────────────────
select
  t.name,
  t.paused_by_tech               as paused_herself,
  t.founder_free,
  t.subscription_tier,
  public.tech_is_visible(t.id)   as seen_in_gallery,
  public.tech_is_bookable(t.id)  as can_be_booked,
  case
    when t.paused_by_tech             then 'she paused herself'
    when not public.paywall_enabled() then 'paywall OFF, everyone bookable'
    when t.founder_free               then 'founding tech, free for life'
    when t.subscription_tier = 'paid' then 'paid'
    else                                   'visible, but not bookable'
  end                            as reason
from public.techs t
order by can_be_booked, seen_in_gallery, t.name;

-- Must be 0.
select count(*) as rows_out_of_sync
  from public.techs t
 where t.listing_paused is distinct from not public.tech_is_bookable(t.id);

-- Paywall state, so nobody has to guess.
select public.paywall_enabled() as paywall_is_on;
