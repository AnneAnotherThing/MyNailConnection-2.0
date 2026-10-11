-- MNC: the phone sign-up RPC trusts the caller's own session.
-- Anne, 2026-10-10: after a good code, the account form answered "Your code
-- expired" (no_recent_auth) twelve seconds later. The RPC only looked for an
-- auth.users row created or signed in within five minutes, and a Supabase
-- test phone number verifies without stamping last_sign_in_at. The fix:
-- when the caller's JWT phone is the phone being signed up, that is proof
-- enough; the five-minute window stays as the fallback. Body otherwise
-- identical to sql/phone-auth-stage-b-booking-rls.sql.
--
-- Idempotent. Re-run freely.

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

  -- Who may create this profile: the caller whose session IS this phone.
  -- The signed-in JWT carries the phone that just passed OTP, which is the
  -- strongest proof there is. The old five-minute window on auth.users is
  -- kept only as a fallback for callers without a phone claim.
  -- (2026-10-10: Supabase test phone numbers verify without touching
  -- last_sign_in_at, so the window alone refused Anne's own sign-up with
  -- no_recent_auth twelve seconds after a good code.)
  if length(coalesce(public.current_phone(), '')) >= 10
     and right(public.current_phone(), 10) = right(v_digits, 10) then
    select id into v_auth_id
      from auth.users
     where regexp_replace(coalesce(phone, ''), '\D', '', 'g') = v_digits
     order by created_at desc
     limit 1;
  end if;

  if v_auth_id is null then
    select id into v_auth_id
      from auth.users
     where regexp_replace(coalesce(phone, ''), '\D', '', 'g') = v_digits
       and greatest(created_at, coalesce(last_sign_in_at, created_at)) > now() - interval '5 minutes'
     order by created_at desc
     limit 1;
  end if;

  if v_auth_id is null then
    return jsonb_build_object('ok', false, 'code', 'no_recent_auth',
      'message', 'this session is not signed in as that phone');
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

grant execute on function public.create_signup_profile_phone(text, text, text, text, text, text, text, text, text, text, text, text[], text, text, timestamptz) to authenticated;
