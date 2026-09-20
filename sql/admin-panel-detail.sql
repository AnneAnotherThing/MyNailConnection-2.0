-- ============================================================================
-- admin-panel-detail.sql  (2026-09-20)
--
-- Lets the admin page EXPAND the appointment numbers to the real rows, so
-- Anne can see whether they're legit bookings or leftover test data.
-- Additive to sql/admin-panel-migration.sql.
--
-- admin_recent_bookings(limit): the most recent bookings with tech + service
-- + client names resolved, gated on is_admin(). Non-admins get zero rows
-- (the is_admin() filter), never an error.
--
-- Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc). Re-runnable.
-- ============================================================================

create or replace function public.admin_recent_bookings(p_limit int default 40)
returns table (
  id            uuid,
  starts_at     timestamptz,
  status        text,
  created_at    timestamptz,
  tech_name     text,
  client_name   text,
  client_email  text,
  service_name  text
)
language sql
stable
security definer
set search_path = public
as $$
  select b.id,
         b.starts_at,
         b.status,
         b.created_at,
         coalesce(t.name, 'Unknown tech')      as tech_name,
         coalesce(b.client_name, '')            as client_name,
         coalesce(b.client_email, '')           as client_email,
         coalesce(s.name, 'Appointment')        as service_name
    from public.bookings b
    left join public.techs t         on t.id = b.tech_id
    left join public.tech_services s on s.id = b.service_id
   where public.is_admin()
   order by b.created_at desc
   limit least(coalesce(p_limit, 40), 200);
$$;
revoke all on function public.admin_recent_bookings(int) from public, anon;
grant execute on function public.admin_recent_bookings(int) to authenticated;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--   select * from public.admin_recent_bookings(20);   -- as an admin
