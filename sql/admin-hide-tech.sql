-- ============================================================================
-- admin-hide-tech.sql  (2026-11-24)
--
-- Powers the Hide / Unhide button beside Comp in admin-stats.html.
-- admin_set_tech_stealth(tech_id, on) flips techs.stealth (sql/stealth-profile.sql):
-- a hidden tech is out of the Gallery, Near Me, search, Open today counts,
-- share links and her public web page (techs_public leaves her out, and the
-- nightly page rebuild drops her page). She can still sign in and use her
-- Tech Portal, gallery, bookings and settings. Admins still see her here.
--
-- SECURITY DEFINER, gated on is_admin() like admin_set_tech_comp.
-- Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc,
-- "My Nail Connection 3"). Re-runnable.
-- ============================================================================

-- Make sure the column exists (no-op if sql/stealth-profile.sql already ran).
alter table public.techs add column if not exists stealth boolean not null default false;

create or replace function public.admin_set_tech_stealth(p_tech_id uuid, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_on boolean;
begin
  if not public.is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if not exists (select 1 from public.techs where id = p_tech_id) then
    raise exception 'Tech not found';
  end if;

  update public.techs set stealth = p_on where id = p_tech_id;
  select stealth into v_on from public.techs where id = p_tech_id;

  return jsonb_build_object('ok', true, 'tech_id', p_tech_id, 'stealth', v_on);
end;
$$;
revoke all on function public.admin_set_tech_stealth(uuid, boolean) from public, anon;
grant execute on function public.admin_set_tech_stealth(uuid, boolean) to authenticated;

-- ── Report (read only) ──────────────────────────────────────────────────────
-- view_hides_stealth must be true, or Hide does nothing on the client side
-- (then re-run sql/stealth-profile.sql). anne_hidden shows whether Anne's own
-- tech account is hidden right now (it showed in the public list on Nov 24).
select
  position('stealth' in pg_get_viewdef('public.techs_public'::regclass)) > 0 as view_hides_stealth,
  (select string_agg(name || ' = ' || stealth::text, ', ') from public.techs where name ilike 'anne wilson%') as anne_hidden,
  (select count(*) from public.techs where stealth) as hidden_count;
