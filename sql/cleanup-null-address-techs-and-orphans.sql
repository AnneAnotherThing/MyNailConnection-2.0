-- ========================================================================
-- Cleanup: NULL-Address Techs + Orphans  (2026-05-02)
-- ========================================================================
-- Run AFTER rollback-archived-and-create-og17-auth.sql.
--
-- WHAT THIS DOES
--   PART A, Delete techs with NULL/empty address.
--            Cascades the delete across the tech's full footprint so we
--            don't create new orphans:
--              - public.tech_comps (by email)
--              - public.techs      (by id)
--              - public.users      (by email)
--              - auth.users        (by email; auth.identities cascades
--                                   automatically via FK)
--
--   PART B, Show every category of orphan so you can pick which to nuke.
--            Each orphan category has a discovery query and a DELETE that
--            is COMMENTED OUT. Uncomment the ones you want to run.
--
-- ORDER (run sections in order)
--   SECTION 1, Discovery: preview NULL-address techs + every orphan type
--   SECTION 2, Delete NULL-address techs (cascading cleanup)
--   SECTION 3, Orphan deletes (commented; uncomment per category)
--   SECTION 4, Verification
--
-- Exclusions honored throughout: anne@mynailconnection.com,
-- leslie@mynailconnection.com, appleuser1@gmail.com.
-- ========================================================================


-- ========================================================================
-- SECTION 1, DISCOVERY (read-only)
-- ========================================================================

-- 1A. Techs with NULL/empty address (will be deleted in Section 2)
select t.id,
       t.email,
       t.name,
       t.phone,
       t.city,
       t.state,
       t.subscription_tier,
       t.created_at
  from public.techs t
 where (t.address is null or btrim(t.address) = '')
   and lower(t.email) not in (
     'anne@mynailconnection.com',
     'leslie@mynailconnection.com',
     'appleuser1@gmail.com'
   )
 order by t.name;

-- 1B. Orphan type 1, public.techs rows with NO matching public.users row
select t.id, t.email, t.name, 'techs without users row' as orphan_type
  from public.techs t
  left join public.users u on lower(u.email) = lower(btrim(t.email))
 where u.id is null
   and lower(t.email) not in (
     'anne@mynailconnection.com',
     'leslie@mynailconnection.com',
     'appleuser1@gmail.com'
   );

-- 1C. Orphan type 2, public.users with role='tech' but NO public.techs row
select u.id, u.email, u.name, u.role, 'users(role=tech) without techs row' as orphan_type
  from public.users u
  left join public.techs t on lower(t.email) = lower(btrim(u.email))
 where u.role = 'tech'
   and t.id is null
   and lower(u.email) not in (
     'anne@mynailconnection.com',
     'leslie@mynailconnection.com',
     'appleuser1@gmail.com'
   );

-- 1D. Orphan type 3, public.users with NO auth.users row (can't sign in)
select u.id, u.email, u.name, u.role, 'users without auth row' as orphan_type
  from public.users u
  left join auth.users au on lower(au.email) = lower(btrim(u.email))
 where au.id is null
   and lower(u.email) not in (
     'anne@mynailconnection.com',
     'leslie@mynailconnection.com',
     'appleuser1@gmail.com'
   );

-- 1E. Orphan type 4, auth.users with NO public.users row (auth-only accounts)
select au.id, au.email, au.created_at, 'auth without users row' as orphan_type
  from auth.users au
  left join public.users u on lower(u.email) = lower(btrim(au.email))
 where u.id is null
   and lower(au.email) not in (
     'anne@mynailconnection.com',
     'leslie@mynailconnection.com',
     'appleuser1@gmail.com'
   );

-- 1F. Orphan type 5, tech_comps for emails that exist nowhere else
select c.email, c.note, c.granted_at::date as granted, 'comp with no tech anywhere' as orphan_type
  from public.tech_comps c
 where not exists (select 1 from public.techs t          where lower(t.email)  = c.email)
   and not exists (select 1 from public.users u          where lower(u.email)  = c.email)
   and not exists (select 1 from public.archived_techs a where lower(a.email)  = c.email);


-- ========================================================================
-- SECTION 2, DELETE NULL-ADDRESS TECHS (full cascade)
-- ========================================================================
-- Build the target email set ONCE in a CTE so all four deletes target the
-- same emails (otherwise the techs delete could remove a row and the
-- subsequent users/auth deletes wouldn't see it).

with target_emails as (
  select lower(btrim(t.email)) as email
    from public.techs t
   where (t.address is null or btrim(t.address) = '')
     and lower(t.email) not in (
       'anne@mynailconnection.com',
       'leslie@mynailconnection.com',
       'appleuser1@gmail.com'
     )
),
del_comps as (
  delete from public.tech_comps
   where email in (select email from target_emails)
  returning 1
),
del_techs as (
  delete from public.techs
   where lower(email) in (select email from target_emails)
  returning 1
),
del_users as (
  delete from public.users
   where lower(email) in (select email from target_emails)
  returning 1
),
del_auth as (
  delete from auth.users
   where lower(email) in (select email from target_emails)
  returning 1
)
select
  (select count(*) from target_emails) as targeted_emails,
  (select count(*) from del_comps)     as tech_comps_deleted,
  (select count(*) from del_techs)     as techs_deleted,
  (select count(*) from del_users)     as users_deleted,
  (select count(*) from del_auth)      as auth_users_deleted;


-- ========================================================================
-- SECTION 3, ORPHAN DELETES (commented out, uncomment per category)
-- ========================================================================
-- After Section 2 runs, re-run Section 1's queries to see which orphans
-- remain. Then uncomment the ones below that match what you want to nuke.

-- ─── 3A. Delete techs without a users row (orphan type 1) ──────────────
-- delete from public.tech_comps
--  where email in (
--    select lower(t.email) from public.techs t
--     left join public.users u on lower(u.email) = lower(btrim(t.email))
--    where u.id is null
--  );
-- delete from auth.users
--  where lower(email) in (
--    select lower(t.email) from public.techs t
--     left join public.users u on lower(u.email) = lower(btrim(t.email))
--    where u.id is null
--  );
-- delete from public.techs t
--  using (
--    select t2.id from public.techs t2
--     left join public.users u on lower(u.email) = lower(btrim(t2.email))
--    where u.id is null
--  ) o
--  where t.id = o.id;


-- ─── 3B. Delete users(role=tech) without a techs row (orphan type 2) ──
-- delete from public.tech_comps
--  where email in (
--    select lower(u.email) from public.users u
--     left join public.techs t on lower(t.email) = lower(btrim(u.email))
--    where u.role = 'tech' and t.id is null
--  );
-- delete from auth.users
--  where lower(email) in (
--    select lower(u.email) from public.users u
--     left join public.techs t on lower(t.email) = lower(btrim(u.email))
--    where u.role = 'tech' and t.id is null
--  );
-- delete from public.users u
--  using (
--    select u2.id from public.users u2
--     left join public.techs t on lower(t.email) = lower(btrim(u2.email))
--    where u2.role = 'tech' and t.id is null
--  ) o
--  where u.id = o.id;


-- ─── 3C. Delete users without an auth row (orphan type 3) ─────────────
-- delete from public.users u
--  using (
--    select u2.id from public.users u2
--     left join auth.users au on lower(au.email) = lower(btrim(u2.email))
--    where au.id is null
--  ) o
--  where u.id = o.id;


-- ─── 3D. Delete auth.users without a public.users row (orphan type 4) ─
-- delete from auth.users au
--  using (
--    select au2.id from auth.users au2
--     left join public.users u on lower(u.email) = lower(btrim(au2.email))
--    where u.id is null
--      and lower(au2.email) not in (
--        'anne@mynailconnection.com',
--        'leslie@mynailconnection.com',
--        'appleuser1@gmail.com'
--      )
--  ) o
--  where au.id = o.id;


-- ─── 3E. Delete comps with no tech anywhere (orphan type 5) ───────────
-- delete from public.tech_comps c
--  where not exists (select 1 from public.techs t          where lower(t.email)  = c.email)
--    and not exists (select 1 from public.users u          where lower(u.email)  = c.email)
--    and not exists (select 1 from public.archived_techs a where lower(a.email)  = c.email);


-- ========================================================================
-- SECTION 4, VERIFICATION
-- ========================================================================

-- 4A. No techs left with NULL address
select count(*) as null_address_techs_remaining
  from public.techs
 where (address is null or btrim(address) = '')
   and lower(email) not in (
     'anne@mynailconnection.com',
     'leslie@mynailconnection.com',
     'appleuser1@gmail.com'
   );

-- 4B. Final tech roster (the keepers)
select t.id,
       t.name,
       t.email,
       t.city,
       t.state,
       t.subscription_tier,
       (au.id is not null)                                         as has_auth,
       (exists (select 1 from public.users u where lower(u.email) = lower(t.email))) as has_users_row,
       (exists (select 1 from public.tech_comps c where c.email   = lower(t.email))) as is_comped
  from public.techs t
  left join auth.users au on lower(au.email) = lower(btrim(t.email))
 order by t.name;

-- 4C. Cross-table sanity (all four counts should make sense together)
select
  (select count(*) from public.techs)      as techs_count,
  (select count(*) from public.users where role='tech') as users_tech_count,
  (select count(*) from public.tech_comps) as tech_comps_count,
  (select count(*) from auth.users
    where lower(email) not in ('anne@mynailconnection.com','leslie@mynailconnection.com','appleuser1@gmail.com')
  ) as auth_users_excluding_admins;
