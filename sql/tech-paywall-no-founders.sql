-- ========================================================================
-- REMOVE FOUNDER GRANDFATHERING: one rule for every tech   (2026-08-17)
-- ========================================================================
-- Run AFTER sql/tech-paywall-split.sql. Idempotent, safe to re-run.
--
-- Anne, 2026-08-17: "I don't care if they're free forever. Let's just treat
-- these techs like everyone else. They wouldn't even get on to test, we're
-- taking too much care of them. It was free for them when we didn't have
-- booking. They're just early adopters."
--
-- She is right, and it removes a whole class of future confusion. The 21
-- existing accounts were promised a product that had no booking engine. The
-- booking engine is a new thing, and it costs the same for everybody.
--
-- THE MODEL, ENTIRE
--   Signup, profile, gallery, Gallery placement, Map placement, Call / Text,
--   and an external booking_link:      FREE for everyone, no time limit.
--   MNC's own booking engine:          subscription. Three months free via
--                                      the STORE intro offer, then $10.99.
--   No exceptions, no grandfathering, no per-account carve-outs.
--
-- The three-month trial is delivered by the App Store / Play introductory
-- offer, NOT by this database. During the trial RevenueCat reports an active
-- entitlement, the webhook writes subscription_tier='paid', and the tech is
-- bookable. That is why there is no trial state here to get out of sync.
--
-- CONSEQUENCE, EYES OPEN: once paywall_enabled() returns true, any tech with
-- booking switched on who has not subscribed becomes unbookable. Send the 21
-- a heads-up before flipping it; do not let them find out from a client.
-- ========================================================================


-- ── 1. Bookability no longer knows about founders ───────────────────────
-- Signature changes (the p_founder_free parameter is gone), so the old
-- 4-arg version is dropped explicitly first. Every caller is updated below
-- in the same transaction.
drop function if exists public.tech_bookable_calc(boolean, boolean, text, timestamptz);

create or replace function public.tech_bookable_calc(
  p_paused_by_tech boolean,
  p_tier           text,
  p_period_reset   timestamptz
) returns boolean language sql stable as $fn$
  select public.tech_visible_calc(p_paused_by_tech)
     and (
          not public.paywall_enabled()
       or (   p_tier = 'paid'
          -- 3-day grace so a card that fails on renewal does not make her
          -- vanish the same hour Apple is still retrying the charge.
          and coalesce(p_period_reset, now() + interval '100 years')
              > now() - interval '3 days')
     );
$fn$;

create or replace function public.tech_is_bookable(p_tech_id uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select coalesce((select public.tech_bookable_calc(t.paused_by_tech,
                                                    t.subscription_tier, t.period_reset_at)
                     from public.techs t where t.id = p_tech_id), false);
$fn$;

create or replace function public.is_bookable(public.techs)
returns boolean language sql stable as $fn$
  select public.tech_bookable_calc($1.paused_by_tech, $1.subscription_tier, $1.period_reset_at);
$fn$;


-- ── 2. Trigger + resync drop the founder argument ───────────────────────
create or replace function public.techs_derive_listing_paused()
returns trigger language plpgsql as $fn$
begin
  new.listing_paused := not public.tech_bookable_calc(
    new.paused_by_tech, new.subscription_tier, new.period_reset_at);
  return new;
end $fn$;

create or replace function public.sync_tech_visibility()
returns integer language plpgsql security definer set search_path = public as $fn$
declare v_n integer;
begin
  update public.techs t
     set listing_paused = not public.tech_bookable_calc(
           t.paused_by_tech, t.subscription_tier, t.period_reset_at)
   where t.listing_paused is distinct from not public.tech_bookable_calc(
           t.paused_by_tech, t.subscription_tier, t.period_reset_at);
  get diagnostics v_n = row_count;
  return v_n;
end $fn$;


-- ── 3. Retire the column ────────────────────────────────────────────────
-- Dropped rather than left unused. A column named founder_free that grants
-- nothing is exactly the kind of thing someone re-wires by accident later.
alter table public.techs drop column if exists founder_free;

select public.sync_tech_visibility() as rows_resynced;


-- ── VERIFY ──────────────────────────────────────────────────────────────
select
  t.name,
  t.paused_by_tech               as paused_herself,
  t.subscription_tier,
  t.booking_enabled,
  public.tech_is_visible(t.id)   as seen_in_gallery,
  public.tech_is_bookable(t.id)  as can_be_booked,
  case
    when t.paused_by_tech             then 'she paused herself'
    when not public.paywall_enabled() then 'paywall OFF, everyone bookable'
    when t.subscription_tier = 'paid' then 'subscribed'
    else                                   'visible, needs a subscription to take bookings'
  end                            as reason
from public.techs t
order by can_be_booked, t.name;

-- Must be 0.
select count(*) as rows_out_of_sync
  from public.techs t
 where t.listing_paused is distinct from not public.tech_is_bookable(t.id);

-- Must return 0 rows: nothing may still reference founder_free.
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'techs' and column_name = 'founder_free';

-- WHO GETS CUT OFF when you flip the switch. Text these people first.
select t.name, coalesce(t.email, t.phone) as identity, t.booking_enabled
  from public.techs t
 where t.booking_enabled
   and coalesce(t.subscription_tier, 'free') <> 'paid'
   and not coalesce(t.paused_by_tech, false)
 order by t.name;

select public.paywall_enabled() as paywall_is_on;
