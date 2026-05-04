-- ============================================================================
-- og-comps-prune.sql
-- ----------------------------------------------------------------------------
-- DESTRUCTIVE: Trims public.tech_comps down to active OG techs only.
-- Deletes comp rows whose email does NOT have a matching public.techs row
-- (i.e., archived techs that were seeded into tech_comps for re-onboarding).
--
-- Why this is safe:
--   - tech_comps rows for archived emails (no public.techs row) → just removed.
--   - The forward trigger sync_tech_comp_to_techs_trg fires on DELETE but
--     only updates public.techs rows that EXIST. Since these emails have no
--     public.techs row, the trigger is effectively a no-op for them.
--   - Active techs are protected by the WHERE filter below.
--
-- Edit the ALLOW_LIST array if you want to KEEP a comp for someone who
-- doesn't have a public.techs row (e.g., Leslie if she's admin-only,
-- or any opt-in archived techs you've decided to grandfather in).
--
-- Run STEP 1 first. Read it. Then run STEP 2.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 1 — PREVIEW (read-only)
-- ----------------------------------------------------------------------------
-- Tags every comp row as KEEP or DELETE so you can eyeball it before nuking.
-- ----------------------------------------------------------------------------
select
  tc.email,
  tc.monthly_limit,
  tc.note,
  case
    when t.email is not null then
      'KEEP — active tech (in public.techs)'
    when lower(tc.email) = any (array[
      -- ALLOW_LIST: emails to KEEP even without a public.techs row.
      -- Add Leslie's email here if she should retain her comp.
      'leslie@example.com'
      -- , 'another@example.com'
    ]::text[]) then
      'KEEP — explicit allow-list'
    else
      'DELETE — archived (no public.techs row)'
  end as plan
from public.tech_comps tc
left join public.techs t on lower(t.email) = lower(tc.email)
order by plan, tc.email;


-- ----------------------------------------------------------------------------
-- STEP 2 — DELETE (run after STEP 1)
-- ----------------------------------------------------------------------------
-- IMPORTANT: keep the ALLOW_LIST array here in sync with STEP 1.
-- ----------------------------------------------------------------------------
delete from public.tech_comps tc
where not exists (
  select 1 from public.techs t where lower(t.email) = lower(tc.email)
)
and lower(tc.email) <> all (array[
  -- ALLOW_LIST: must match STEP 1 above.
  'leslie@example.com'
  -- , 'another@example.com'
]::text[]);


-- ----------------------------------------------------------------------------
-- STEP 3 — VERIFY
-- ----------------------------------------------------------------------------
-- (a) Count what's left.
-- (b) Should return zero rows OTHER than your allow-listed emails.
-- ----------------------------------------------------------------------------
select count(*) as remaining_comps from public.tech_comps;

select tc.email
from public.tech_comps tc
left join public.techs t on lower(t.email) = lower(tc.email)
where t.email is null;
-- ↑ Any row here = comp without a matching public.techs. Should only ever be
--   the ALLOW_LIST emails. If anything else shows up, investigate before
--   running og-auth-bulk-create.sql.
