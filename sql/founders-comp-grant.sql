-- ========================================================================
-- MNC Founders Comp Grant  (2026-04-27)
-- ========================================================================
-- Comps the 17 OG techs (already in public.techs), Leslie, and any
-- archived techs you want to invite back. Everyone goes into the
-- public.tech_comps table; the sync trigger does the rest.
--
-- No copy-pasting emails into placeholder rows — the active 17 already
-- live in public.techs, so we INSERT ... SELECT directly. The archived
-- ones come from public.archived_techs the same way.
--
-- Prerequisite: free-upload-counter-fix.sql has been run (creates
-- public.tech_comps and the sync triggers).
--
-- Three groups of comps, each with the same pattern:
--   STEP A — review who'd be comped
--   STEP B — comp ALL of them (uncomment to run)
--   STEP C — comp specific people (uncomment + paste IDs to run)
--   STEP D — verify
-- ========================================================================


-- ════════════════════════════════════════════════════════════════════════
-- GROUP 1 — Active techs (everyone in public.techs)
-- ════════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────────────
-- STEP A.1 — Review the active tech list. The `already_comped` column
-- tells you who's already in tech_comps so re-running won't surprise.
-- The `joined` date is your sanity-check for "is this an OG founder vs
-- a test account I made yesterday?"
-- ────────────────────────────────────────────────────────────────────────

select t.id,
       coalesce(t.name, '(no name)')   as name,
       coalesce(t.email, '(no email)') as email,
       t.joined,
       t.subscription_tier,
       (exists (select 1 from public.tech_comps c
                 where c.email = lower(btrim(coalesce(t.email, '')))
       )) as already_comped
  from public.techs t
 order by t.joined nulls last, lower(coalesce(t.name, t.email, ''));


-- ────────────────────────────────────────────────────────────────────────
-- STEP B.1 — Comp ALL active techs. One statement, idempotent.
-- on conflict do nothing protects re-runs and prevents clobbering any
-- comps you've already manually added with custom notes / limits.
-- ────────────────────────────────────────────────────────────────────────

-- Uncomment to run:
--
-- insert into public.tech_comps (email, granted_by, note, monthly_limit)
-- select lower(btrim(t.email)),
--        'anne@mynailconnection.com',
--        'MNC 1.0 founder — comped Glow Up',
--        40
--   from public.techs t
--  where t.email is not null
--    and btrim(t.email) <> ''
-- on conflict (email) do nothing;


-- ────────────────────────────────────────────────────────────────────────
-- STEP C.1 — Comp ONLY specific active techs. Use this if STEP A.1
-- shows test accounts mixed in with the 17 OGs and you want to skip
-- them. Paste the IDs from STEP A.1's output.
-- ────────────────────────────────────────────────────────────────────────

-- Uncomment to run:
--
-- insert into public.tech_comps (email, granted_by, note, monthly_limit)
-- select lower(btrim(t.email)),
--        'anne@mynailconnection.com',
--        'MNC 1.0 founder — comped Glow Up',
--        40
--   from public.techs t
--  where t.id in (
--    'paste-tech-id-1',
--    'paste-tech-id-2'
--    -- ... etc
--  )
--    and t.email is not null
--    and btrim(t.email) <> ''
-- on conflict (email) do nothing;


-- ════════════════════════════════════════════════════════════════════════
-- GROUP 2 — Leslie (explicit, since she's an admin not in techs)
-- ════════════════════════════════════════════════════════════════════════
-- This INSERT is unconditional — Leslie should always have the comp on
-- the comps table whether or not she's in public.techs. Idempotent via
-- on conflict do nothing.

insert into public.tech_comps (email, granted_by, note, monthly_limit)
values
  (lower(btrim('leslie@mynailconnection.com')),
   'anne@mynailconnection.com',
   'Co-admin / founding partner',
   40)
on conflict (email) do nothing;


-- ════════════════════════════════════════════════════════════════════════
-- GROUP 3 — Archived techs (in public.archived_techs)
-- ════════════════════════════════════════════════════════════════════════
-- Archived techs have no public.techs row right now. Adding them to
-- tech_comps records the comp; when they re-sign-up via the regular
-- flow, the apply_pending_comp_on_tech_insert trigger (in
-- free-upload-counter-fix.sql) auto-stamps subscription_tier='paid'
-- on their newly-created techs row. So the order is: comp them now,
-- send the invite / password-reset email, they sign up and immediately
-- show up as Glow Up members with the gold badge.

-- ────────────────────────────────────────────────────────────────────────
-- STEP A.3 — Review the archived list.
-- ────────────────────────────────────────────────────────────────────────

select at.id,
       coalesce(at.name, '(no name)')   as name,
       coalesce(at.email, '(no email)') as email,
       coalesce(at.city || ', ' || at.state, '') as location,
       (exists (select 1 from public.tech_comps c
                 where c.email = lower(btrim(coalesce(at.email, '')))
       )) as already_comped
  from public.archived_techs at
 order by lower(coalesce(at.name, at.email, ''));


-- ────────────────────────────────────────────────────────────────────────
-- STEP B.3 — Comp ALL archived techs (the easy path).
-- ────────────────────────────────────────────────────────────────────────

-- Uncomment to run:
--
-- insert into public.tech_comps (email, granted_by, note, monthly_limit)
-- select lower(btrim(at.email)),
--        'anne@mynailconnection.com',
--        'MNC 1.0 archived founder — comped Glow Up',
--        40
--   from public.archived_techs at
--  where at.email is not null
--    and btrim(at.email) <> ''
-- on conflict (email) do nothing;


-- ────────────────────────────────────────────────────────────────────────
-- STEP C.3 — Comp ONLY specific archived techs (the picky path).
-- ────────────────────────────────────────────────────────────────────────

-- Uncomment to run:
--
-- insert into public.tech_comps (email, granted_by, note, monthly_limit)
-- select lower(btrim(at.email)),
--        'anne@mynailconnection.com',
--        'MNC 1.0 archived founder — comped Glow Up',
--        40
--   from public.archived_techs at
--  where at.id in (
--    'paste-archived-id-1',
--    'paste-archived-id-2'
--    -- ... etc
--  )
--    and at.email is not null
--    and btrim(at.email) <> ''
-- on conflict (email) do nothing;


-- ════════════════════════════════════════════════════════════════════════
-- VERIFY — final state of the comps table
-- ════════════════════════════════════════════════════════════════════════
-- Shows everyone in tech_comps with two flags:
--   has_techs_row — false = waiting for them to re-onboard
--   from_archive  — true  = they came from the archived list
-- ════════════════════════════════════════════════════════════════════════

select c.email,
       c.note,
       c.granted_at::date as granted,
       (exists (select 1 from public.techs t where lower(t.email) = c.email))     as has_techs_row,
       (exists (select 1 from public.archived_techs a where lower(a.email) = c.email)) as from_archive
  from public.tech_comps c
 order by from_archive desc, has_techs_row desc, c.granted_at desc;


-- ────────────────────────────────────────────────────────────────────────
-- HOW TO ADD ONE PERSON LATER (no migration needed):
--
--   insert into public.tech_comps (email, granted_by, note, monthly_limit)
--   values (lower(btrim('newperson@example.com')),
--           'anne@mynailconnection.com',
--           'Personal grant — friend of the platform',
--           40)
--   on conflict (email) do nothing;
--
-- HOW TO REVOKE A COMP:
--
--   delete from public.tech_comps where email = 'theiremail@example.com';
--
-- HOW TO CHANGE SOMEONE'S MONTHLY LIMIT:
--
--   update public.tech_comps set monthly_limit = 80
--    where email = 'theiremail@example.com';
-- ────────────────────────────────────────────────────────────────────────
