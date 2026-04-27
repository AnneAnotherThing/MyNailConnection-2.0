-- ========================================================================
-- MNC Email-Casing Fix  (2026-04-27)
-- ========================================================================
-- Symptom: a fresh tech signup landed on the client home with no
-- "Tech Portal" pill — even though public.users.role was 'tech' and
-- the public.techs row existed.
--
-- Root cause: Supabase auto-lowercases auth.users.email on signup. The
-- create_signup_profile RPC, however, was inserting `p_email` into
-- public.users and public.techs as-typed. iOS / iPadOS keyboards
-- auto-capitalize the first letter of the email field by default, so
-- the public rows ended up with a capital first letter while auth.users
-- stayed lowercase. PostgREST `eq.` is case-sensitive, so showCorrectHome
-- in the app —
--
--   /rest/v1/users?email=eq.sonoran…@gmail.com  (lowercased from auth)
--
-- — never matched the row stored as `Sonoran…@gmail.com`. The role
-- lookup returned zero rows, _mncCurrentRole stayed empty, and the
-- home view defaulted to client. Hit by Anne's Sonoran-Sun test
-- account on 2026-04-27.
--
-- This migration:
--   1. Replaces create_signup_profile so future inserts always store
--      `lower(btrim(p_email))`.
--   2. Backfills any existing rows in public.users / public.techs whose
--      email differs from its lowercase form.
--
-- Safe to re-run. Block 1 uses CREATE OR REPLACE; Block 2's UPDATEs are
-- guarded by `where email <> lower(email)` so they're no-ops once clean.
-- ========================================================================


-- ========================================================================
-- BLOCK 1 — Patched RPC (now writes lower-cased email everywhere)
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
  v_email      text;
begin
  -- Input normalisation. Lower-case + trim once up front so every
  -- downstream check and insert uses the canonical form.
  if p_email is null or btrim(p_email) = '' then
    return jsonb_build_object('ok', false, 'code', 'bad_email', 'message', 'email is required');
  end if;
  if p_role not in ('client', 'tech') then
    return jsonb_build_object('ok', false, 'code', 'bad_role', 'message', 'role must be client or tech');
  end if;
  v_email := lower(btrim(p_email));

  -- Replay-window check.
  select id, created_at
    into v_auth_id, v_created_at
    from auth.users
   where lower(email) = v_email
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

  -- public.users insert (idempotent, lower-cased email).
  if not exists (
    select 1 from public.users where lower(email) = v_email
  ) then
    begin
      insert into public.users (
        name, email, role, joined, phone, address, city, state, zip,
        bio, image_url, liability_version, liability_accepted_at,
        last_password_change
      ) values (
        p_name, v_email, p_role, v_now_date, p_phone, p_address, p_city, p_state, p_zip,
        p_bio, p_image_url, p_liability_version, p_liability_accepted_at,
        now()
      );
    exception when unique_violation then
      return jsonb_build_object(
        'ok', false,
        'code', '23505',
        'message', sqlerrm,
        'details', 'unique violation on public.users'
      );
    end;
  end if;

  -- public.techs insert (tech role only, idempotent, lower-cased email).
  if p_role = 'tech' then
    if not exists (
      select 1 from public.techs where lower(email) = v_email
    ) then
      begin
        insert into public.techs (
          name, email, phone, address, city, state, zip, bio,
          shop_name, hours_available, tags, image_url,
          liability_version, liability_accepted_at
        ) values (
          p_name, v_email, p_phone, p_address, p_city, p_state, p_zip, p_bio,
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

grant execute on function public.create_signup_profile(
  text, text, text, text, text, text, text, text, text, text, text,
  text[], text, text, timestamptz
) to anon, authenticated;


-- ========================================================================
-- BLOCK 2 — Backfill: lowercase any existing mixed-case emails
-- ========================================================================
-- Run this once. The `where email <> lower(email)` guard makes it
-- idempotent — re-running after the data is clean is a no-op. If a
-- row collides on the lower-case form (would violate a unique
-- constraint), the UPDATE will raise `23505 unique_violation` so we
-- can investigate the collision rather than silently dropping data.

update public.users
   set email = lower(btrim(email))
 where email <> lower(btrim(email));

update public.techs
   set email = lower(btrim(email))
 where email <> lower(btrim(email));

-- Optional sanity check — should both return 0 after the updates above.
-- select count(*) as users_still_mixed  from public.users where email <> lower(btrim(email));
-- select count(*) as techs_still_mixed  from public.techs where email <> lower(btrim(email));
