-- MNC: fill blank city and state from the ZIP, for techs and clients, now and
-- from here on (Anne, 2026-10-13: "can we backfill tech's states using zips?").
--
-- zip_centroids (sql/wh-travel-radius.sql, loaded by the zip-centroids files)
-- knows the city and state of every US ZIP, so a blank city or state next to a
-- real ZIP is a solved problem:
--   1. Backfill: every techs and users row with a ZIP and a blank city or state
--      gets the ZIP's. Only blanks change; nothing on file is overwritten.
--   2. Trigger: the same fill runs before every insert or update on both
--      tables, so a tech still on an older build who saves without a city
--      gets one anyway, and a client's ZIP alone is enough to place her.
-- On 2026-10-13 every tech already had a state (the Oct 11 backfill); the only
-- blank city with a real ZIP was Harlie (85119, Apache Junction). Nail It
-- Forever's ZIP 86587 does not exist, so she stays blank until she fixes it.
--
-- Run AFTER the zip-centroids files. Idempotent. Re-run freely. Copy the
-- whole file into a FRESH query. Proof this is the new copy: the trigger is
-- named wh_fill_place_trg.

begin;

-- Fill blank city and state on a techs or users row from its ZIP.
create or replace function public.wh_fill_place() returns trigger
language plpgsql
set search_path = public
as $$
declare
  z public.zip_centroids;
begin
  if coalesce(btrim(new.zip), '') = '' then return new; end if;
  if coalesce(btrim(new.city), '') <> '' and coalesce(btrim(new.state), '') <> '' then return new; end if;
  z := public.wh_zip_point(new.zip);
  if z.zip is null then return new; end if;
  if coalesce(btrim(new.city), '') = '' then new.city := z.city; end if;
  if coalesce(btrim(new.state), '') = '' then new.state := z.state; end if;
  return new;
end $$;

drop trigger if exists wh_fill_place_trg on public.techs;
create trigger wh_fill_place_trg before insert or update of zip, city, state on public.techs
  for each row execute function public.wh_fill_place();

drop trigger if exists wh_fill_place_trg on public.users;
create trigger wh_fill_place_trg before insert or update of zip, city, state on public.users
  for each row execute function public.wh_fill_place();

-- Backfill the rows that exist today. The update fires the trigger, which
-- does the filling; the where clause keeps it to rows with a gap and a ZIP.
update public.techs t
   set zip = t.zip
 where coalesce(btrim(t.zip), '') <> ''
   and (coalesce(btrim(t.city), '') = '' or coalesce(btrim(t.state), '') = '')
   and (public.wh_zip_point(t.zip)).zip is not null;

update public.users u
   set zip = u.zip
 where coalesce(btrim(u.zip), '') <> ''
   and (coalesce(btrim(u.city), '') = '' or coalesce(btrim(u.state), '') = '')
   and (public.wh_zip_point(u.zip)).zip is not null;

commit;

-- Checks (SQL editor, as the project owner):
--   Techs still missing a city or state, with what their ZIP says (expect
--   only rows whose ZIP is not real):
--   select t.name, t.zip, t.city, t.state, z.city as zip_city, z.state as zip_state
--     from public.techs t left join public.zip_centroids z on z.zip = left(regexp_replace(coalesce(t.zip, ''), '\D', '', 'g'), 5)
--    where coalesce(btrim(t.city), '') = '' or coalesce(btrim(t.state), '') = '';
--   Clients the same way:
--   select count(*) from public.users u
--    where coalesce(btrim(u.zip), '') <> '' and (coalesce(btrim(u.city), '') = '' or coalesce(btrim(u.state), '') = '');
--   Harlie should now read Apache Junction, AZ.
