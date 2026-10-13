-- MNC: a map pin for every tech (Anne, 2026-10-13: "put the 14 invisible
-- techs on the map").
--
-- The Near Me map and the distance filters read techs.lat and techs.lng,
-- which the app fills by geocoding the street address on profile save. A
-- tech with no address, or whose geocode never came back, has no pin and no
-- distance, so a client browsing Near Me never sees her. 14 of 39 techs sat
-- like that on 2026-10-13, every one of them with a ZIP.
--
-- What this does:
--   1. Backfill: every tech with a ZIP and no coordinates gets the center of
--      her ZIP (zip_centroids), or the center of her city when the ZIP is not
--      a real one. Only null lat/lng change; a geocoded address is never
--      touched.
--   2. Trigger: the same fill runs before every insert or update on techs, so
--      a new tech has a pin the moment she saves, and the app's address
--      geocode (a later PATCH of lat and lng) still wins because it writes
--      real values over the ZIP center.
--
-- A ZIP center is a mile or two off the real spot. Clients already see
-- coordinates rounded to two decimals (techs_public), so nothing leaks, and
-- for a mobile tech the ZIP center is the honest place to put her anyway.
--
-- Run AFTER sql/wh-travel-radius.sql and the zip-centroids files. Idempotent.
-- Re-run freely. Copy the whole file into a FRESH query. Proof this is the
-- new copy: the trigger is named wh_fill_pin_trg.

begin;

create or replace function public.wh_fill_pin() returns trigger
language plpgsql
set search_path = public
as $$
declare
  pt record;
begin
  if new.lat is not null and new.lng is not null then return new; end if;
  if coalesce(btrim(new.zip), '') = '' and coalesce(btrim(new.city), '') = '' then return new; end if;
  select q.lat, q.lng into pt
    from public.wh_point(null, null, new.zip, new.city, public.wh_state(new.state, new.zip)) q;
  if pt.lat is not null and pt.lng is not null then
    new.lat := pt.lat;
    new.lng := pt.lng;
  end if;
  return new;
end $$;

drop trigger if exists wh_fill_pin_trg on public.techs;
create trigger wh_fill_pin_trg before insert or update of zip, city, state, lat, lng on public.techs
  for each row execute function public.wh_fill_pin();

-- Backfill today's rows. The update fires the trigger, which does the fill;
-- the where clause keeps it to techs with no pin and something to place by.
update public.techs t
   set zip = t.zip
 where (t.lat is null or t.lng is null)
   and (coalesce(btrim(t.zip), '') <> '' or coalesce(btrim(t.city), '') <> '');

commit;

-- Checks (SQL editor, as the project owner):
--   Techs still without a pin (expect none, or only rows with no ZIP and no city):
--   select name, city, state, zip from public.techs where lat is null or lng is null;
--   The 14 from today, now placed at their ZIP centers:
--   select t.name, t.zip, round(t.lat::numeric, 3) as lat, round(t.lng::numeric, 3) as lng
--     from public.techs t join public.zip_centroids z on z.zip = left(regexp_replace(coalesce(t.zip, ''), '\D', '', 'g'), 5)
--    where t.lat = z.lat and t.lng = z.lng
--    order by t.name;
-- Then in the app as a guest: Near Me, Anywhere, count the pins.
