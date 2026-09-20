-- ============================================================================
-- comp-permanent-fix.sql  (2026-09-20)
--
-- A comp is supposed to mean "full access, never pays, never lapses." It did
-- not. Bookability is tech_bookable_calc = visible AND tier='paid' AND
-- period_reset_at > now() - 3 days (the 3-day renewal grace). All three comp
-- paths stamped period_reset_at only one MONTH out:
--   1. admin_set_tech_comp()            -- the admin panel button
--   2. sync_tech_comp_to_techs()        -- INSERT on the email-keyed tech_comps
--   3. apply_pending_comp_on_tech_insert() -- a comped email that later signs up
-- Nothing rolls period_reset_at forward for a comp (no webhook, no renewal), so
-- roughly a month after being comped a tech silently falls off her own listing
-- while still marked paid and owing nothing.
--
-- Fix: comps stamp period_reset_at far in the future (now + 100 years, the same
-- sentinel tech_bookable_calc already uses for a null reset). That keeps a comp
-- bookable forever and is NOT re-stamped by the lazy upload reset, which only
-- fires when period_reset_at is null or already past. subscription_expires_at
-- stays null, so nothing expires. Everything else in each function is unchanged.
--
-- Then backfill every current comp (source='comp' OR present in tech_comps).
--
-- NOTE: does NOT fix Leslie. She is a real RevenueCat subscriber whose row was
-- mis-stamped by the webhook (punchlist c-rcreset), a separate bug with its own
-- fix. This file only makes COMPS permanent.
-- NOTE: if sql/tech-billing-split.sql is ever run, it recreates
-- sync_tech_comp_to_techs; re-run this file afterward so the far-future stamp
-- survives.
--
-- Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc). Re-runnable.
-- ============================================================================

-- ── 1. Admin panel: comp / un-comp a tech by id ─────────────────────────────
create or replace function public.admin_set_tech_comp(p_tech_id uuid, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier text;
  v_src  text;
begin
  if not public.is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if not exists (select 1 from public.techs where id = p_tech_id) then
    raise exception 'Tech not found';
  end if;

  if p_on then
    update public.techs
       set subscription_tier       = 'paid',
           subscription_source     = 'comp',
           subscription_expires_at  = null,
           period_upload_count      = coalesce(period_upload_count, 0),
           period_reset_at          = now() + interval '100 years'
     where id = p_tech_id;
  else
    update public.techs
       set subscription_tier       = 'free',
           subscription_source     = null,
           subscription_expires_at  = null,
           period_reset_at          = null
     where id = p_tech_id
       and coalesce(subscription_source, '') = 'comp';
  end if;

  select subscription_tier, subscription_source
    into v_tier, v_src
    from public.techs where id = p_tech_id;

  return jsonb_build_object('ok', true, 'tech_id', p_tech_id, 'tier', v_tier, 'source', v_src);
end;
$$;
revoke all on function public.admin_set_tech_comp(uuid, boolean) from public, anon;
grant execute on function public.admin_set_tech_comp(uuid, boolean) to authenticated;

-- ── 2. Email-keyed comp table -> techs (INSERT / DELETE / UPDATE) ────────────
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
           period_reset_at         = now() + interval '100 years'
     where lower(email) = lower(new.email);
    return new;
  elsif tg_op = 'DELETE' then
    -- Revert to free only if no Stripe subscription is backing the row.
    update public.techs
       set subscription_tier       = 'free',
           subscription_expires_at = null
     where lower(email) = lower(old.email)
       and stripe_customer_id is null;
    return old;
  elsif tg_op = 'UPDATE' then
    if lower(new.email) <> lower(old.email) then
      update public.techs
         set subscription_tier       = 'paid',
             subscription_expires_at = null,
             period_reset_at         = now() + interval '100 years'
       where lower(email) = lower(new.email);
    end if;
    return new;
  end if;
  return null;
end;
$$;

-- ── 3. A comped email that later signs up (BEFORE INSERT on techs) ───────────
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
    new.period_reset_at         := now() + interval '100 years';
  end if;
  return new;
end;
$$;

-- ── 4. Backfill every current comp so the live ones stop lapsing ─────────────
update public.techs t
   set period_reset_at         = now() + interval '100 years',
       subscription_expires_at = null,
       subscription_tier       = 'paid'
 where coalesce(t.subscription_source, '') = 'comp'
    or exists (select 1 from public.tech_comps c where c.email = lower(t.email));

-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- Every comp should now read bookable, with a period_reset_at ~100 years out.
--   select name, email, subscription_tier, subscription_source,
--          period_reset_at, public.tech_is_bookable(id) as bookable
--     from public.techs
--    where coalesce(subscription_source,'') = 'comp'
--       or exists (select 1 from public.tech_comps c where c.email = lower(techs.email));
