-- ============================================================================
-- PHONE-AUTH STAGE B: booking-table RLS accepts phone identity  (2026-07-24)
-- ============================================================================
-- Stage A gave users / techs / board_posts / push_subscriptions dual-identity
-- policies (email OR phone), but every BOOKING table was missed. Their
-- ownership test is still:
--
--     tech_id in (select id from techs where lower(email) = current_email())
--
-- For a phone-identity tech current_email() is null, the subquery matches
-- nothing, and any insert/update fails with
-- "new row violates row-level security policy" (Anne hit this adding a
-- service in Set Up Free Booking, 2026-07-24). Every policy below gets the
-- same email-OR-phone test Stage A established. Client legs (client_id =
-- auth.uid()) and admin legs are preserved unchanged.
--
-- Requires Stage A (public.current_phone / public.phone_digits).
-- Runs in the Supabase SQL editor. Safe to re-run.
-- ============================================================================

begin;

-- ── tech_services ───────────────────────────────────────────────────────────
drop policy if exists svc_insert_self on public.tech_services;
create policy svc_insert_self on public.tech_services
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists svc_update_self on public.tech_services;
create policy svc_update_self on public.tech_services
  for update to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  )
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists svc_delete_self on public.tech_services;
create policy svc_delete_self on public.tech_services
  for delete to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

-- ── tech_availability ───────────────────────────────────────────────────────
drop policy if exists avail_insert_self on public.tech_availability;
create policy avail_insert_self on public.tech_availability
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists avail_update_self on public.tech_availability;
create policy avail_update_self on public.tech_availability
  for update to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  )
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists avail_delete_self on public.tech_availability;
create policy avail_delete_self on public.tech_availability
  for delete to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

-- ── tech_time_off ───────────────────────────────────────────────────────────
drop policy if exists toff_insert_self on public.tech_time_off;
create policy toff_insert_self on public.tech_time_off
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists toff_delete_self on public.tech_time_off;
create policy toff_delete_self on public.tech_time_off
  for delete to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

-- ── standing_appointments ───────────────────────────────────────────────────
drop policy if exists standing_select_involved on public.standing_appointments;
create policy standing_select_involved on public.standing_appointments
  for select to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs
                    where lower(email) = public.current_email()
                       or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists standing_update_tech on public.standing_appointments;
create policy standing_update_tech on public.standing_appointments
  for update to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  )
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

-- ── blocked_clients ─────────────────────────────────────────────────────────
drop policy if exists blk_select_self on public.blocked_clients;
create policy blk_select_self on public.blocked_clients
  for select to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists blk_insert_self on public.blocked_clients;
create policy blk_insert_self on public.blocked_clients
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists blk_delete_self on public.blocked_clients;
create policy blk_delete_self on public.blocked_clients
  for delete to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

-- ── bookings (tech leg only; client + admin legs unchanged) ─────────────────
drop policy if exists bookings_select_involved on public.bookings;
create policy bookings_select_involved on public.bookings
  for select to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs
                    where lower(email) = public.current_email()
                       or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists bookings_update_involved on public.bookings;
create policy bookings_update_involved on public.bookings
  for update to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs
                    where lower(email) = public.current_email()
                       or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  )
  with check (
    client_id = auth.uid()
    or tech_id in (select id from public.techs
                    where lower(email) = public.current_email()
                       or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists bookings_delete_involved on public.bookings;
create policy bookings_delete_involved on public.bookings
  for delete to authenticated
  using (
    client_id = auth.uid()
    or tech_id in (select id from public.techs
                    where lower(email) = public.current_email()
                       or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

commit;

-- ── Confirm (read-only) ─────────────────────────────────────────────────────
-- Every booking-table policy should now mention current_phone.
select tablename, policyname,
       case when coalesce(qual,'') || coalesce(with_check,'') like '%current_phone%'
            then 'phone-aware' else 'EMAIL ONLY' end as identity
from pg_policies
where schemaname = 'public'
  and tablename in ('tech_services','tech_availability','tech_time_off',
                    'standing_appointments','blocked_clients','bookings')
order by tablename, policyname;
