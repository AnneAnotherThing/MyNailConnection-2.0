-- MNC Build 0, part 2 of 2: close the public read on techs.
--
-- RUN THIS LAST, and only after:
--   1. sql/build0-guest-lane.sql has been run (the view and RPCs exist).
--   2. The store build that reads techs_public has been live long enough
--      that installed phones have updated. Older builds still ask for
--      techs?select=* with the public key; after this file they get an
--      empty list and the Gallery goes blank for them.
--   3. The web /app gate also reads techs_public in that same deploy.
--
-- What changes:
--   - anon loses SELECT on public.techs entirely.
--   - authenticated users can read their OWN techs row (by email or phone
--     from the JWT) and admins can read every row. Clients browse through
--     techs_public and ask tech_contact() for a phone at tap time.
--   - Updates, inserts and deletes keep their existing policies.
--
-- Roll back: re-run the two lines at the bottom.

drop policy if exists techs_select_all on public.techs;
drop policy if exists techs_select_own_or_admin on public.techs;

create policy techs_select_own_or_admin on public.techs
  for select to authenticated
  using (
    (email is not null and lower(email) = public.current_email())
    or (length(coalesce(public.phone_digits(phone), '')) >= 10
        and length(coalesce(public.current_phone(), '')) >= 10
        and right(public.phone_digits(phone), 10) = right(public.current_phone(), 10))
    or public.is_admin()
  );

revoke select on public.techs from anon;

-- Probe from outside afterwards (expect [] or a 401/403, never a row):
--   curl -s -H "apikey: <anon>" -H "Authorization: Bearer <anon>" \
--     "https://nwqnakoongrorbwnrqzc.supabase.co/rest/v1/techs?select=email,phone,address&limit=1"
-- And the lane that must still work:
--   curl -s -H "apikey: <anon>" -H "Authorization: Bearer <anon>" \
--     "https://nwqnakoongrorbwnrqzc.supabase.co/rest/v1/techs_public?select=id,name,city&limit=1"

-- Roll back (restores the pre-Build-0 state):
--   create policy techs_select_all on public.techs for select using (true);
--   grant select on public.techs to anon;
