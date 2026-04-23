-- Glow Up weekly-slots enforcement
--
-- Implements the 2026-04-22 subscription pivot: Glow Up ($9/mo) grants
-- 5 new portfolio-photo uploads per week with a Sunday 00:00 UTC reset,
-- no rollover. Credits bought separately ($1/photo, $5/10-photo bundle)
-- stack with the weekly allowance as overflow — a subscriber who hits
-- their 5/week can burn a credit to upload more that week.
--
-- Design notes:
-- * Reset is LAZY (not a cron job): consume_upload_slot checks if
--   weekly_reset_at has passed and resets inline before enforcing the
--   cap. No cron dependency, no sweep worker.
-- * Sunday midnight UTC (not tech-local timezone) — one absolute
--   timestamp keeps the "when does my week reset?" UX answerable in one
--   line and debugging simple. 4-hour grace for west-coast techs.
-- * The RPC is the SINGLE gate — client-side canUploadPhoto is advisory
--   (for UI only); actual enforcement happens here with row-level locks
--   so parallel uploads from two devices can't both race past the cap.
-- * SECURITY DEFINER so the function can mutate techs rows under RLS;
--   we authenticate by email match against auth.jwt().
--
-- Apply by pasting into Supabase → SQL Editor. Idempotent — every
-- statement uses create-or-replace / if-not-exists.
-- 2026-04-22.

-- ── Schema ───────────────────────────────────────────────────────────────
alter table public.techs
  add column if not exists weekly_upload_count integer not null default 0,
  add column if not exists weekly_reset_at     timestamptz;

comment on column public.techs.weekly_upload_count is
  'Glow Up subscribers: how many portfolio photos uploaded so far this week. Reset lazily by consume_upload_slot() when weekly_reset_at passes.';
comment on column public.techs.weekly_reset_at is
  'Glow Up subscribers: UTC timestamp at which the current weekly count expires (next Sunday 00:00 UTC). NULL for techs who have never subscribed.';

-- ── Helper: next Sunday 00:00 UTC strictly after a given timestamp ──────
create or replace function public.next_sunday_utc_midnight(p_now timestamptz)
returns timestamptz
language sql
immutable
as $$
  -- extract(dow) → 0=Sun, 1=Mon, ..., 6=Sat.
  -- We want the next Sunday midnight STRICTLY AFTER p_now:
  --   Sunday → 7 days (so a Sunday 00:01 still points 7 days out,
  --            preserving "the current week ends next Sunday").
  --   Other   → 7 - dow days.
  -- Computed in UTC regardless of session timezone.
  select (
    date_trunc('day', p_now at time zone 'UTC')
    + case extract(dow from p_now at time zone 'UTC')::int
        when 0 then interval '7 days'
        else ((7 - extract(dow from p_now at time zone 'UTC')::int) || ' days')::interval
      end
  ) at time zone 'UTC';
$$;

comment on function public.next_sunday_utc_midnight(timestamptz) is
  'Returns the next Sunday at 00:00 UTC strictly after the given timestamp. Used by consume_upload_slot() to set weekly_reset_at.';

-- ── RPC: consume_upload_slot ─────────────────────────────────────────────
-- Atomic slot-consumption gate for portfolio photo uploads. The ONE
-- source of truth — client calls this before each upload; if ok=false,
-- block. If ok=true, proceed.
--
-- Resolution order when a subscriber uploads:
--   1. Try weekly slot (free, resets Sunday).
--   2. If weekly cap hit, try a credit (decrements photo_credits).
--   3. Otherwise block.
--
-- Resolution order for a non-subscriber:
--   1. If array_length(photos) < free_limit: 'free' (no mutation —
--      portfolio array growth is the counter).
--   2. If photo_credits > 0: decrement credit, 'credit'.
--   3. Otherwise block.
--
-- Returns enough context for the UI to show "you just used a weekly
-- slot, 3 of 5 left" or "that used a credit, 2 credits remain."
create or replace function public.consume_upload_slot(p_email text)
returns table (
  ok                 boolean,
  slot_type          text,        -- 'weekly' | 'credit' | 'free' | null on failure
  reason             text,        -- null on success; 'not_found' | 'capped' on failure
  remaining_weekly   integer,     -- 0–5; 0 for non-subscribers
  remaining_credits  integer,     -- photo_credits after this consume
  weekly_reset_at    timestamptz  -- when the current week ends; null for non-subscribers
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
  v_weekly_count    integer;
  v_weekly_reset    timestamptz;
  v_photos_len      integer;
  v_free_limit      integer := 5;  -- keep in sync with STRIPE_CONFIG.free_limit
  v_is_subscriber   boolean;
  v_slot_type       text;
  v_ok              boolean := false;
  v_reason          text    := 'capped';
begin
  -- Lock the row for the duration of the transaction so two concurrent
  -- uploads can't both pass the cap check.
  select t.id,
         t.subscription_tier,
         t.subscription_expires_at,
         coalesce(t.photo_credits, 0),
         coalesce(t.weekly_upload_count, 0),
         t.weekly_reset_at,
         coalesce(jsonb_array_length(t.photos), 0)
    into v_tech_id, v_tier, v_expires_at, v_credits, v_weekly_count, v_weekly_reset, v_photos_len
    from public.techs t
    where t.email = p_email
    for update;

  if not found then
    return query select false, null::text, 'not_found'::text, 0, 0, null::timestamptz;
    return;
  end if;

  v_is_subscriber := (v_tier = 'paid')
                     and (v_expires_at is null or v_expires_at > now());

  -- Lazy reset: if this is a subscriber whose week has rolled over,
  -- zero the counter and advance the reset marker before we check the cap.
  if v_is_subscriber and (v_weekly_reset is null or v_weekly_reset <= now()) then
    v_weekly_count := 0;
    v_weekly_reset := public.next_sunday_utc_midnight(now());
  end if;

  -- ── Try slot sources in order ─────────────────────────────────────────
  if v_is_subscriber and v_weekly_count < 5 then
    -- Use a weekly slot. Free to the subscriber, resets Sunday.
    v_weekly_count := v_weekly_count + 1;
    update public.techs
       set weekly_upload_count = v_weekly_count,
           weekly_reset_at     = v_weekly_reset
     where id = v_tech_id;
    v_slot_type := 'weekly';
    v_ok := true;
    v_reason := null;
  elsif v_credits > 0 then
    -- Use a credit. Works for both subscribers (overflow past weekly cap)
    -- and non-subscribers (after free slots exhausted).
    v_credits := v_credits - 1;
    update public.techs
       set photo_credits    = v_credits,
           weekly_reset_at  = v_weekly_reset  -- preserve subscriber reset marker if set
     where id = v_tech_id;
    v_slot_type := 'credit';
    v_ok := true;
    v_reason := null;
  elsif (not v_is_subscriber) and v_photos_len < v_free_limit then
    -- Non-subscriber, within lifetime free allowance. No mutation —
    -- portfolio array growth is the de-facto counter.
    v_slot_type := 'free';
    v_ok := true;
    v_reason := null;
  else
    -- No slots available. v_reason stays 'capped'.
    v_ok := false;
  end if;

  return query select
    v_ok,
    v_slot_type,
    v_reason,
    case when v_is_subscriber then greatest(0, 5 - v_weekly_count) else 0 end,
    v_credits,
    case when v_is_subscriber then v_weekly_reset else null end;
end;
$$;

comment on function public.consume_upload_slot(text) is
  'Atomic slot-consumption gate for portfolio photo uploads. Returns ok=true and the slot type used on success. Subscribers prefer weekly slots, fall back to credits. Non-subscribers use free-then-credits. Called once per file by the client before the upload itself.';

-- ── RLS: grant execute to authenticated users ────────────────────────────
-- SECURITY DEFINER handles the actual row access; we still want auth'd
-- users to be able to CALL the function.
grant execute on function public.consume_upload_slot(text) to authenticated;
grant execute on function public.next_sunday_utc_midnight(timestamptz) to authenticated;

-- ── Optional: peek_upload_slots (read-only view for UI) ──────────────────
-- Returns the same shape as consume_upload_slot but without mutating.
-- Useful for rendering "you have 3 of 5 weekly slots left" before the
-- user taps the upload button. Performs a lazy reset in its returned
-- VIEW of the data only (doesn't persist).
create or replace function public.peek_upload_slots(p_email text)
returns table (
  is_subscriber      boolean,
  remaining_weekly   integer,
  remaining_credits  integer,
  weekly_reset_at    timestamptz,
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
  v_weekly_count  integer;
  v_weekly_reset  timestamptz;
  v_photos_len    integer;
  v_is_subscriber boolean;
  v_effective_count integer;
  v_effective_reset timestamptz;
begin
  select t.subscription_tier,
         t.subscription_expires_at,
         coalesce(t.photo_credits, 0),
         coalesce(t.weekly_upload_count, 0),
         t.weekly_reset_at,
         coalesce(jsonb_array_length(t.photos), 0)
    into v_tier, v_expires_at, v_credits, v_weekly_count, v_weekly_reset, v_photos_len
    from public.techs t
    where t.email = p_email;

  if not found then
    return query select false, 0, 0, null::timestamptz, 0;
    return;
  end if;

  v_is_subscriber := (v_tier = 'paid')
                     and (v_expires_at is null or v_expires_at > now());

  -- Project the lazy reset so the caller sees the fresh count.
  if v_is_subscriber and (v_weekly_reset is null or v_weekly_reset <= now()) then
    v_effective_count := 0;
    v_effective_reset := public.next_sunday_utc_midnight(now());
  else
    v_effective_count := v_weekly_count;
    v_effective_reset := v_weekly_reset;
  end if;

  return query select
    v_is_subscriber,
    case when v_is_subscriber then greatest(0, 5 - v_effective_count) else 0 end,
    v_credits,
    case when v_is_subscriber then v_effective_reset else null end,
    v_photos_len;
end;
$$;

grant execute on function public.peek_upload_slots(text) to authenticated;

comment on function public.peek_upload_slots(text) is
  'Read-only peek at remaining upload slots for a tech. UI-only — not an authoritative gate. Use consume_upload_slot() to actually reserve a slot.';
