-- ========================================================================
-- MNC 3.0 Booking Test Accounts  (2026-07-05)
-- ========================================================================
-- Creates two pre-confirmed logins for end-to-end booking tests:
--
--   TECH   annewilson1021+booktech@gmail.com    password MNC2026
--   CLIENT annewilson1021+bookclient@gmail.com  password MNC2026
--
-- Plus-addresses land in Anne's real inbox if a reset is ever needed,
-- but email_confirmed_at is pre-stamped so no email is sent at all.
-- Neither address matches is_admin(), so both are plain-role accounts.
--
-- Run ORDER: booking-system-migration.sql first, then this. Safe to
-- re-run, every insert is guarded by an exists-check.
--
-- CAUTION: the tech row is visible in the live browse feed while it
-- exists (there is no hidden flag on techs). It's named so nobody books
-- it by accident, but run the CLEANUP block when testing is done.
-- ========================================================================

do $$
declare
  rec record;
  new_user_id uuid;
begin
  for rec in
    select * from (values
      ('annewilson1021+booktech@gmail.com',   'tech'),
      ('annewilson1021+bookclient@gmail.com', 'client')
    ) as t(email, role)
  loop
    -- auth.users + auth.identities (same idiom as og-auth-bulk-create.sql)
    if not exists (select 1 from auth.users where lower(email) = rec.email) then
      new_user_id := gen_random_uuid();

      insert into auth.users (
        id, instance_id, aud, role, email, encrypted_password,
        email_confirmed_at, created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data,
        confirmation_token, recovery_token, email_change_token_new, email_change
      ) values (
        new_user_id, '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', rec.email,
        crypt('MNC2026', gen_salt('bf')),
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        '', '', '', ''
      );

      insert into auth.identities (
        id, user_id, identity_data, provider, provider_id,
        last_sign_in_at, created_at, updated_at
      ) values (
        gen_random_uuid(), new_user_id,
        jsonb_build_object('sub', new_user_id::text, 'email', rec.email),
        'email', new_user_id::text, null, now(), now()
      );

      raise notice 'Created auth user: %', rec.email;
    end if;

    -- public.users profile row (columns per create_signup_profile)
    if not exists (select 1 from public.users where lower(email) = rec.email) then
      insert into public.users (name, email, role, joined, last_password_change)
      values (
        case when rec.role = 'tech' then 'Booking Test Tech' else 'Booking Test Client' end,
        rec.email, rec.role, current_date, now()
      );
      raise notice 'Created users row: %', rec.email;
    end if;
  end loop;

  -- public.techs row for the tech (named so no real client books it)
  if not exists (select 1 from public.techs where lower(email) = 'annewilson1021+booktech@gmail.com') then
    insert into public.techs (name, email, bio, shop_name, city, state, tags)
    values (
      'ZZ TEST, do not book',
      'annewilson1021+booktech@gmail.com',
      'Internal test account for the new booking system. Please ignore!',
      'MNC Test Studio', 'Phoenix', 'AZ', '[]'::jsonb
    );
    raise notice 'Created techs row';
  end if;
end $$;


-- ========================================================================
-- VERIFY, should return 2 rows with confirmed = true
-- ========================================================================
select u.email, u.role, au.email_confirmed_at is not null as confirmed
from public.users u
join auth.users au on lower(au.email) = lower(u.email)
where lower(u.email) in
  ('annewilson1021+booktech@gmail.com', 'annewilson1021+bookclient@gmail.com');


-- ========================================================================
-- CLEANUP, run when booking testing is DONE (destructive, scoped to the
-- two test emails only; removes their bookings/services/hours too)
-- ========================================================================
-- delete from public.bookings
--   where tech_id in (select id from public.techs where lower(email) = 'annewilson1021+booktech@gmail.com')
--      or client_id in (select id from auth.users where lower(email) = 'annewilson1021+bookclient@gmail.com');
-- delete from public.tech_services
--   where tech_id in (select id from public.techs where lower(email) = 'annewilson1021+booktech@gmail.com');
-- delete from public.tech_availability
--   where tech_id in (select id from public.techs where lower(email) = 'annewilson1021+booktech@gmail.com');
-- delete from public.techs where lower(email) = 'annewilson1021+booktech@gmail.com';
-- delete from public.users where lower(email) in
--   ('annewilson1021+booktech@gmail.com', 'annewilson1021+bookclient@gmail.com');
-- delete from auth.identities where user_id in (select id from auth.users where lower(email) in
--   ('annewilson1021+booktech@gmail.com', 'annewilson1021+bookclient@gmail.com'));
-- delete from auth.users where lower(email) in
--   ('annewilson1021+booktech@gmail.com', 'annewilson1021+bookclient@gmail.com');
