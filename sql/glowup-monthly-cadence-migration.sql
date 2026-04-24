-- Glow Up: weekly → monthly cadence migration
--
-- Supersedes glowup-weekly-slots-migration.sql (2026-04-22). The
-- subscription pivot is now:
--
--   * $10/mo Glow Up → 40 credits refilled monthly on the anniversary
--     of the last refill (rolling 30-day window, not a fixed calendar
--     day). No rollover — 40 fresh every refill.
--   * Subscriber + free-tier uploads hit the bulletin-board feed.
--     Pay-per-photo uploads (credits) stay portfolio-only — the
--     release wizard skips the board_posts insert when slot_type='credit'.
--   * $5 = 10-credit bundle as the standalone pay-per-photo price.
--   * Free: first 5 lifetime uploads still go to the feed as a new-tech
--     welcome boost — first impression of "being seen."
--
-- This migration renames the old `weekly_*` columns to `period_*` so the
-- schema reads honestly at the monthly cadence, updates the
-- consume_upload_slot + peek_upload_slots RPCs with the new cap (40) and
-- reset interval (+1 month), and migrates any existing subscribers onto
-- the new cadence (reset clock = now + 1 month, count = 0).
--
-- Idempotent — safe to re-run. Rename is no-op if already done.
-- Apply via Supabase SQL editor. 2026-04-23.

-- ── Rename columns: weekly_* → period_* ──────────────────────────────────
-- DO block so re-runs don't fail on "column already renamed."
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'techs'
       and column_name  = 'weekly_upload_count'
  ) then
    alter table public.techs rename column weekly_upload_count to period_upload_count;
  end if;
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'techs'
       and column_name  = 'weekly_reset_at'
  ) then
    alter table public.techs rename column weekly_reset_at to period_reset_at;
  end if;
end $$;

comment on column public.techs.period_upload_count is
  'Glow Up subscribers: how many portfolio photos uploaded so far in the current monthly billing window. Reset lazily by consume_upload_slot() when period_reset_at passes.';
comment on column public.techs.period_reset_at is
  'Glow Up subscribers: UTC timestamp at which the current monthly window ends (last refill + 1 month). NULL for techs who have never subscribed.';

-- ── Migrate existing subscribers onto the new cadence ────────────────────
-- Anyone currently subscribed gets zero'd out and moved to the new
-- 1-month rolling window starting now. Pre-launch scale so this is a
-- handful of rows; not worth a data-preserving dance.
update public.techs
   set period_upload_count = 0,
       period_reset_at     = now() + interval '1 month'
 where subscription_tier = 'paid'
   and (subscription_expires_at is null or subscription_expires_at > now());

-- ── RPC: consume_upload_slot ─────────────────────────────────────────────
-- Replaces the 2026-04-22 version. Cap is 40 (was 5). Reset interval is
-- '+1 month from now' (was 'next Sunday 00:00 UTC'). Slot-type return
-- values unchanged: 'weekly' | 'credit' | 'free' so the existing client
-- code can keep using slot_type to decide feed eligibility.
--
-- NB: we keep 'weekly' as the slot_type label even though the cadence
-- is monthly — renaming that enum-like value requires a lockstep client
-- deploy, and the label is internal anyway. "Subscription slot" is what
-- it really means. If later cleanup matters, swap it in a follow-up.
create or replace function public.consume_upload_slot(p_email text)
returns table (
  ok                 boolean,
  slot_type          text,
  reason             text,
  remaining_weekly   integer,     -- kept name for wire-compat; now reflects monthly remaining
  remaining_credits  integer,
  weekly_reset_at    timestamptz  -- kept name for wire-compat; now the monthly refill timestamp
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
  v_photos_len      integer;
  v_free_limit      integer := 5;   -- lifetime free uploads; keep in sync with STRIPE_CONFIG.free_limit
  v_period_cap      integer := 40;  -- monthly subscription cap; keep in sync with STRIPE_CONFIG.monthly_limit
  v_is_subscriber   boolean;
  v_slot_type       text;
  v_ok              boolean := false;
  v_reason          text    := 'capped';
begin
  -- Lock the row so parallel uploads can't both slip past the cap.
  select t.id,
         t.subscription_tier,
         t.subscription_expires_at,
         coalesce(t.photo_credits, 0),
         coalesce(t.period_upload_count, 0),
         t.period_reset_at,
         coalesce(jsonb_array_length(t.photos), 0)
    into v_tech_id, v_tier, v_expires_at, v_credits, v_period_count, v_period_reset, v_photos_len
    from public.techs t
    where t.email = p_email
    for update;

  if not found then
    return query select false, null::text, 'not_found'::text, 0, 0, null::timestamptz;
    return;
  end if;

  v_is_subscriber := (v_tier = 'paid')
                     and (v_expires_at is null or v_expires_at > now());

  -- Lazy reset: month rolled over → zero the counter, advance the
  -- marker by another month from now.
  if v_is_subscriber and (v_period_reset is null or v_period_reset <= now()) then
    v_period_count := 0;
    v_period_reset := now() + interval '1 month';
  end if;

  -- Try slot sources in order.
  if v_is_subscriber and v_period_count < v_period_cap then
    v_period_count := v_period_count + 1;
    update public.techs
       set period_upload_count = v_period_count,
           period_reset_at     = v_period_reset
     where id = v_tech_id;
    v_slot_type := 'weekly';  -- wire-compat label (see comment above)
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
  elsif (not v_is_subscriber) and v_photos_len < v_free_limit then
    -- First N lifetime uploads for a non-subscriber. Portfolio growth is
    -- the de-facto counter; no column mutation needed.
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
  'Atomic slot-consumption gate for portfolio uploads. Subscribers: 40 monthly + credits overflow. Non-subscribers: 5 lifetime free then credits. Returns slot_type so the client can decide feed eligibility (weekly/free → feed; credit → portfolio-only).';

grant execute on function public.consume_upload_slot(text) to authenticated;

-- ── RPC: peek_upload_slots (read-only UI helper) ─────────────────────────
create or replace function public.peek_upload_slots(p_email text)
returns table (
  is_subscriber      boolean,
  remaining_weekly   integer,     -- wire-compat: now monthly remaining
  remaining_credits  integer,
  weekly_reset_at    timestamptz, -- wire-compat: now monthly refill timestamp
  photos_count       integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier          text;
  v_expires_at    timestamptz;
  v_credits       integer;
  v_period_count  integer;
  v_period_reset  timestamptz;
  v_photos_len    integer;
  v_is_subscriber boolean;
  v_effective_count integer;
  v_effective_reset timestamptz;
  v_period_cap    integer := 40;
begin
  select t.subscription_tier,
         t.subscription_expires_at,
         coalesce(t.photo_credits, 0),
         coalesce(t.period_upload_count, 0),
         t.period_reset_at,
         coalesce(jsonb_array_length(t.photos), 0)
    into v_tier, v_expires_at, v_credits, v_period_count, v_period_reset, v_photos_len
    from public.techs t
    where t.email = p_email;

  if not found then
    return query select false, 0, 0, null::timestamptz, 0;
    return;
  end if;

  v_is_subscriber := (v_tier = 'paid')
                     and (v_expires_at is null or v_expires_at > now());

  if v_is_subscriber and (v_period_reset is null or v_period_reset <= now()) then
    v_effective_count := 0;
    v_effective_reset := now() + interval '1 month';
  else
    v_effective_count := v_period_count;
    v_effective_reset := v_period_reset;
  end if;

  return query select
    v_is_subscriber,
    case when v_is_subscriber then greatest(0, v_period_cap - v_effective_count) else 0 end,
    v_credits,
    case when v_is_subscriber then v_effective_reset else null end,
    v_photos_len;
end;
$$;

grant execute on function public.peek_upload_slots(text) to authenticated;

comment on function public.peek_upload_slots(text) is
  'Read-only peek at remaining upload slots. UI-only — not an authoritative gate. Use consume_upload_slot() to actually reserve.';

-- ── next_sunday_utc_midnight is no longer called anywhere ────────────────
-- Kept in place (not dropped) so any third-party SQL still referencing
-- it keeps resolving. Safe to drop in a follow-up cleanup.

-- End of migration.
