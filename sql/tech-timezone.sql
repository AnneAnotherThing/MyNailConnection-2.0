-- MNC: a tech's time zone follows where she is (Anne, 2026-10-13: "not
-- everyone is in AZ, their timezone needs to be set from their location
-- when they join").
--
-- Before this, techs.booking_timezone defaulted to America/Phoenix and
-- nothing set it at join; the only way off Phoenix was the "Use my device
-- timezone" link in Booking Settings. On 2026-10-13, 15 of the 16 techs
-- outside Arizona still said Phoenix. Everything that runs on her clock
-- read that column: the 8:00 AM "Open today?" push (11:00 AM for a
-- Virginia tech), the 9 PM to 7 AM quiet hours on near-me pushes (midnight
-- to 10 AM Eastern), the midnight availability reset, and the booking slot
-- grid once she turns booking on.
--
-- What this adds:
--   1. wh_tz_for_place(state, zip): the IANA zone for a US state, with the
--      split states (FL, ID, IN, KY, MI, NE, ND, OR, SD, TN, TX) resolved
--      by ZIP prefix. Null when it cannot tell.
--   2. techs.device_tz: the zone her phone reported last, for the record.
--   3. wh_fill_tz trigger: on insert, and when state or ZIP change, a tech
--      still on the Phoenix default outside Arizona gets her state's zone.
--      A zone she set herself in this same save is never touched.
--   4. tech_opened(p_tz): the once-a-day heartbeat now carries the phone's
--      zone. It is stored in device_tz, and if she is still on the Phoenix
--      default outside Arizona it becomes her booking_timezone. The phone
--      beats the state table because it is exact; after that first fill the
--      zone is hers and only Booking Settings changes it.
--   5. Backfill: every tech on the Phoenix default outside Arizona moves to
--      her state's zone now, so tonight's quiet hours and tomorrow's 8:00 AM
--      push are already right; her phone corrects the split-state cases the
--      next time she opens the app.
--
-- The app sends booking_timezone from the device on the signup insert too,
-- so a new tech is right from her first save.
--
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query. Proof
-- this is the new copy: the function is named wh_tz_for_place.

begin;

alter table public.techs add column if not exists device_tz text;
comment on column public.techs.device_tz is
  'IANA zone her device reported on the last daily heartbeat (tech_opened). Informational; booking_timezone is the one the clocks read.';

-- ── 1. State (and ZIP) to zone ───────────────────────────────────────────────
create or replace function public.wh_tz_for_place(p_state text, p_zip text) returns text
language plpgsql immutable
set search_path = public
as $$
declare
  st text := public.wh_state(p_state, p_zip);
  z3 int  := nullif(substr(regexp_replace(coalesce(p_zip, ''), '[^0-9]', '', 'g'), 1, 3), '')::int;
begin
  if st = '' then return null; end if;
  return case st
    -- one zone
    when 'AL' then 'America/Chicago'
    when 'AK' then 'America/Anchorage'
    when 'AZ' then 'America/Phoenix'
    when 'AR' then 'America/Chicago'
    when 'CA' then 'America/Los_Angeles'
    when 'CO' then 'America/Denver'
    when 'CT' then 'America/New_York'
    when 'DE' then 'America/New_York'
    when 'DC' then 'America/New_York'
    when 'GA' then 'America/New_York'
    when 'HI' then 'Pacific/Honolulu'
    when 'IL' then 'America/Chicago'
    when 'IA' then 'America/Chicago'
    when 'KS' then 'America/Chicago'
    when 'LA' then 'America/Chicago'
    when 'ME' then 'America/New_York'
    when 'MD' then 'America/New_York'
    when 'MA' then 'America/New_York'
    when 'MN' then 'America/Chicago'
    when 'MS' then 'America/Chicago'
    when 'MO' then 'America/Chicago'
    when 'MT' then 'America/Denver'
    when 'NV' then 'America/Los_Angeles'
    when 'NH' then 'America/New_York'
    when 'NJ' then 'America/New_York'
    when 'NM' then 'America/Denver'
    when 'NY' then 'America/New_York'
    when 'NC' then 'America/New_York'
    when 'OH' then 'America/New_York'
    when 'OK' then 'America/Chicago'
    when 'PA' then 'America/New_York'
    when 'RI' then 'America/New_York'
    when 'SC' then 'America/New_York'
    when 'UT' then 'America/Denver'
    when 'VT' then 'America/New_York'
    when 'VA' then 'America/New_York'
    when 'WA' then 'America/Los_Angeles'
    when 'WV' then 'America/New_York'
    when 'WI' then 'America/Chicago'
    when 'WY' then 'America/Denver'
    -- split states, by ZIP prefix; the phone corrects the edges
    when 'FL' then case when z3 between 324 and 325 then 'America/Chicago' else 'America/New_York' end
    when 'ID' then case when z3 = 838 then 'America/Los_Angeles' else 'America/Boise' end
    when 'IN' then case when z3 in (463, 464, 475, 476, 477) then 'America/Chicago' else 'America/Indiana/Indianapolis' end
    when 'KY' then case when z3 between 420 and 427 then 'America/Chicago' else 'America/New_York' end
    when 'MI' then case when z3 in (498, 499) then 'America/Menominee' else 'America/Detroit' end
    when 'NE' then case when z3 between 691 and 693 then 'America/Denver' else 'America/Chicago' end
    when 'ND' then case when z3 in (586) then 'America/Denver' else 'America/Chicago' end
    when 'OR' then case when z3 = 979 then 'America/Boise' else 'America/Los_Angeles' end
    when 'SD' then case when z3 between 575 and 577 then 'America/Denver' else 'America/Chicago' end
    when 'TN' then case when z3 in (373, 374, 376, 377, 378, 379) then 'America/New_York' else 'America/Chicago' end
    when 'TX' then case when z3 in (798, 799, 885) then 'America/Denver' else 'America/Chicago' end
    else null
  end;
end $$;

-- A zone name PostgreSQL accepts (the phone's Intl zone, usually).
create or replace function public.wh_tz_valid(p_tz text) returns boolean
language plpgsql immutable
set search_path = public
as $$
begin
  if coalesce(btrim(p_tz), '') = '' or length(p_tz) > 64 then return false; end if;
  perform now() at time zone p_tz;
  return true;
exception when others then
  return false;
end $$;

-- ── 3. Fill at join and on a move ────────────────────────────────────────────
create or replace function public.wh_fill_tz() returns trigger
language plpgsql
set search_path = public
as $$
declare
  z text;
begin
  -- She picked a zone in this very save: leave it alone.
  if tg_op = 'UPDATE' and new.booking_timezone is distinct from old.booking_timezone then return new; end if;
  -- Only the untouched default moves. A zone that is not Phoenix is hers.
  if coalesce(btrim(new.booking_timezone), '') not in ('', 'America/Phoenix') then return new; end if;
  if public.wh_state(new.state, new.zip) in ('', 'AZ') then return new; end if;
  z := public.wh_tz_for_place(new.state, new.zip);
  if z is not null then new.booking_timezone := z; end if;
  return new;
end $$;

drop trigger if exists wh_fill_tz_trg on public.techs;
create trigger wh_fill_tz_trg before insert or update of state, zip on public.techs
  for each row execute function public.wh_fill_tz();

-- ── 4. The heartbeat carries the phone's zone ───────────────────────────────
-- Replaces the zero-argument tech_opened from sql/tech-last-opened.sql. The
-- old one is dropped so PostgREST sees a single function; apps still in the
-- field call it with no arguments and land on the default.
drop function if exists public.tech_opened();
create or replace function public.tech_opened(p_tz text default null) returns boolean
language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid := (public.wh_my_tech()).id;
  v_tz text := btrim(coalesce(p_tz, ''));
begin
  if v_id is null then return false; end if;
  if v_tz <> '' and public.wh_tz_valid(v_tz) then
    update public.techs t
       set last_opened_at = now(),
           device_tz = v_tz,
           booking_timezone = case
             when coalesce(btrim(t.booking_timezone), '') in ('', 'America/Phoenix')
              and v_tz <> 'America/Phoenix'
              and public.wh_state(t.state, t.zip) <> 'AZ'
             then v_tz
             else t.booking_timezone end
     where t.id = v_id;
  else
    update public.techs set last_opened_at = now() where id = v_id;
  end if;
  return true;
end $$;

revoke all on function public.tech_opened(text) from public, anon;
grant execute on function public.tech_opened(text) to authenticated;

-- ── 5. Backfill today's rows ─────────────────────────────────────────────────
update public.techs t
   set booking_timezone = public.wh_tz_for_place(t.state, t.zip)
 where coalesce(btrim(t.booking_timezone), '') in ('', 'America/Phoenix')
   and public.wh_state(t.state, t.zip) not in ('', 'AZ')
   and public.wh_tz_for_place(t.state, t.zip) is not null;

commit;

-- Checks (SQL editor, as the project owner):
--   select public.wh_state(state, zip) as st, booking_timezone, count(*)
--     from public.techs group by 1, 2 order by 1, 2;      -- no non-AZ row on Phoenix
--   select name, state, zip, booking_timezone, device_tz, last_opened_at
--     from public.techs where public.wh_state(state, zip) <> 'AZ' order by state;
--   Then open the app as 2314 (Tech Portal): device_tz fills for 2314 and
--   booking_timezone stays America/Phoenix (AZ never moves).
