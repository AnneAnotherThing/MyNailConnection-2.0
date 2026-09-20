-- ============================================================================
-- admin-panel-migration.sql  (2026-09-20)
--
-- Powers the new admin panel in admin-stats.html:
--   1. admin_set_tech_comp(tech_id, on) -- comp / un-comp a tech BY ID, so it
--      works for phone-only techs (the tech_comps table is email-keyed and
--      most techs now have no email). Sets the comp straight on the techs row.
--   2. admin_booking_stats() -- appointment activity counts for the dashboard.
--
-- Both are SECURITY DEFINER and gated on is_admin() (phone-aware since
-- sql/sweep-fixes-2026-09-04.sql), so a phone-admin session works.
--
-- Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc). Re-runnable.
-- ============================================================================

-- ── 1. Comp / un-comp a tech by id ──────────────────────────────────────────
-- Comp on:  full paid access, no expiry, source 'comp'. Un-comp: back to free,
-- but ONLY if they were comped -- never touches a real paid/trial sub.
-- Writes straight to the techs row (not the email-keyed tech_comps table), so
-- phone-only techs can be comped. The grant_booking_trial trigger doesn't fire
-- here (booking_enabled is unchanged).
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
           period_reset_at          = coalesce(period_reset_at, now() + interval '1 month')
     where id = p_tech_id;
  else
    update public.techs
       set subscription_tier       = 'free',
           subscription_source     = null,
           subscription_expires_at  = null
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

-- ── 2. Appointment activity counts ──────────────────────────────────────────
create or replace function public.admin_booking_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'total',              (select count(*) from public.bookings),
    'this_week',          (select count(*) from public.bookings where created_at > now() - interval '7 days'),
    'upcoming',           (select count(*) from public.bookings
                             where status in ('pending','confirmed') and starts_at > now()),
    'confirmed_upcoming', (select count(*) from public.bookings
                             where status = 'confirmed' and starts_at > now()),
    'pending',            (select count(*) from public.bookings
                             where status = 'pending' and starts_at > now()),
    'next_7_days',        (select count(*) from public.bookings
                             where status in ('pending','confirmed')
                               and starts_at between now() and now() + interval '7 days'),
    'completed',          (select count(*) from public.bookings where status = 'completed'),
    'no_show',            (select count(*) from public.bookings where status = 'no_show'),
    'cancelled',          (select count(*) from public.bookings
                             where status in ('cancelled_by_client','cancelled_by_tech')),
    'active_booking_techs', (select count(distinct tech_id) from public.bookings
                               where starts_at > now() - interval '60 days')
  );
end;
$$;
revoke all on function public.admin_booking_stats() from public, anon;
grant execute on function public.admin_booking_stats() to authenticated;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--   select public.admin_booking_stats();                        -- as an admin
--   select public.admin_set_tech_comp('<tech-uuid>', true);     -- comp on
--   select public.admin_set_tech_comp('<tech-uuid>', false);    -- comp off
