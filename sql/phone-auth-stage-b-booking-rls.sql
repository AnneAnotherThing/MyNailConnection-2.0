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


-- ============================================================================
-- ALSO IN STAGE B: fix the signup RPC's replay guard  (2026-07-24)
-- ============================================================================
-- The guard only accepted auth.users rows CREATED in the last 5 minutes.
-- Anyone who verified a code but backed out of the profile step already has
-- an auth row, so on every later attempt created_at is old and the RPC
-- refused forever with no_recent_auth, that number could never finish
-- signing up (Leslie hit the abandoned-signup state, 2026-07-24).
-- last_sign_in_at updates on EVERY successful OTP verify, so the guard now
-- accepts either: a row just created, or a fresh re-verification.
-- Function body is otherwise byte-identical to Stage A.
-- ============================================================================

create or replace function public.create_signup_profile_phone(
  p_phone                 text,
  p_name                  text,
  p_role                  text,
  p_email                 text default null,
  p_address               text default null,
  p_city                  text default null,
  p_state                 text default null,
  p_zip                   text default null,
  p_bio                   text default null,
  p_shop_name             text default null,
  p_hours_available       text default null,
  p_tags                  text[] default null,
  p_image_url             text default null,
  p_liability_version     text default null,
  p_liability_accepted_at timestamptz default null
) returns jsonb
  language plpgsql security definer set search_path = public
as $$
declare
  v_now_date   date := (now() at time zone 'utc')::date;
  v_auth_id    uuid;
  v_digits     text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_email      text := nullif(btrim(coalesce(p_email, '')), '');
begin
  if v_digits is null or length(v_digits) < 10 then
    return jsonb_build_object('ok', false, 'code', 'bad_phone', 'message', 'a valid phone is required');
  end if;
  if p_role not in ('client', 'tech') then
    return jsonb_build_object('ok', false, 'code', 'bad_role', 'message', 'role must be client or tech');
  end if;

  -- Replay-window: the phone must have completed OTP in the last 5 minutes.
  select id into v_auth_id
    from auth.users
   where regexp_replace(coalesce(phone, ''), '\D', '', 'g') = v_digits
     and greatest(created_at, coalesce(last_sign_in_at, created_at)) > now() - interval '5 minutes'
   order by created_at desc
   limit 1;

  if v_auth_id is null then
    return jsonb_build_object('ok', false, 'code', 'no_recent_auth',
      'message', 'no auth.users row for this phone created in the last 5 minutes');
  end if;

  -- users insert (idempotent on phone)
  if not exists (select 1 from public.users where phone_digits(phone) = v_digits) then
    begin
      insert into public.users (
        name, email, role, joined, phone, address, city, state, zip,
        bio, image_url, liability_version, liability_accepted_at, last_password_change
      ) values (
        p_name, v_email, p_role, v_now_date, p_phone, p_address, p_city, p_state, p_zip,
        p_bio, p_image_url, p_liability_version, p_liability_accepted_at, now()
      );
    exception when unique_violation then
      return jsonb_build_object('ok', false, 'code', '23505', 'message', sqlerrm,
        'details', 'unique violation on public.users');
    end;
  end if;

  -- techs insert (tech role only, idempotent on phone)
  if p_role = 'tech' then
    if not exists (select 1 from public.techs where phone_digits(phone) = v_digits) then
      begin
        insert into public.techs (
          name, email, phone, address, city, state, zip, bio,
          shop_name, hours_available, tags, image_url, liability_version, liability_accepted_at
        ) values (
          p_name, v_email, p_phone, p_address, p_city, p_state, p_zip, p_bio,
          p_shop_name, p_hours_available, p_tags, p_image_url, p_liability_version, p_liability_accepted_at
        );
      exception when unique_violation then
        return jsonb_build_object('ok', false, 'code', '23505', 'message', sqlerrm,
          'details', 'unique violation on public.techs');
      end;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'auth_id', v_auth_id);
end;
$$;
