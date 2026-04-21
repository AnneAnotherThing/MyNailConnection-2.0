-- ============================================================================
-- Mobile tech address privacy
-- ============================================================================
-- Adds a boolean flag so mobile techs can keep their location off the map.
-- Defaults ON for any existing tech already tagged "Mobile".
-- ============================================================================

alter table public.techs
  add column if not exists hide_address_public boolean default false;

-- Default to hidden for existing Mobile techs
update public.techs
   set hide_address_public = true
 where 'Mobile' = any(tags)
   and hide_address_public = false;

-- Verify — should list every Mobile tech with hide_address_public = true
select name, email, hide_address_public, tags
  from public.techs
 where 'Mobile' = any(tags)
 order by name;
