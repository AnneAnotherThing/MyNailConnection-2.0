-- ========================================================================
-- First photo free (2026-07-20)
--
-- New model: a tech's FIRST photo is on us, every one after that is paid.
-- Anything a tech has ALREADY uploaded stays up for good (3.0 already never
-- removes photos, see the stripe-webhook "photos stay up" note), so a tech
-- with existing photos has already used their free one and pays for the next.
--
-- This is a drop-in replacement of the live consume_upload_slot (the version
-- from free-upload-counter-fix.sql, which drives lifetime_free_used). The
-- ONLY change is v_free_limit: 5 -> 1. Subscription and credit logic are
-- identical.
--
-- Pairs with the client change (STRIPE_CONFIG.free_limit = 1 and
-- NEW_TECH_FREE_PHOTOS = 1). Run this in the Supabase SQL editor. Idempotent.
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
  v_tech_id         uuid;
  v_tier            text;
  v_expires_at      timestamptz;
  v_credits         integer;
  v_period_count    integer;
  v_period_reset    timestamptz;
  v_free_used       integer;
  v_comp_limit      integer;     -- non-null when the email has a comp
  v_free_limit      integer := 1;   -- 1-free model (was 5): first photo on us, then paid. Existing photos stay.
  v_period_cap      integer;     -- resolved from tier or comp
  v_is_subscriber   boolean;
  v_slot_type       text;
  v_ok              boolean := false;
  v_reason          text    := 'capped';
  v_email           text    := lower(btrim(p_email));
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
    where lower(t.email) = v_email
    for update;

  if not found then
    return query select false, null::text, 'not_found'::text, 0, 0, null::timestamptz;
    return;
  end if;

  -- Comp check: a row in tech_comps overrides Stripe state. Comped techs
  -- are subscribers, period, with their own monthly_limit (default 25).
  select monthly_limit into v_comp_limit
    from public.tech_comps
   where email = v_email
   limit 1;

  if v_comp_limit is not null then
    v_is_subscriber := true;
    v_period_cap    := v_comp_limit;
  else
    v_is_subscriber := (v_tier = 'paid')
                       and (v_expires_at is null or v_expires_at > now());
    v_period_cap    := 25;
  end if;

  -- Lazy reset: month rolled over → zero the counter, advance the
  -- marker by another month. Same logic for both Stripe-paid and comped
  -- subscribers, they both use period_upload_count / period_reset_at.
  if v_is_subscriber and (v_period_reset is null or v_period_reset <= now()) then
    v_period_count := 0;
    v_period_reset := now() + interval '1 month';
  end if;

  -- Slot sources in order: subscription → credits → free (now zero).
  if v_is_subscriber and v_period_count < v_period_cap then
    v_period_count := v_period_count + 1;
    update public.techs
       set period_upload_count = v_period_count,
           period_reset_at     = v_period_reset
     where id = v_tech_id;
    v_slot_type := 'weekly';   -- wire-compat label; feed-eligible
    v_ok := true;
    v_reason := null;
  elsif v_credits > 0 then
    v_credits := v_credits - 1;
    update public.techs
       set photo_credits   = v_credits,
           period_reset_at = v_period_reset
     where id = v_tech_id;
    v_slot_type := 'credit';
    v_ok := true;
    v_reason := null;
  elsif (not v_is_subscriber) and v_free_used < v_free_limit then
    -- With v_free_limit = 1 this fires once (the free first photo), then not.
    v_free_used := v_free_used + 1;
    update public.techs
       set lifetime_free_used = v_free_used
     where id = v_tech_id;
    v_slot_type := 'free';
    v_ok := true;
    v_reason := null;
  else
    v_ok := false;
  end if;

  return query select
    v_ok,
    v_slot_type,
    v_reason,
    case when v_is_subscriber then greatest(0, v_period_cap - v_period_count) else 0 end,
    v_credits,
    case when v_is_subscriber then v_period_reset else null end;
end;
$$;

comment on function public.consume_upload_slot(text) is
  'Atomic slot-consumption gate for portfolio uploads. 1-free model (2026-07-20): non-subscribers get their FIRST photo free, then pay (v_free_limit = 1); already-uploaded photos are never removed. Comped techs (tech_comps) get monthly_limit/month. Stripe subscribers get their monthly cap while subscription_expires_at > now(). Then credits. Email match case-insensitive.';

grant execute on function public.consume_upload_slot(text) to authenticated;
