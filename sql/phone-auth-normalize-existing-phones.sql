-- ============================================================================
-- PHONE-AUTH: normalize existing phone numbers to E.164  (2026-07-23)
-- ============================================================================
-- Lets EXISTING accounts (Leslie + the onboarded techs, and any old clients)
-- sign in by phone. Their phones were stored as bare 10 digits ("6025021813"),
-- but phone login produces the full E.164 form ("+16025021813"). The app's
-- phone lookups and the dual-identity RLS both compare against E.164, so a
-- 10-digit stored value never matches, and the tech looks like a new user.
--
-- This rewrites every US 10-digit (or 11-digit leading-1) phone to +1XXXXXXXXXX
-- in public.techs and public.users. Values already in +1... form, or that
-- aren't a clean US number, are left alone. Safe to re-run.
-- ============================================================================

begin;

-- techs
update public.techs
   set phone = '+1' || regexp_replace(phone, '\D', '', 'g')
 where phone is not null
   and length(regexp_replace(phone, '\D', '', 'g')) = 10;

update public.techs
   set phone = '+' || regexp_replace(phone, '\D', '', 'g')
 where phone is not null
   and length(regexp_replace(phone, '\D', '', 'g')) = 11
   and left(regexp_replace(phone, '\D', '', 'g'), 1) = '1'
   and phone not like '+%';

-- users
update public.users
   set phone = '+1' || regexp_replace(phone, '\D', '', 'g')
 where phone is not null
   and length(regexp_replace(phone, '\D', '', 'g')) = 10;

update public.users
   set phone = '+' || regexp_replace(phone, '\D', '', 'g')
 where phone is not null
   and length(regexp_replace(phone, '\D', '', 'g')) = 11
   and left(regexp_replace(phone, '\D', '', 'g'), 1) = '1'
   and phone not like '+%';

commit;

-- ── Confirm (read-only) ─────────────────────────────────────────────────────
-- Every phone should now start with +1 and be 12 chars.
select 'techs' as tbl, phone from public.techs where phone is not null
union all
select 'users', phone from public.users where phone is not null
order by 1, 2;
