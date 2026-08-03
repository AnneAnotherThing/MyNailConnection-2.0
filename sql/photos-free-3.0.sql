-- ========================================================================
-- 3.0 IS FREE, PERMANENTLY (2026-08-03, rev 4)
--
-- REV 4: restores the phone-identity lookup (email OR phone) that rev 3
-- accidentally clobbered from stage C. Found live in Anne's launch lap:
-- phone-signup techs got reason=not_found on every upload.
--
-- FINAL SHAPE. Photos are free forever. There is no lifetime ceiling and
-- no photo paywall. A monthly upload allowance exists ONLY to stop abuse
-- and runaway storage, not to sell anything.
--
--   Free tech (no subscription):  50 uploads per month, forever
--   Glow Up subscriber:           150 uploads per month
--   Comped tech (tech_comps):     tech_comps.monthly_limit, unchanged
--   Anyone holding photo_credits: credits still spend, and can burst
--                                 PAST the monthly allowance
--
-- WHY THIS REPLACES REV 2's LIFETIME CEILING
-- Rev 2 gave 100 free photos for life, then asked for $10.99. That put a
-- wall in front of exactly the wrong tech: the prolific, proud one who is
-- filling the Gallery for you. She hits it, gets blocked, and it becomes a
-- support conversation. Worse, it re-coupled Glow Up to photos, the very
-- thing we decided not to charge for -- Glow Up is meant to become
-- booking-side value (no-show deposits, rebooking reminders, salon
-- accounts). A monthly allowance never permanently blocks anyone, resets
-- itself, and needs no explaining: "post up to 50 looks a month, free,
-- forever."
--
-- WHY 50/MONTH
-- A tech doing five sets a day realistically photographs and posts her
-- best one or two, so 40-50 covers an enthusiastic tech without ever
-- binding. 50 photos is ~14MB per tech per month at ~280KB each. It is
-- also a dial: dropping to 25 is a one-number edit with no migration.
--
-- STRUCTURAL SIMPLIFICATION
-- Free techs now use the SAME period_upload_count / period_reset_at
-- mechanic that subscribers already use -- one model for everybody, only
-- the cap differs. lifetime_free_used is still incremented so historical
-- analytics keep working, but it NO LONGER GATES anything.
--
-- CAPACITY (Supabase Pro: 100GB storage, 250GB egress, $25/mo)
--   ~280KB per photo including thumbnail
--   50,000 techs x 30 photos = ~420GB storage = ~$7/mo in overage
--   Egress is the real meter and is driven by CLIENTS BROWSING, not by
--   techs uploading. Serving thumbnails in the Gallery grid rather than
--   full-size images is worth ~4x, far more than any upload cap.
--   Escape hatch if egress ever runs away: move objects behind Cloudflare
--   R2 (zero egress fees).
--
-- NOTHING IS REMOVED. photo_credits, tech_comps, subscription_tier and
-- the whole Stripe/IAP path stay intact. Pay-per-photo (Spotlight) is
-- retired from the UI, not from the schema.
--
-- Supersedes: first-photo-free-migration.sql, and revs 1 and 2.
-- Pairs with: index.html NEW_TECH_FREE_PHOTOS = 50
--             STRIPE_CONFIG.free_limit    = 50
--
-- Run in the Supabase SQL editor. Idempotent, safe to re-run.
-- ========================================================================

create or replace function public.consume_upload_slot(p_email text)
returns table (
  ok                 boolean,
  slot_type          text,
  reason             text,
  remaining_weekly   integer,
  remaining_credits  integer,
  weekly_reset_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tech_id           uuid;
  v_tier              text;
  v_expires_at        timestamptz;
  v_credits           integer;
  v_period_count      integer;
  v_period_reset      timestamptz;
  v_free_used         integer;
  v_comp_limit        integer;
  -- The three caps. All monthly. Change these and nothing else.
  v_free_cap      constant integer := 50;    -- free tech, forever
  v_glowup_cap    constant integer := 150;   -- Glow Up subscriber
  v_period_cap        integer;
  v_is_subscriber     boolean;
  v_slot_type         text;
  v_ok                boolean := false;
  v_reason            text    := null;
  v_email             text    := lower(btrim(p_email));
begin
  -- Lock the techs row so parallel uploads can't both slip past the cap.
  select t.id,
         t.subscription_tier,
         t.subscription_expires_at,
         coalesce(t.photo_credits, 0),
         coalesce(t.period_upload_count, 0),
         t.period_reset_at,
         coalesce(t.lifetime_free_used, 0)
    into v_tech_id, v_tier, v_expires_at, v_credits, v_period_count, v_period_reset, v_free_used
    from public.techs t
    where (lower(t.email) = v_email
           or public.phone_digits(t.phone) = public.phone_digits(v_email))
    for update;

  if not found then
    return query select false, null::text, 'not_found'::text, 0, 0, null::timestamptz;
    return;
  end if;

  -- Resolve who this tech is and therefore which monthly cap applies.
  -- A tech_comps row overrides Stripe state entirely.
  select monthly_limit into v_comp_limit
    from public.tech_comps
   where email = v_email
   limit 1;

  if v_comp_limit is not null then
    v_is_subscriber := true;
    v_period_cap    := v_comp_limit;
  elsif (v_tier = 'paid') and (v_expires_at is null or v_expires_at > now()) then
    v_is_subscriber := true;
    v_period_cap    := v_glowup_cap;
  else
    -- The free tech. Not a trial, not a countdown -- this is permanent.
    v_is_subscriber := false;
    v_period_cap    := v_free_cap;
  end if;

  -- Lazy monthly reset, now for EVERYBODY rather than subscribers only.
  -- First upload ever (period_reset_at null) starts the first window.
  if v_period_reset is null or v_period_reset <= now() then
    v_period_count := 0;
    v_period_reset := now() + interval '1 month';
  end if;

  -- Slot sources, in order:
  --   1. this month's allowance (free or paid, same mechanic)
  --   2. photo credits, which let a tech burst PAST the monthly allowance
  if v_period_count < v_period_cap then
    v_period_count := v_period_count + 1;
    -- lifetime_free_used is now analytics only; it gates nothing.
    if not v_is_subscriber then
      v_free_used := v_free_used + 1;
    end if;
    update public.techs
       set period_upload_count = v_period_count,
           period_reset_at     = v_period_reset,
           lifetime_free_used  = v_free_used
     where id = v_tech_id;
    -- 'weekly' and 'free' are both feed-eligible on the client; 'credit'
    -- is portfolio-only. Keep the label matched to the tech's tier so
    -- existing client behaviour is unchanged.
    v_slot_type := case when v_is_subscriber then 'weekly' else 'free' end;
    v_ok := true;

  elsif v_credits > 0 then
    v_credits := v_credits - 1;
    update public.techs
       set photo_credits   = v_credits,
           period_reset_at = v_period_reset
     where id = v_tech_id;
    v_slot_type := 'credit';
    v_ok := true;

  else
    -- Monthly allowance spent. NOT a paywall: it refills on
    -- weekly_reset_at, which is returned below so the UI can say when.
    v_ok     := false;
    v_reason := 'monthly_cap';
  end if;

  return query select
    v_ok,
    v_slot_type,
    v_reason,
    greatest(0, v_period_cap - v_period_count),  -- now meaningful for free techs too
    v_credits,
    v_period_reset;                              -- always returned, so the UI can name the refill date
end;
$$;

comment on function public.consume_upload_slot(text) is
  'Atomic slot-consumption gate for portfolio uploads. 3.0 FREE model (2026-07-30 rev 3): photos are free forever with a monthly allowance that exists only to prevent abuse -- 50/month free, 150/month Glow Up, tech_comps.monthly_limit for comped techs. Free and paid techs share one period_upload_count/period_reset_at mechanic; only the cap differs. photo_credits still spend and can burst past the monthly allowance. lifetime_free_used is retained for analytics and no longer gates anything. No lifetime ceiling. Email match case-insensitive.';

grant execute on function public.consume_upload_slot(text) to authenticated;

-- ── One-time hygiene: clear stale period markers ────────────────────────
-- Free techs never used period_reset_at before, so any value sitting there
-- is meaningless. Nulling it makes the next upload open a clean window.
-- Safe: subscribers with a live window are left alone.
update public.techs
   set period_upload_count = 0,
       period_reset_at     = null
 where coalesce(subscription_tier, '') <> 'paid'
   and email not in (select email from public.tech_comps);

-- ── Sanity check after running ──────────────────────────────────────────
--
-- select t.email,
--        case when tc.email is not null then 'comped'
--             when t.subscription_tier = 'paid' then 'glow up'
--             else 'free' end                       as tier,
--        coalesce(t.period_upload_count, 0)         as used_this_month,
--        case when tc.email is not null then tc.monthly_limit
--             when t.subscription_tier = 'paid' then 150
--             else 50 end                           as monthly_cap,
--        t.period_reset_at                          as refills_at,
--        coalesce(t.photo_credits, 0)               as credits,
--        coalesce(t.lifetime_free_used, 0)          as lifetime_uploads
--   from public.techs t
--   left join public.tech_comps tc on tc.email = lower(btrim(t.email))
--  order by used_this_month desc;
