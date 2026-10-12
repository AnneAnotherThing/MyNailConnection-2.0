-- MNC techs: fill in city and state for the techs who have a ZIP but no city
-- or state (7 of 38 on 2026-10-11). Without them a tech lands under
-- Everywhere on What's happening and never gets a near-me push. The app now
-- requires both on save and shows a portal card until they are set; this
-- covers the rows that exist today.
--
-- Cities are from the ZIP. 86587 is not a real ZIP, so that row (Nail It
-- Forever) gets a state only; the portal card asks her for the city.
-- Idempotent: only blank fields change. Re-run freely.

begin;

-- The ZIP-to-state table said 201xx was DC; it is Northern Virginia. Corrected
-- copy of the function (same as sql/build2-whats-happening.sql).
create or replace function public.wh_state_from_zip(p_zip text) returns text
language sql immutable
set search_path = public
as $$
  select case
    when z is null then null
    when z between 5 and 5 then 'NY'
    when z between 6 and 9 then 'PR'
    when z between 10 and 27 then 'MA'
    when z between 28 and 29 then 'RI'
    when z between 30 and 38 then 'NH'
    when z between 39 and 49 then 'ME'
    when z = 55 then 'MA'
    when z between 50 and 59 then 'VT'
    when z between 60 and 69 then 'CT'
    when z between 70 and 89 then 'NJ'
    when z between 100 and 149 then 'NY'
    when z between 150 and 196 then 'PA'
    when z between 197 and 199 then 'DE'
    when z = 200 then 'DC'
    when z = 201 then 'VA'   -- Northern Virginia (Manassas, Dulles)
    when z between 202 and 205 then 'DC'
    when z between 206 and 219 then 'MD'
    when z between 220 and 246 then 'VA'
    when z between 247 and 268 then 'WV'
    when z between 270 and 289 then 'NC'
    when z between 290 and 299 then 'SC'
    when z between 300 and 319 then 'GA'
    when z between 320 and 349 then 'FL'
    when z between 350 and 369 then 'AL'
    when z between 370 and 385 then 'TN'
    when z between 386 and 397 then 'MS'
    when z between 398 and 399 then 'GA'
    when z between 400 and 427 then 'KY'
    when z between 430 and 459 then 'OH'
    when z between 460 and 479 then 'IN'
    when z between 480 and 499 then 'MI'
    when z between 500 and 528 then 'IA'
    when z between 530 and 549 then 'WI'
    when z between 550 and 567 then 'MN'
    when z = 569 then 'DC'
    when z between 570 and 577 then 'SD'
    when z between 580 and 588 then 'ND'
    when z between 590 and 599 then 'MT'
    when z between 600 and 629 then 'IL'
    when z between 630 and 658 then 'MO'
    when z between 660 and 679 then 'KS'
    when z between 680 and 693 then 'NE'
    when z between 700 and 714 then 'LA'
    when z between 716 and 729 then 'AR'
    when z between 730 and 749 then 'OK'
    when z = 885 then 'TX'
    when z between 750 and 799 then 'TX'
    when z between 800 and 816 then 'CO'
    when z between 820 and 831 then 'WY'
    when z between 832 and 838 then 'ID'
    when z between 840 and 847 then 'UT'
    when z between 850 and 865 then 'AZ'
    when z between 870 and 884 then 'NM'
    when z between 889 and 898 then 'NV'
    when z between 900 and 961 then 'CA'
    when z between 967 and 968 then 'HI'
    when z between 970 and 979 then 'OR'
    when z between 980 and 994 then 'WA'
    when z between 995 and 999 then 'AK'
    else null end
  from (select case when coalesce(p_zip, '') ~ '^\s*\d{5}' then substring(btrim(p_zip) from 1 for 3)::int end as z) x;
$$;

update public.techs
   set state = public.wh_state_from_zip(zip)
 where coalesce(btrim(state), '') = ''
   and public.wh_state_from_zip(zip) is not null;

update public.techs t
   set city = m.city
  from (values
    ('18201', 'Hazleton'),
    ('85379', 'Surprise'),
    ('85035', 'Phoenix'),
    ('85031', 'Phoenix'),
    ('20111', 'Manassas'),
    ('31047', 'Kathleen')
  ) as m(zip, city)
 where btrim(t.zip) = m.zip
   and coalesce(btrim(t.city), '') = '';

commit;

-- Check: should list only the 86587 row (city still blank).
--   select name, zip, city, state from public.techs
--    where coalesce(btrim(city), '') = '' or coalesce(btrim(state), '') = '';
