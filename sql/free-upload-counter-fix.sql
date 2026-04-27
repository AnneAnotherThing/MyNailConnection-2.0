-- ========================================================================
-- MNC Paywall Hardening + Comps System  (2026-04-27)
-- ========================================================================
-- Two related fixes bundled into one migration because Anne hasn't run
-- the originally-separate "free counter" migration yet, and the comps
-- table needs to be checked inside the same RPC. Single CREATE OR REPLACE
-- on consume_upload_slot is cleaner than two sequential ones.
--
-- ── Part 1 — Free-upload counter ────────────────────────────────────────
-- The old free-tier branch of consume_upload_slot used
-- jsonb_array_length(techs.photos) as its counter:
--
--     elsif (not v_is_subscriber) and v_photos_len < v_free_limit then
--         -- "Portfolio growth is the de-facto counter"
--         v_slot_type := 'free'; v_ok := true;
--
-- That assumes photos hit techs.photos immediately. They don't — the
-- tech-edit screen accumulates uploads in a local edit buffer and only
-- writes to techs.photos on Save. Within a single edit session a tech
-- could blast past the 5-free cap because the counter never advanced.
--
-- Fix: real `lifetime_free_used` integer column on techs. RPC mutates it
-- on every free grant. Atomic, mid-session correct.
--
-- ── Part 2 — Comps system ───────────────────────────────────────────────
-- A separate `public.tech_comps` table is the source of truth for who
-- gets a permanent comp (free Glow Up, no Stripe sub). Anne can manage
-- this table independently of public.techs — add/remove rows whenever,
-- without re-running migrations. The RPC checks tech_comps FIRST, before
-- the Stripe-based subscription logic, so a comped tech is a subscriber
-- regardless of what subscription_tier or subscription_expires_at say
-- on the techs row. Webhooks can't accidentally downgrade them.
--
-- Why a table beats a column flag:
--   • Decoupled from Stripe state. Stripe webhook events key off
--     stripe_customer_id; comped techs have none, so no event can touch
--     them. With a flag column on techs, a stray subscription.deleted
--     for an unrelated reason could clobber the comp.
--   • Auditable. granted_at + granted_by + note record why each comp
--     exists. Useful for the founders cohort and any future grants.
--   • Per-person customization without schema changes. monthly_limit
--     defaults to 40 but Anne can set 20 for one person, 80 for another.
--
-- ── Part 3 — Email casing in the RPC ───────────────────────────────────
-- The previous RPC used `where t.email = p_email` (case-sensitive). Most
-- callers pass auth-lowercased emails, but it's a footgun. Now does
-- `where lower(t.email) = lower(btrim(p_email))` everywhere.
--
-- Safe to re-run. Block 1 ALTER and Block 2 CREATE TABLE use IF NOT
-- EXISTS / IF NOT EXISTS. Block 4-5 use CREATE OR REPLACE.
-- ========================================================================


-- ========================================================================
-- BLOCK 1 — Add lifetime_free_used counter to techs
-- ========================================================================

alter table public.techs
  add column if not exists lifetime_free_used integer not null default 0;

comment on column public.techs.lifetime_free_used is
  'Non-subscriber free uploads consumed in the lifetime of this tech account. Incremented by consume_upload_slot() in the free branch. Capped at STRIPE_CONFIG.free_limit (5) on the gating side. Decoupled from the photos array so unsaved edit buffers cannot mask the count. 2026-04-27.';

-- Backfill from existing photos (best-effort; older rows lacked slot_type
-- so we treat null as free).
update public.techs t
   set lifetime_free_used = least(
     coalesce((
       select count(*)::int
         from jsonb_array_elements(t.photos) p
        where (p->>'slot_type') is null
           or (p->>'slot_type') = 'free'
     ), 0),
     5
   );


-- ========================================================================
-- BLOCK 2 — Create the comps table
-- ========================================================================

create table if not exists public.tech_comps (
  email          text primary key
                   check (email = lower(btrim(email))),
  granted_at     timestamptz not null default now(),
  granted_by     text,
  note           text,
  monthly_limit  integer not null default 40
                   check (monthly_limit > 0 and monthly_limit <= 1000)
);

comment on table public.tech_comps is
  'Permanent free-Glow-Up grants. A row here means the email gets subscriber treatment from consume_upload_slot regardless of the techs.subscription_tier value. Decoupled from Stripe — webhook events cannot affect rows here. Email is enforced lowercase by CHECK constraint so case-insensitive lookups always match.';
comment on column public.tech_comps.note is
  'Free-text reason for the grant (e.g. "MNC 1.0 founder", "Beta tester", "Personal grant from Anne"). Audit trail.';
comment on column public.tech_comps.monthly_limit is
  'Override for the standard 40/month allowance. Lets Anne grant smaller (e.g. 20/mo trial) or larger comps without schema changes.';

-- RLS — admin can read/write all rows; the owner can read their own
-- (so the client UI can detect comp status and tailor copy). Browse
-- lists / cards do NOT need to read this table directly — the trigger
-- below syncs subscription_tier onto techs, so the standard
-- 'tier === paid' check already lights up comped techs in lists.
alter table public.tech_comps enable row level security;

drop policy if exists tech_comps_owner_read on public.tech_comps;
create policy tech_comps_owner_read on public.tech_comps
  for select to authenticated
  using (lower(email) = lower((auth.jwt() ->> 'email')::text));

drop policy if exists tech_comps_admin_all on public.tech_comps;
create policy tech_comps_admin_all on public.tech_comps
  for all to authenticated
  using (
    exists (
      select 1 from public.users u
       where lower(u.email) = lower((auth.jwt() ->> 'email')::text)
         and u.role = 'admin'
    )
  );

-- Sync trigger: tech_comps is the source of truth; the trigger keeps
-- public.techs in lockstep so the rest of the app (browse cards, tech
-- profile header, upgrade-modal eyebrow, etc.) can keep using the
-- existing `subscription_tier === 'paid'` check without learning about
-- the new table. Comped techs end up looking identical to Stripe
-- subscribers in the UI (which is the goal — they ARE Glow Up members).
--
-- Webhook safety: the deleted/updated subscription webhooks key off
-- stripe_customer_id. Comped techs have stripe_customer_id = null, so
-- those webhook handlers won't touch their row. The trigger only flips
-- subscription_tier back to 'free' on comp DELETE if there's no Stripe
-- sub backing the row.

create or replace function public.sync_tech_comp_to_techs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.techs
       set subscription_tier       = 'paid',
           subscription_expires_at = null,
           period_upload_count     = coalesce(period_upload_count, 0),
           period_reset_at         = coalesce(period_reset_at, now() + interval '1 month')
     where lower(email) = lower(new.email);
    return new;
  elsif tg_op = 'DELETE' then
    -- Revert to 'free' only if no Stripe subscription is backing the
    -- row. If a Stripe sub IS active, leave the tier alone — the webhook
    -- is the authority for that lifecycle.
    update public.techs
       set subscription_tier       = 'free',
           subscription_expires_at = null
     where lower(email) = lower(old.email)
       and stripe_customer_id is null;
    return old;
  elsif tg_op = 'UPDATE' then
    -- Only matters if email changed (rare). Re-apply on the new email.
    if lower(new.email) <> lower(old.email) then
      update public.techs
         set subscription_tier       = 'paid',
             subscription_expires_at = null
       where lower(email) = lower(new.email);
    end if;
    return new;
  end if;
  return null;
end;
$$;

drop trigger if exists sync_tech_comp_to_techs_trg on public.tech_comps;
create trigger sync_tech_comp_to_techs_trg
  after insert or update or delete on public.tech_comps
  for each row
  execute function public.sync_tech_comp_to_techs();

-- Backfill: if any tech_comps rows already exist, fire the sync once
-- to bring techs into line. Idempotent.
update public.techs t
   set subscription_tier       = 'paid',
       subscription_expires_at = null,
       period_upload_count     = coalesce(t.period_upload_count, 0),
       period_reset_at         = coalesce(t.period_reset_at, now() + interval '1 month')
 where exists (
   select 1 from public.tech_comps c where c.email = lower(t.email)
 );


-- Reverse trigger: when a public.techs row is created for an email that
-- already has a comp on file, auto-apply the paid tier. This is what
-- makes archived-tech re-onboarding work — Anne adds an archived email
-- to tech_comps NOW, the person eventually re-signs-up via the regular
-- signup flow, and the moment their techs row lands, this trigger marks
-- them paid. No manual reconciliation pass required. 2026-04-27.

create or replace function public.apply_pending_comp_on_tech_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.tech_comps c where c.email = lower(new.email)) then
    new.subscription_tier       := 'paid';
    new.subscription_expires_at := null;
    new.period_upload_count     := coalesce(new.period_upload_count, 0);
    new.period_reset_at         := coalesce(new.period_reset_at, now() + interval '1 month');
  end if;
  return new;
end;
$$;

drop trigger if exists apply_pending_comp_on_tech_insert_trg on public.techs;
create trigger apply_pending_comp_on_tech_insert_trg
  before insert on public.techs
  for each row
  execute function public.apply_pending_comp_on_tech_insert();


-- ========================================================================
-- BLOCK 3 — Patched consume_upload_slot
-- Comp check first, then standard tier logic. lifetime_free_used drives
-- the free branch. Email match case-insensitive.
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
  v_free_limit      integer := 5;
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
  -- are subscribers, period, with their own monthly_limit (default 40).
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
    v_period_cap    := 40;
  end if;

  -- Lazy reset: month rolled over → zero the counter, advance the
  -- marker by another month. Same logic for both Stripe-paid and comped
  -- subscribers — they both use period_upload_count / period_reset_at.
  if v_is_subscriber and (v_period_reset is null or v_period_reset <= now()) then
    v_period_count := 0;
    v_period_reset := now() + interval '1 month';
  end if;

  -- Slot sources in order: subscription → credits → free.
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
    -- Real counter on a real column.
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
  'Atomic slot-consumption gate for portfolio uploads. Comped techs (in tech_comps) get monthly_limit/month uploads, no expiry. Stripe subscribers get 40/month while subscription_expires_at > now(). Non-subscribers get 5 lifetime free, then credits. Returns slot_type so the client decides feed eligibility (weekly/free → feed; credit → portfolio-only). Email match case-insensitive.';

grant execute on function public.consume_upload_slot(text) to authenticated;


-- ========================================================================
-- BLOCK 4 — Patched peek_upload_slots (read-only sibling)
-- ========================================================================
-- The existing function's return columns differ (added `tier` +
-- `is_subscriber`), so Postgres requires an explicit DROP — CREATE OR
-- REPLACE alone errors with "cannot change return type of existing
-- function." Drop is idempotent thanks to IF EXISTS.

drop function if exists public.peek_upload_slots(text);

create or replace function public.peek_upload_slots(p_email text)
returns table (
  tier               text,
  is_subscriber      boolean,
  remaining_weekly   integer,
  remaining_credits  integer,
  free_remaining     integer,
  period_reset_at    timestamptz
)
language sql
security definer
set search_path = public
as $$
  with t as (
    select tt.subscription_tier,
           tt.subscription_expires_at,
           coalesce(tt.photo_credits, 0)         as credits,
           coalesce(tt.period_upload_count, 0)   as period_count,
           tt.period_reset_at                    as period_reset,
           coalesce(tt.lifetime_free_used, 0)    as free_used
      from public.techs tt
     where lower(tt.email) = lower(btrim(p_email))
     limit 1
  ),
  c as (
    select monthly_limit
      from public.tech_comps
     where email = lower(btrim(p_email))
     limit 1
  ),
  resolved as (
    select
      coalesce(t.subscription_tier, 'free')                                      as raw_tier,
      (c.monthly_limit is not null)
        or (t.subscription_tier = 'paid' and (t.subscription_expires_at is null or t.subscription_expires_at > now()))
        as is_sub,
      coalesce(c.monthly_limit, 40)                                              as cap,
      t.credits, t.period_count, t.period_reset, t.free_used
    from t left join c on true
  )
  select
    raw_tier,
    is_sub,
    case when is_sub then greatest(0, cap - period_count) else 0 end,
    credits,
    case when is_sub then 0 else greatest(0, 5 - free_used) end,
    case when is_sub then period_reset else null end
  from resolved;
$$;

grant execute on function public.peek_upload_slots(text) to anon, authenticated;


-- ========================================================================
-- Sanity checks (run after migration; both should be readable)
-- ========================================================================
-- select email, lifetime_free_used, photo_credits, subscription_tier
--   from public.techs order by created_at desc limit 10;
-- select * from public.tech_comps order by granted_at desc;
