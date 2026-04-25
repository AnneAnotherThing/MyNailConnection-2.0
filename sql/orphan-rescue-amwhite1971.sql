-- ========================================================================
-- Orphan-rescue migration for amwhite1971@gmail.com  (2026-04-24)
-- ========================================================================
-- She has an auth.users row but no public.users / public.techs profile
-- rows, so the app can't find her (gallery empty, availability toggle
-- PATCH matches zero rows and silently no-ops). The normal signup RPC
-- (public.create_signup_profile) refuses to backfill because its
-- 5-minute replay window has long since expired.
--
-- This script:
--   1. Verifies the auth.users row exists (NOTICE with her id).
--   2. Inserts a minimal public.users profile row if missing.
--   3. Inserts a minimal public.techs row if missing.
--   4. Returns both rows so you can eyeball them before refreshing the app.
--
-- Safe to re-run. Every INSERT is gated on "not already there."
--
-- After running: have amwhite1971 sign in and finish her profile from
-- the tech dashboard (name, bio, photos, etc.). The display name below
-- is a placeholder — she can overwrite it via the app.
-- ========================================================================

do $$
declare
  v_email text := 'amwhite1971@gmail.com';
  v_auth_id uuid;
  v_auth_created timestamptz;
  v_today date := (now() at time zone 'utc')::date;
  v_placeholder_phone text;
begin
  -- -- 1) Locate the auth user --
  select id, created_at
    into v_auth_id, v_auth_created
    from auth.users
   where lower(email) = lower(v_email)
   order by created_at desc
   limit 1;

  if v_auth_id is null then
    raise exception 'No auth.users row for % — nothing to rescue. Check the email spelling or the Supabase Auth dashboard.', v_email;
  end if;

  raise notice 'Found auth.users id = % (created %)', v_auth_id, v_auth_created;

  -- -- Placeholder phone --
  -- public.users.phone and public.techs.phone are both NOT NULL + UNIQUE
  -- (phone-email-uniqueness-migration). We derive a digits-only string
  -- from the uuid so it's globally unique per-account and obviously fake
  -- (prefixed "0000") so Anne knows which rows still need a real number.
  -- The tech can replace it with their real phone from the profile
  -- screen as soon as they can sign in.
  v_placeholder_phone := '0000' || regexp_replace(v_auth_id::text, '\D', '', 'g');

  -- -- 2) public.users stamp --
  if not exists (select 1 from public.users where lower(email) = lower(v_email)) then
    insert into public.users (name, email, phone, role, joined, last_password_change)
    values ('New Tech', v_email, v_placeholder_phone, 'tech', v_today, now());
    raise notice 'Inserted public.users row for %', v_email;
  else
    raise notice 'public.users row already exists for %, leaving it alone', v_email;
  end if;

  -- -- 3) public.techs row --
  if not exists (select 1 from public.techs where lower(email) = lower(v_email)) then
    insert into public.techs (name, email, phone)
    values ('New Tech', v_email, v_placeholder_phone);
    raise notice 'Inserted public.techs row for %', v_email;
  else
    raise notice 'public.techs row already exists for %, leaving it alone', v_email;
  end if;
end $$;

-- -- 4) Verify --
select 'users'  as source, id::text as id, email, name, phone, role, joined::text as joined
  from public.users
 where lower(email) = 'amwhite1971@gmail.com'
union all
select 'techs'  as source, id::text as id, email, name, phone, null as role, null as joined
  from public.techs
 where lower(email) = 'amwhite1971@gmail.com';
