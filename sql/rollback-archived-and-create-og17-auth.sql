-- ========================================================================
-- Rollback Archived-Tech Restore + Create OG-17 Auth  (2026-05-02)
-- ========================================================================
-- Course-correction script. The previous archived-tech-restore script
-- created public.users / public.techs / public.tech_comps rows for every
-- archived tech, but the underlying archived_techs data was too sparse
-- to be useful (mostly empty phone/address/etc). Rather than backfill
-- garbage on top of garbage, we're rolling those rows back and focusing
-- on what matters: making sure the OG 17 active techs in public.techs
-- can sign in.
--
-- WHAT THIS DOES
--   PART A, Rollback
--     Deletes the rows we added in the previous script. Identified by:
--       - public.tech_comps:  the specific note string we set
--       - public.techs:       placeholder phone pattern (0000 + digits)
--                             AND email exists in public.archived_techs
--       - public.users:       same dual filter as techs
--     The dual "placeholder phone" + "in archived_techs" filter is
--     belt-and-suspenders, protects any real tech that happens to be
--     in archived_techs from being accidentally deleted.
--
--   PART B, Create auth for OG 17
--     For every tech in public.techs without an auth.users row, creates:
--       - auth.users        with password = 'MNC2026', email_confirmed
--       - auth.identities   with provider='email' (required for sign-in
--                           on modern Supabase, without it, the user
--                           exists but can't authenticate)
--     Excludes anne@mynailconnection.com, leslie@mynailconnection.com,
--     appleuser1@gmail.com.
--
-- ORDER (run sections in order)
--   SECTION 1, Discovery: preview what'll be deleted + who needs auth
--   SECTION 2, Rollback (DELETEs)
--   SECTION 3, Create auth.users + auth.identities for OG 17
--   SECTION 4, Verification
--
-- Safe to re-run. Section 2 deletes are filtered to be precise; Section 3
-- skips anyone who already has an auth row.
-- ========================================================================


-- ========================================================================
-- SECTION 1, DISCOVERY (read-only)
-- ========================================================================

-- 1A. What would be deleted from tech_comps?
select email, granted_at::date as granted, note
  from public.tech_comps
 where note = 'MNC 1.0 archived founder, restored 2026-05-02, comped Glow Up'
 order by email;

-- 1B. What would be deleted from techs? (placeholder phone pattern)
select t.email,
       t.name,
       t.phone,
       (exists (select 1 from public.archived_techs a where lower(a.email) = lower(t.email))) as in_archive,
       t.subscription_tier,
       t.created_at
  from public.techs t
 where t.phone like '0000%'
   and t.phone ~ '^0000[0-9]+$'
   and length(t.phone) > 20
 order by t.email;

-- 1C. What would be deleted from users? (same pattern)
select u.email,
       u.name,
       u.phone,
       u.role,
       (exists (select 1 from public.archived_techs a where lower(a.email) = lower(u.email))) as in_archive,
       u.joined
  from public.users u
 where u.phone like '0000%'
   and u.phone ~ '^0000[0-9]+$'
   and length(u.phone) > 20
 order by u.email;

-- 1D. Who in techs needs an auth row created? (the OG 17 minus those
--     who already have auth)
select t.email,
       t.name,
       t.subscription_tier,
       t.joined,
       case when au.id is null then 'NEEDS AUTH' else 'has auth' end as auth_status
  from public.techs t
  left join auth.users au on lower(au.email) = lower(btrim(t.email))
 where lower(t.email) not in (
   'anne@mynailconnection.com',
   'leslie@mynailconnection.com',
   'appleuser1@gmail.com'
 )
 order by case when au.id is null then 0 else 1 end, t.name;


-- ========================================================================
-- SECTION 2, ROLLBACK (deletes the archived-tech additions)
-- ========================================================================
-- Order: tech_comps first → techs → users.
-- Deleting tech_comps first triggers sync_tech_comp_to_techs DELETE which
-- flips subscription_tier back to 'free' on the techs row, but we're
-- about to delete the techs row anyway, so the trigger work is harmless.

-- 2A. tech_comps rows we created (matched by exact note string)
delete from public.tech_comps
 where note = 'MNC 1.0 archived founder, restored 2026-05-02, comped Glow Up'
   and email in (
     select lower(btrim(email)) from public.archived_techs where email is not null
   );

-- 2B. techs rows with placeholder phone, scoped to archived emails
delete from public.techs
 where phone like '0000%'
   and phone ~ '^0000[0-9]+$'
   and length(phone) > 20
   and lower(email) in (
     select lower(btrim(email)) from public.archived_techs where email is not null
   );

-- 2C. users rows with placeholder phone, scoped to archived emails
delete from public.users
 where phone like '0000%'
   and phone ~ '^0000[0-9]+$'
   and length(phone) > 20
   and lower(email) in (
     select lower(btrim(email)) from public.archived_techs where email is not null
   );


-- ========================================================================
-- SECTION 3, CREATE auth.users + auth.identities FOR THE OG 17
-- ========================================================================
-- For each tech in public.techs without an auth row, hand-create both
-- the auth.users row AND the auth.identities row. Modern Supabase (post
-- mid-2023) requires the auth.identities row for email/password sign-in
-- to function, without it, the user exists in auth.users but can't sign
-- in via password.
--
-- Pattern matches what supabase.auth.admin.createUser() does internally:
--   - auth.users.encrypted_password set with bcrypt
--   - email_confirmed_at = now() to skip confirmation
--   - raw_app_meta_data identifies provider as 'email'
--   - auth.identities.provider = 'email'
--   - auth.identities.provider_id = the email (modern convention)
--   - identity_data carries sub/email/email_verified

do $$
declare
  r record;
  v_user_id uuid;
  v_inserted int := 0;
begin
  for r in
    select t.email, t.name
      from public.techs t
      left join auth.users au on lower(au.email) = lower(btrim(t.email))
     where au.id is null
       and t.email is not null
       and btrim(t.email) <> ''
       and lower(t.email) not in (
         'anne@mynailconnection.com',
         'leslie@mynailconnection.com',
         'appleuser1@gmail.com'
       )
  loop
    v_user_id := gen_random_uuid();

    -- auth.users
    insert into auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      created_at,
      updated_at,
      raw_app_meta_data,
      raw_user_meta_data,
      is_super_admin,
      is_sso_user,
      is_anonymous,
      confirmation_token,
      recovery_token,
      email_change,
      email_change_token_new,
      email_change_token_current
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      lower(btrim(r.email)),
      crypt('MNC2026', gen_salt('bf')),
      now(),
      now(),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('name', coalesce(r.name, '')),
      false,
      false,
      false,
      '',
      '',
      '',
      '',
      ''
    );

    -- auth.identities (required for email/password sign-in to work)
    insert into auth.identities (
      id,
      user_id,
      provider,
      provider_id,
      identity_data,
      last_sign_in_at,
      created_at,
      updated_at
    )
    values (
      gen_random_uuid(),
      v_user_id,
      'email',
      lower(btrim(r.email)),
      jsonb_build_object(
        'sub',            v_user_id::text,
        'email',          lower(btrim(r.email)),
        'email_verified', true,
        'phone_verified', false
      ),
      null,
      now(),
      now()
    );

    v_inserted := v_inserted + 1;
  end loop;

  raise notice 'Created auth.users + auth.identities for % techs', v_inserted;
end $$;

-- Mirror the password-change timestamp onto public.users so the audit
-- trail reflects this batch.
update public.users u
   set last_password_change = now()
 where lower(u.email) in (
   select lower(t.email)
     from public.techs t
    where t.email is not null
      and lower(t.email) not in (
        'anne@mynailconnection.com',
        'leslie@mynailconnection.com',
        'appleuser1@gmail.com'
      )
 );


-- ========================================================================
-- SECTION 4, VERIFICATION
-- ========================================================================

-- 4A. Confirm the rollback removed everything (these should all be 0)
select 'tech_comps with our note' as what,
       count(*) as remaining
  from public.tech_comps
 where note = 'MNC 1.0 archived founder, restored 2026-05-02, comped Glow Up'
union all
select 'techs with placeholder phone' as what,
       count(*) as remaining
  from public.techs
 where phone like '0000%' and phone ~ '^0000[0-9]+$' and length(phone) > 20
union all
select 'users with placeholder phone' as what,
       count(*) as remaining
  from public.users
 where phone like '0000%' and phone ~ '^0000[0-9]+$' and length(phone) > 20;

-- 4B. Confirm every tech in public.techs now has an auth row
select t.email,
       t.name,
       case when au.id is not null then 'has auth' else 'STILL MISSING' end as auth_status,
       au.email_confirmed_at,
       au.updated_at as auth_updated
  from public.techs t
  left join auth.users au on lower(au.email) = lower(btrim(t.email))
 order by case when au.id is null then 0 else 1 end, t.name;

-- 4C. Spot-check one freshly-created auth row to confirm it looks right
select au.email,
       au.email_confirmed_at,
       au.created_at,
       (select count(*) from auth.identities i where i.user_id = au.id) as identity_count
  from auth.users au
 where au.created_at > now() - interval '5 minutes'
 order by au.created_at desc
 limit 5;
