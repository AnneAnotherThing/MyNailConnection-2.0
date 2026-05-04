-- ============================================================================
-- og-auth-bulk-create.sql
-- ----------------------------------------------------------------------------
-- For every email in public.tech_comps that does NOT already have an
-- auth.users row, create one with password 'MNC2026' and a matching
-- auth.identities row so email/password login works.
--
-- Run in Supabase → SQL Editor (needs the dashboard's superuser role).
-- pgcrypto must be enabled (it is, by default in Supabase).
--
-- BEFORE you run the DO block: run STEP 1 (preview) to see exactly who
-- will be created and who will be skipped. AFTER you run the DO block:
-- run STEP 3 (verify) to confirm everyone now has an auth row.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 1 — PREVIEW (read-only, run first)
-- ----------------------------------------------------------------------------
-- Lists every tech_comps email and whether an auth.users row already exists.
-- 'will create' rows are what the DO block will insert.
-- ----------------------------------------------------------------------------
select
  lower(tc.email) as email,
  case
    when au.id is not null then 'skip — auth row exists'
    when t.email is null   then 'will create — ARCHIVED (no public.techs row, will be orphan-auth until they re-onboard)'
    else                        'will create — active tech'
  end as plan,
  t.email is not null as has_techs_row
from public.tech_comps tc
left join auth.users   au on lower(au.email) = lower(tc.email)
left join public.techs t  on lower(t.email)  = lower(tc.email)
order by plan, email;


-- ----------------------------------------------------------------------------
-- STEP 2 — CREATE auth.users + auth.identities for missing emails
-- ----------------------------------------------------------------------------
-- Run AFTER you've reviewed STEP 1 and are happy with the plan.
--
-- To restrict to ACTIVE techs only (skip archived/orphan-auth-prone emails),
-- uncomment the marked line inside the loop.
-- ----------------------------------------------------------------------------
do $$
declare
  rec record;
  new_user_id uuid;
  created_count int := 0;
  skipped_count int := 0;
begin
  for rec in
    select lower(tc.email) as email
    from public.tech_comps tc
    where not exists (
      select 1 from auth.users au where lower(au.email) = lower(tc.email)
    )
    -- Uncomment this to skip archived techs (option a):
    -- and exists (select 1 from public.techs t where lower(t.email) = lower(tc.email))
    order by tc.email
  loop
    new_user_id := gen_random_uuid();

    insert into auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      created_at,
      updated_at,
      raw_app_meta_data,
      raw_user_meta_data,
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change
    ) values (
      new_user_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      rec.email,
      crypt('MNC2026', gen_salt('bf')),
      now(),  -- pre-confirm email so they can sign in immediately
      now(),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      '', '', '', ''
    );

    -- Identity row is required for email/password login on modern Supabase.
    insert into auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      new_user_id,
      jsonb_build_object('sub', new_user_id::text, 'email', rec.email),
      'email',
      new_user_id::text,
      null,
      now(),
      now()
    );

    created_count := created_count + 1;
    raise notice 'Created auth user: %', rec.email;
  end loop;

  raise notice '---';
  raise notice 'Summary: % created, % skipped (already existed)', created_count, skipped_count;
end $$;


-- ----------------------------------------------------------------------------
-- STEP 3 — VERIFY (run after STEP 2)
-- ----------------------------------------------------------------------------
-- Should return zero rows. Any row here is a tech_comps email that didn't
-- get an auth row — investigate.
-- ----------------------------------------------------------------------------
select tc.email
from public.tech_comps tc
left join auth.users au on lower(au.email) = lower(tc.email)
where au.id is null;


-- ----------------------------------------------------------------------------
-- ROLLBACK (only if something is clearly wrong — DESTRUCTIVE)
-- ----------------------------------------------------------------------------
-- Deletes auth.users + auth.identities rows for tech_comps emails that
-- were created TODAY. Filters by created_at::date = current_date so it
-- can't accidentally nuke older accounts. Read it twice before running.
-- ----------------------------------------------------------------------------
-- delete from auth.identities
-- where user_id in (
--   select au.id
--   from auth.users au
--   join public.tech_comps tc on lower(au.email) = lower(tc.email)
--   where au.created_at::date = current_date
-- );
--
-- delete from auth.users au
-- using public.tech_comps tc
-- where lower(au.email) = lower(tc.email)
--   and au.created_at::date = current_date;
