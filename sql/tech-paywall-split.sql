-- ========================================================================
-- SPLIT: being SEEN is free, being BOOKED is paid   (2026-08-17, rev 2)
-- ========================================================================
-- Run AFTER sql/tech-paywall.sql. Supersedes sql/paywall-switch.sql, which
-- can be deleted once this has run. Idempotent, safe to re-run.
--
-- REV 2 REMOVES ALL BACK-COMPAT. Rev 1 kept tech_live_calc / tech_is_live /
-- is_live as aliases so an already-shipped build would keep working. There
-- is no such build — 3.0 has never been through App Review and nobody is
-- depending on the current bundle. Carrying two names for one idea is how
-- the next person gets it wrong, so the old names are DROPPED here and the
-- app is updated in the same change.
--
-- WHY THE SPLIT
--   Gating visibility behind payment is self-defeating. A paid-only Gallery
--   is guaranteed to be thin; a thin Gallery means clients find nobody
--   nearby, so the client side never starts, so discovery never becomes
--   real, so the thing that would justify charging never arrives. The free
--   tier's job is to FILL the Gallery.
--
--   A tech who is seen and gets a phone call is a win: she is in the
--   Gallery, her work draws clients, and she costs about five cents a month
--   to host. Some of those techs will never pay. That leak is real, and it
--   is the wrong thing to optimise while adoption is the constraint. You
--   cannot leak revenue you were never going to collect.
--
-- THE MODEL
--   is_visible  = she has not paused herself.              FREE.
--                 Gallery, Map, profile, Call / Text, and her external
--                 booking_link (a tech on Vagaro who lists MNC as her
--                 portfolio is still filling the Gallery).
--   is_bookable = is_visible AND (founding tech OR paid).  PAID.
--                 MNC's own booking engine: get_open_slots, create_booking.
--
--   listing_paused stays derived as NOT is_bookable, which is exactly what
--   get_open_slots() and create_booking() already read — so those two long
--   functions need no edit. That was the point of deriving it. See
--   sql/booking-min-notice.sql for what happened the one time someone
--   rebuilt one of them from an older base and silently dropped a feature.
-- ========================================================================


-- ── 1. The paywall master switch ────────────────────────────────────────
-- One function, one word. Flip to true in the SAME release that ships the
-- purchase sheet, never before.
create or replace function public.paywall_enabled()
returns boolean language sql immutable as $fn$
  select false;   -- <<< change to true when techs can actually pay
$fn$;

comment on function public.paywall_enabled() is
  'Master switch for the tech paywall. false = everyone bookable. Flip to true only in the release that ships the purchase sheet.';


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
          -- vanish the same hour Apple is still retrying the charge.
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


-- ── 3. Computed columns the client reads ────────────────────────────────
-- PostgREST does NOT return computed columns for select=*. They must be
-- named explicitly in the select, or they arrive undefined and every filter
-- reads the wrong answer — which would hide every tech at once.
create or replace function public.is_visible(public.techs)
returns boolean language sql stable as $fn$
  select public.tech_visible_calc($1.paused_by_tech);
$fn$;

create or replace function public.is_bookable(public.techs)
returns boolean language sql stable as $fn$
  select public.tech_bookable_calc($1.paused_by_tech, $1.founder_free,
                                   $1.subscription_tier, $1.period_reset_at);
$fn$;


-- ── 4. listing_paused stays derived, from BOOKABILITY ────────────────────
-- No legacy-write branch. The app writes paused_by_tech and only that; a
-- direct write to listing_paused is now simply overwritten, which is correct
-- because listing_paused is output, not input.
create or replace function public.techs_derive_listing_paused()
returns trigger language plpgsql as $fn$
begin
  new.listing_paused := not public.tech_bookable_calc(
    new.paused_by_tech, new.founder_free,
    new.subscription_tier, new.period_reset_at);
  return new;
end $fn$;

drop trigger if exists trg_techs_derive_listing_paused on public.techs;
create trigger trg_techs_derive_listing_paused
  before insert or update on public.techs
  for each row execute function public.techs_derive_listing_paused();

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
-- Body carried from sql/phone-auth-stage-d-blocklist-phone.sql; only the
-- pause test changed. The blocklist half is untouched.
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


-- ── 6. Drop the single-concept generation ───────────────────────────────
-- These came from sql/tech-paywall.sql rev 1, when visibility and
-- bookability were one idea. Two names for one thing is how the next change
-- goes wrong. Run the app update in the same release.
drop function if exists public.is_live(public.techs);
drop function if exists public.tech_is_live(uuid);
drop function if exists public.tech_live_calc(boolean, boolean, text, timestamptz);

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

-- Must return 0 rows: nothing should reference the dropped names.
select p.proname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('is_live','tech_is_live','tech_live_calc');

select public.paywall_enabled() as paywall_is_on;
