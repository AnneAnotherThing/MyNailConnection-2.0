-- ========================================================================
-- MNC Signup Profile RPC  (2026-04-21)
-- ========================================================================
-- Creates public.create_signup_profile() - a SECURITY DEFINER RPC that
-- lets the signup flow insert into public.users (and, for techs,
-- public.techs) even when the caller is anon - i.e., when Supabase
-- "Confirm email" is ON and the user has no JWT yet.
--
-- Why we need this:
--   RLS on public.users grants INSERT only to the "authenticated" role
--   where the row's email matches auth.jwt() email. With Confirm-email
--   ON (which Anne keeps on intentionally to block sybil accounts -
--   see memory: project_mnc_email_confirmation_on_by_design), the user
--   has no session until they click the confirmation link, so they
--   can't satisfy the RLS check at the moment of signup. An anon-key
--   INSERT therefore 401s, and the auth.users row ends up orphaned
--   (no matching profile row ever gets created).
--
-- Anti-abuse properties of this RPC:
--   1. The RPC looks up the email in auth.users - the caller can ONLY
--      create a profile for an email that successfully completed the
--      /auth/v1/signup endpoint. No freehand profile creation.
--   2. It requires auth.users.created_at to be within the last 5
--      minutes - bounds the replay window. An attacker who guesses a
--      victim's email can't come back later and create a profile for
--      them; the signup would have to have JUST happened.
--   3. It's idempotent - if a profile row already exists for the email,
--      returns success without clobbering. Prevents re-running the RPC
--      from overwriting fields the user has since edited.
--   4. It NEVER touches auth.users. Only public schema inserts.
--
-- Safe to re-run. Uses CREATE OR REPLACE.
-- ========================================================================


-- ========================================================================
-- BLOCK 1 - The RPC
-- ========================================================================

create or replace function public.create_signup_profile(
  p_email                 text,
  p_name                  text,
  p_role                  text,
  p_phone                 text default null,
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
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_now_date   date := (now() at time zone 'utc')::date;
  v_auth_id    uuid;
  v_created_at timestamptz;
begin
  -- -- Input normalisation --
  if p_email is null or btrim(p_email) = '' then
    return jsonb_build_object('ok', false, 'code', 'bad_email', 'message', 'email is required');
  end if;
  if p_role not in ('client', 'tech') then
    return jsonb_build_object('ok', false, 'code', 'bad_role', 'message', 'role must be client or tech');
  end if;

  -- -- Replay-window check --
  -- The caller must have completed /auth/v1/signup for this email within
  -- the last 5 minutes. If not, deny.
  select id, created_at
    into v_auth_id, v_created_at
    from auth.users
   where lower(email) = lower(btrim(p_email))
     and created_at > now() - interval '5 minutes'
   order by created_at desc
   limit 1;

  if v_auth_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'no_recent_auth',
      'message', 'no auth.users row for this email created in the last 5 minutes'
    );
  end if;

  -- -- public.users insert (idempotent) --
  -- If a row already exists for this email, leave it alone and report
  -- success - caller treats this as "already seeded". Prevents double
  -- submits from overwriting user-edited data.
  if not exists (
    select 1 from public.users where lower(email) = lower(btrim(p_email))
  ) then
    begin
      insert into public.users (
        name, email, role, joined, phone, address, city, state, zip,
        bio, image_url, liability_version, liability_accepted_at
      ) values (
        p_name, p_email, p_role, v_now_date, p_phone, p_address, p_city, p_state, p_zip,
        p_bio, p_image_url, p_liability_version, p_liability_accepted_at
      );
    exception when unique_violation then
      -- Phone or secondary-email collision: surface it so the client
      -- can route to the "Welcome back!" modal (code matches PostgREST
      -- convention so existing client logic keeps working).
      return jsonb_build_object(
        'ok', false,
        'code', '23505',
        'message', sqlerrm,
        'details', 'unique violation on public.users'
      );
    end;
  end if;

  -- -- public.techs insert (tech role only, idempotent) --
  if p_role = 'tech' then
    if not exists (
      select 1 from public.techs where lower(email) = lower(btrim(p_email))
    ) then
      begin
        insert into public.techs (
          name, email, phone, address, city, state, zip, bio,
          shop_name, hours_available, tags, image_url,
          liability_version, liability_accepted_at
        ) values (
          p_name, p_email, p_phone, p_address, p_city, p_state, p_zip, p_bio,
          p_shop_name, p_hours_available, p_tags, p_image_url,
          p_liability_version, p_liability_accepted_at
        );
      exception when unique_violation then
        return jsonb_build_object(
          'ok', false,
          'code', '23505',
          'message', sqlerrm,
          'details', 'unique violation on public.techs'
        );
      end;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'auth_id', v_auth_id);
end;
$$;


-- ========================================================================
-- BLOCK 2 - Grants
-- ========================================================================
-- Both anon (Confirm-email-ON branch) AND authenticated (Confirm-email-
-- OFF branch) need EXECUTE. The replay-window check inside the function
-- is what enforces access, not the grant.
-- ========================================================================

grant execute on function public.create_signup_profile(
  text, text, text, text, text, text, text, text, text, text, text,
  text[], text, text, timestamptz
) to anon, authenticated;
