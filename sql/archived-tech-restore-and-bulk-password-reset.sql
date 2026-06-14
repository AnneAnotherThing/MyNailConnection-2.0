-- ========================================================================
-- Archived-Tech Restore + Bulk Password Reset  (2026-05-02)
-- ========================================================================
-- Two related operations bundled into one script because the password
-- portion needs to apply to BOTH the freshly-restored archived techs AND
-- the existing user base in a single sweep.
--
-- WHAT THIS DOES
--   1. Restores everyone in public.archived_techs to active status:
--        - Inserts public.users row if missing (role='tech')
--        - Inserts public.techs row if missing (placeholder phone if none)
--        - Inserts public.tech_comps row if missing → trigger auto-stamps
--          subscription_tier='paid' on the techs row (Glow Up for life)
--        - Sets the auth.users password to 'MNC2026' (for those that
--          already have an auth row)
--   2. Resets the auth password to 'MNC2026' for ALL other users EXCEPT:
--        - anne@mynailconnection.com
--        - leslie@mynailconnection.com
--        - appleuser1@gmail.com
--
-- IMPORTANT, auth.users prerequisite
--   Restoring an archived tech only fully works if there's already an
--   auth.users row for that email. Section 1 reports anyone missing an
--   auth row so you can decide how to onboard them (invite email via
--   Supabase admin, or hand-create, the latter is risky from raw SQL).
--   Section 2 STILL inserts public.users / public.techs / tech_comps for
--   them so the moment their auth row appears, they're ready to roll.
--
-- ORDER OF OPERATIONS (run sections in order)
--   SECTION 1, Discovery (read-only, run first to see scope)
--   SECTION 2, Restore archived techs (public.users / techs / comps)
--   SECTION 3, Set passwords (archived techs + bulk reset, all in one)
--   SECTION 4, Verification
--
-- Safe to re-run. All inserts use ON CONFLICT DO NOTHING / NOT EXISTS
-- guards. Password updates are idempotent (re-running just re-sets the
-- same hash).
-- ========================================================================


-- ========================================================================
-- SECTION 1, DISCOVERY (read-only)
-- ========================================================================
-- Run these first. Don't proceed to Section 2 until the numbers look
-- right. If anything surprises you (an Android tester showing up in the
-- bulk-reset count, an archived tech you didn't expect, etc.) STOP and
-- ping Claude before continuing.

-- 1A. Archived techs by auth status
select
  count(*)                          as total_archived,
  count(au.id)                      as have_auth_row,
  count(*) - count(au.id)           as need_auth_row_created
  from public.archived_techs at
  left join auth.users au on lower(au.email) = lower(btrim(at.email));

-- 1B. Per-archived-tech detail
select
  at.email,
  coalesce(at.name, '(no name)') as name,
  case when au.id is not null then 'has auth row' else 'NO AUTH ROW' end as auth_status,
  exists(select 1 from public.users      u where lower(u.email) = lower(btrim(at.email))) as has_users_row,
  exists(select 1 from public.techs      t where lower(t.email) = lower(btrim(at.email))) as has_techs_row,
  exists(select 1 from public.tech_comps c where c.email        = lower(btrim(at.email))) as has_comp
  from public.archived_techs at
  left join auth.users au on lower(au.email) = lower(btrim(at.email))
 order by case when au.id is null then 0 else 1 end, at.name;

-- 1C. Bulk-reset scope: who would have their password set to MNC2026?
select
  count(*) as users_to_reset,
  array_agg(email order by email) as emails_affected
  from auth.users
 where lower(email) not in (
   'anne@mynailconnection.com',
   'leslie@mynailconnection.com',
   'appleuser1@gmail.com'
 );


-- ========================================================================
-- SECTION 2, RESTORE ARCHIVED TECHS
-- ========================================================================
-- Mirrors orphan-rescue-amwhite1971.sql pattern but loops over every
-- archived_techs row. Inserts public.users + public.techs + tech_comps
-- for each, gated on "not already there." The tech_comps insert fires
-- the apply_pending_comp_on_tech_insert trigger (or sync_tech_comp_to_techs
-- if techs already exists), which auto-stamps subscription_tier='paid'.

do $$
declare
  r record;
  v_today date := (now() at time zone 'utc')::date;
  v_placeholder_phone text;
  v_users_inserted    int := 0;
  v_techs_inserted    int := 0;
  v_comps_inserted    int := 0;
begin
  for r in
    select at.email, at.name
      from public.archived_techs at
     where at.email is not null
       and btrim(at.email) <> ''
  loop
    -- Stable per-account placeholder phone (mirrors orphan-rescue).
    -- Uses md5(email) as a digits source so it stays stable across re-runs
    -- and is obviously fake (prefixed "0000").
    v_placeholder_phone := '0000' || regexp_replace(md5(lower(r.email)), '\D', '', 'g');

    -- public.users
    if not exists (select 1 from public.users where lower(email) = lower(r.email)) then
      insert into public.users (name, email, phone, role, joined, last_password_change)
      values (coalesce(r.name, 'New Tech'), r.email, v_placeholder_phone, 'tech', v_today, now());
      v_users_inserted := v_users_inserted + 1;
    end if;

    -- public.techs
    -- The before-insert trigger apply_pending_comp_on_tech_insert will
    -- check tech_comps and stamp subscription_tier='paid' if a comp
    -- already exists. We insert the tech row FIRST, then comp, the
    -- after-insert trigger sync_tech_comp_to_techs will sync paid status
    -- on the comp insert.
    if not exists (select 1 from public.techs where lower(email) = lower(r.email)) then
      insert into public.techs (name, email, phone)
      values (coalesce(r.name, 'New Tech'), r.email, v_placeholder_phone);
      v_techs_inserted := v_techs_inserted + 1;
    end if;

    -- public.tech_comps  →  trigger handles subscription_tier sync
    if not exists (select 1 from public.tech_comps where email = lower(btrim(r.email))) then
      insert into public.tech_comps (email, granted_by, note, monthly_limit)
      values (
        lower(btrim(r.email)),
        'anne@mynailconnection.com',
        'MNC 1.0 archived founder, restored 2026-05-02, comped Glow Up',
        40
      );
      v_comps_inserted := v_comps_inserted + 1;
    end if;
  end loop;

  raise notice 'Restored archived techs:';
  raise notice '  public.users rows inserted: %', v_users_inserted;
  raise notice '  public.techs rows inserted: %', v_techs_inserted;
  raise notice '  public.tech_comps rows inserted: %', v_comps_inserted;
end $$;


-- ========================================================================
-- SECTION 3, SET PASSWORDS (one bulk update covers everyone)
-- ========================================================================
-- Single UPDATE handles both:
--   (a) archived techs that have an auth row → password becomes MNC2026
--   (b) every other auth user → password becomes MNC2026
-- Anne / Leslie / appleuser1@gmail.com are the ONLY exclusions.
--
-- Also clears any pending recovery / email-change tokens that would
-- otherwise put accounts into a "complete your reset" UI state on next
-- sign-in (the same fix we used for the Apple test user earlier today).

update auth.users
   set encrypted_password       = crypt('MNC2026', gen_salt('bf')),
       recovery_token           = '',
       recovery_sent_at         = null,
       email_change_token_new   = '',
       email_change_token_current = '',
       email_change             = '',
       email_change_sent_at     = null,
       updated_at               = now()
 where lower(email) not in (
   'anne@mynailconnection.com',
   'leslie@mynailconnection.com',
   'appleuser1@gmail.com'
 );

-- Mirror the password-change timestamp onto public.users for the audit
-- trail (last_password_change is what the app reads). Same exclusion list.
update public.users
   set last_password_change = now()
 where lower(email) not in (
   'anne@mynailconnection.com',
   'leslie@mynailconnection.com',
   'appleuser1@gmail.com'
 );


-- ========================================================================
-- SECTION 4, VERIFICATION
-- ========================================================================

-- 4A. Confirm exclusions were preserved (their updated_at should NOT be ~now)
select email,
       updated_at,
       (updated_at > now() - interval '5 minutes') as recently_updated__should_be_false
  from auth.users
 where lower(email) in (
   'anne@mynailconnection.com',
   'leslie@mynailconnection.com',
   'appleuser1@gmail.com'
 )
 order by email;

-- 4B. Confirm everyone else got the password reset (updated_at within 5 min)
select count(*) as users_recently_password_reset
  from auth.users
 where lower(email) not in (
   'anne@mynailconnection.com',
   'leslie@mynailconnection.com',
   'appleuser1@gmail.com'
 )
   and updated_at > now() - interval '5 minutes';

-- 4C. Confirm every archived tech now shows up correctly
select at.email,
       case when au.id is not null then 'YES' else 'no auth, needs invite' end as has_auth,
       (exists (select 1 from public.users      u where lower(u.email) = lower(btrim(at.email)))) as has_users_row,
       (exists (select 1 from public.techs      t where lower(t.email) = lower(btrim(at.email)))) as has_techs_row,
       (exists (select 1 from public.tech_comps c where c.email        = lower(btrim(at.email)))) as has_comp,
       (select subscription_tier from public.techs t where lower(t.email) = lower(btrim(at.email))) as tier
  from public.archived_techs at
  left join auth.users au on lower(au.email) = lower(btrim(at.email))
 order by case when au.id is null then 0 else 1 end, at.email;

-- 4D. Final tech_comps roster (should include all archived + active comps)
select c.email,
       c.note,
       c.granted_at::date as granted,
       (exists (select 1 from public.techs t where lower(t.email) = c.email))           as has_techs_row,
       (exists (select 1 from public.archived_techs a where lower(a.email) = c.email))  as from_archive
  from public.tech_comps c
 order by from_archive desc, has_techs_row desc, c.granted_at desc;
