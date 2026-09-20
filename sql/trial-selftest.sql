-- ============================================================================
-- trial-selftest.sql  (2026-09-20)
--
-- Proves the "free month starts when booking is turned on" chain end to end,
-- server-side, WITHOUT touching a real tech and WITHOUT needing an app build.
--
-- It builds a throwaway tech (cloned from a real row so every NOT NULL column
-- is satisfied), then:
--   1. confirms a fresh tech pays nothing  (tier free, no trial, not bookable)
--   2. turns booking ON  -> grant_booking_trial should stamp the 30-day window
--   3. confirms she is now bookable (tech_is_bookable = true)
--   4. toggles booking OFF then ON again -> the trial must NOT move or extend
--   5. simulates the 30 days lapsing -> she goes un-bookable (paywall returns)
-- then DELETES the throwaway tech. Nothing persists. If any step raises, the
-- whole function rolls back and the temp row is gone too.
--
-- Run AFTER sql/tech-booking-trial-migration.sql. Paste the whole thing into
-- the Supabase SQL editor (project nwqnakoongrorbwnrqzc) and read the result
-- grid top to bottom. Every 'expect' should match 'got'.
-- ============================================================================

create or replace function public._trial_selftest()
returns table (step text, detail text)
language plpgsql
as $$
declare
  v_id   uuid := gen_random_uuid();
  v_tmpl public.techs%rowtype;
  v_paywall boolean := public.paywall_enabled();
begin
  -- Clone any real row so all required columns are populated, then reset the
  -- fields that define a brand-new free tech.
  select * into v_tmpl from public.techs limit 1;
  if v_tmpl.id is null then
    return query select 'ABORT', 'No techs exist to clone a template from'; return;
  end if;
  v_tmpl.id                     := v_id;
  v_tmpl.name                   := 'ZZ trial selftest (auto-deletes)';
  v_tmpl.phone                  := '+15550000199';
  v_tmpl.email                  := null;
  v_tmpl.paused_by_tech         := false;   -- visible
  v_tmpl.founder_free           := false;   -- not grandfathered
  v_tmpl.booking_enabled        := false;   -- booking OFF at signup
  v_tmpl.subscription_tier      := 'free';
  v_tmpl.subscription_source    := null;
  v_tmpl.subscription_expires_at:= null;
  v_tmpl.trial_started_at       := null;
  v_tmpl.period_reset_at        := null;
  insert into public.techs select v_tmpl.*;

  return query select 'paywall_enabled()', v_paywall::text;

  -- 1. Fresh tech, booking off: free, no trial, not bookable.
  return query
    select '1. fresh tech (booking off)',
           format('tier=%s src=%s trial_started=%s bookable=%s  [expect: free / <null> / <null> / false]',
                  t.subscription_tier, coalesce(t.subscription_source,'<null>'),
                  coalesce(t.trial_started_at::text,'<null>'),
                  public.tech_is_bookable(t.id))
      from public.techs t where t.id = v_id;

  -- 2. Turn booking ON (exactly what the app writes). Trigger should fire.
  update public.techs set booking_enabled = true where id = v_id;
  return query
    select '2. booking turned ON',
           format('tier=%s src=%s trial_started=%s reset=%s  [expect: paid / trial / now / now+30d]',
                  t.subscription_tier, coalesce(t.subscription_source,'<null>'),
                  coalesce(t.trial_started_at::text,'<null>'),
                  coalesce(t.period_reset_at::text,'<null>'))
      from public.techs t where t.id = v_id;

  -- 3. She is now bookable for free.
  return query
    select '3. now bookable (free month live)',
           format('bookable=%s  [expect: true%s]',
                  public.tech_is_bookable(v_id),
                  case when not v_paywall then '  (paywall OFF, so this is true regardless)' else '' end);

  -- 4. Toggle OFF then ON again: trial must not move or re-grant.
  update public.techs set booking_enabled = false where id = v_id;
  update public.techs set booking_enabled = true  where id = v_id;
  return query
    select '4. off/on again (no re-grant)',
           format('trial_started=%s reset=%s  [expect: SAME instant as step 2, not moved]',
                  coalesce((select trial_started_at::text from public.techs where id = v_id),'<null>'),
                  coalesce((select period_reset_at::text  from public.techs where id = v_id),'<null>'));

  -- 5. Simulate the 30 days lapsing (past the 3-day renewal grace).
  update public.techs
     set subscription_expires_at = now() - interval '4 days',
         period_reset_at         = now() - interval '4 days'
   where id = v_id;
  return query
    select '5. trial lapsed (30d past)',
           format('bookable=%s  [expect: false%s -> paywall returns]',
                  public.tech_is_bookable(v_id),
                  case when not v_paywall then '  BUT paywall is OFF so this stays true' else '' end);

  -- Clean up: remove the throwaway tech. Net effect on prod is zero rows.
  delete from public.techs where id = v_id;
  return query select 'DONE', 'Throwaway tech deleted. Prod untouched.';
end;
$$;

select * from public._trial_selftest();

drop function public._trial_selftest();
