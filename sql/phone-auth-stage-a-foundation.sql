-- ============================================================================
-- PHONE-AUTH, STAGE A: foundation (run this first, in the Supabase SQL editor)
-- ============================================================================
-- Goal: accounts become phone-first. A client signs up with just a phone +
-- SMS code, no email. Techs get an OPTIONAL email (receipts / recovery).
-- Email accounts that already exist keep working, untouched.
--
-- The trick that makes this SAFE and additive: instead of ripping email out
-- of RLS, every owner-check now passes if EITHER the JWT's email OR the JWT's
-- phone matches the row. Email users match on email (as before); phone users
-- match on phone. Nothing existing breaks.
--
-- This migration does NOT touch data and is safe to re-run.
--   1. Make users.email / techs.email nullable (phone-only clients have none)
--   2. current_phone() helper (mirrors current_email())
--   3. create_signup_profile_phone() RPC, keyed on the phone that just
--      completed /auth/v1/otp, instead of the email the old RPC required
--   4. RLS on users / techs / board_posts / push_subscriptions accepts
--      email OR phone identity
--
-- Depends on: is_admin(), current_email() (from sql/rls-fix.sql, already run).
-- 2026-07-23
-- ============================================================================

begin;

-- ── 1. Email is optional now ────────────────────────────────────────────────
alter table public.users alter column email drop not null;
alter table public.techs alter column email drop not null;

-- ── 2. current_phone(): the caller's verified phone, digits only ────────────
-- GoTrue puts the verified phone in the JWT `phone` claim as E.164 (+1602...).
-- We compare on digits only so formatting differences never cause a miss.
create or replace function public.current_phone() returns text
language sql stable as $$
  select nullif(regexp_replace(coalesce(auth.jwt() ->> 'phone', ''), '\D', '', 'g'), '');
$$;

-- Digits-only of an arbitrary stored phone, for the comparison side.
create or replace function public.phone_digits(p text) returns text
language sql immutable as $$
  select nullif(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '');
$$;

-- ── 3. Phone-keyed signup-profile RPC ───────────────────────────────────────
-- Mirrors create_signup_profile, but the identity is the phone that just
-- verified via /auth/v1/otp (auth.users.phone, created in the last 5 minutes),
-- and email is optional. SECURITY DEFINER so it can insert past RLS, with its
-- own replay-window guard so a caller can only seed a profile for a phone that
-- actually just authenticated.
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
     and created_at > now() - interval '5 minutes'
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

grant execute on function public.create_signup_profile_phone(
  text, text, text, text, text, text, text, text, text, text, text, text[], text, text, timestamptz
) to anon, authenticated;

-- ── 4. RLS accepts email OR phone identity ──────────────────────────────────
-- Owner check helper: does THIS row belong to the caller, by email or phone?
-- (Kept inline per-table below rather than a helper, so each policy stays
--  greppable and the phone column name is explicit.)

-- USERS
drop policy if exists users_select_self on public.users;
drop policy if exists users_insert_self on public.users;
drop policy if exists users_update_self on public.users;
create policy users_select_self on public.users for select to authenticated
  using (lower(email) = public.current_email()
         or phone_digits(phone) = public.current_phone()
         or public.is_admin());
create policy users_insert_self on public.users for insert to authenticated
  with check (lower(email) = public.current_email()
              or phone_digits(phone) = public.current_phone()
              or public.is_admin());
create policy users_update_self on public.users for update to authenticated
  using (lower(email) = public.current_email()
         or phone_digits(phone) = public.current_phone()
         or public.is_admin())
  with check (lower(email) = public.current_email()
              or phone_digits(phone) = public.current_phone()
              or public.is_admin());

-- TECHS
drop policy if exists techs_update_self on public.techs;
create policy techs_update_self on public.techs for update to authenticated
  using (lower(email) = public.current_email()
         or phone_digits(phone) = public.current_phone())
  with check (lower(email) = public.current_email()
              or phone_digits(phone) = public.current_phone());

-- BOARD_POSTS (tech_id historically holds the tech's email; keep that, add phone
-- via a lookup to their techs row so phone-only techs can post/edit)
drop policy if exists board_insert_self on public.board_posts;
drop policy if exists board_update_self on public.board_posts;
drop policy if exists board_delete_self on public.board_posts;
create policy board_insert_self on public.board_posts for insert to authenticated
  with check (lower(tech_id) = public.current_email()
              or tech_id in (select email from public.techs where phone_digits(phone) = public.current_phone())
              or public.is_admin());
create policy board_update_self on public.board_posts for update to authenticated
  using (lower(tech_id) = public.current_email()
         or tech_id in (select email from public.techs where phone_digits(phone) = public.current_phone())
         or public.is_admin())
  with check (lower(tech_id) = public.current_email()
              or tech_id in (select email from public.techs where phone_digits(phone) = public.current_phone())
              or public.is_admin());
create policy board_delete_self on public.board_posts for delete to authenticated
  using (lower(tech_id) = public.current_email()
         or tech_id in (select email from public.techs where phone_digits(phone) = public.current_phone())
         or public.is_admin());

-- PUSH_SUBSCRIPTIONS (user_id historically holds email; accept phone too)
drop policy if exists push_select_self on public.push_subscriptions;
drop policy if exists push_insert_self on public.push_subscriptions;
drop policy if exists push_update_self on public.push_subscriptions;
drop policy if exists push_delete_self on public.push_subscriptions;
create policy push_select_self on public.push_subscriptions for select to authenticated
  using (lower(user_id) = public.current_email() or phone_digits(user_id) = public.current_phone() or public.is_admin());
create policy push_insert_self on public.push_subscriptions for insert to authenticated
  with check (lower(user_id) = public.current_email() or phone_digits(user_id) = public.current_phone() or public.is_admin());
create policy push_update_self on public.push_subscriptions for update to authenticated
  using (lower(user_id) = public.current_email() or phone_digits(user_id) = public.current_phone() or public.is_admin())
  with check (lower(user_id) = public.current_email() or phone_digits(user_id) = public.current_phone() or public.is_admin());
create policy push_delete_self on public.push_subscriptions for delete to authenticated
  using (lower(user_id) = public.current_email() or phone_digits(user_id) = public.current_phone() or public.is_admin());

commit;

-- ============================================================================
-- After running this:
--   - Email accounts: unchanged, still work.
--   - Phone accounts: can create a profile (RPC) and own their rows (RLS).
-- Next (Stage B, app side): the phone signup / sign-in UI, wired to this RPC.
-- Then one real-device SMS test before trusting it.
-- ============================================================================
