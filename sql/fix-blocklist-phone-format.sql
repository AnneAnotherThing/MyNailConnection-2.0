-- ============================================================================
-- fix-blocklist-phone-format.sql  (2026-08-25)
--
-- BLOCKING A PHONE CLIENT HAS NEVER WORKED. Leslie found it.
--
-- Every enforcement point -- get_open_slots and _booking_gate -- decides with
-- an exact string compare:
--
--     public.phone_digits(bc.client_email) = public.current_phone()
--
-- current_phone() is the digits of the JWT phone claim, and Supabase's claim
-- carries the country code: '16025551234', ELEVEN digits. But the app wrote
-- the blocked number with the leading 1 deliberately STRIPPED:
--
--     if (d.length === 11 && d[0] === '1') d = d.slice(1);   // -> 6025551234
--
-- Ten digits can never equal eleven. So the row saved, the tech was told
-- "Blocked. They won't be told.", and the client went on seeing every
-- opening. The failure is completely silent on both sides -- there is no
-- error anywhere, which is why it survived this long.
--
-- The app now stores E.164 (+16025551234, eleven digits once phone_digits
-- strips the +), matching users.phone and techs.phone. This file repairs the
-- rows written before that.
--
-- Safe to re-run: the WHERE clause only matches un-migrated rows.
-- ============================================================================


-- ── 1. WHAT IS THERE NOW (read-only) ────────────────────────────────────────
select
  t.name                                   as tech,
  bc.client_email                          as blocked_entry,
  case
    when bc.client_email like '%@%'            then 'email — always worked'
    when bc.client_email ~ '^[0-9]{10}$'       then 'BARE 10 — never blocked anyone, will fix'
    when bc.client_email ~ '^\+?1[0-9]{10}$'   then 'E.164 — works'
    else                                            'unrecognised — look at this one'
  end                                      as state,
  bc.created_at
from public.blocked_clients bc
join public.techs t on t.id = bc.tech_id
order by bc.created_at desc;


-- ── 2. THE REPAIR ───────────────────────────────────────────────────────────
-- Bare 10 digits -> +1 and the same 10 digits. US-only, which is the same
-- assumption bkNormalizePhone() has always made app-side.
update public.blocked_clients
   set client_email = '+1' || client_email
 where client_email ~ '^[0-9]{10}$';

-- Bare 11 digits starting with 1 -> add the +, so phone_digits still yields
-- the same eleven digits and the entry reads consistently in the UI.
update public.blocked_clients
   set client_email = '+' || client_email
 where client_email ~ '^1[0-9]{10}$';


-- ── 3. PROVE IT MATCHES NOW ─────────────────────────────────────────────────
-- Every phone entry should report eleven digits, which is the shape
-- current_phone() produces. Anything else would still silently fail.
select
  bc.client_email,
  public.phone_digits(bc.client_email)              as compares_as,
  length(public.phone_digits(bc.client_email))      as digits,
  case when bc.client_email like '%@%' then 'n/a (email)'
       when length(public.phone_digits(bc.client_email)) = 11 then 'will match a caller'
       else 'STILL BROKEN' end                      as verdict
from public.blocked_clients bc
order by 4, 1;


-- ── 4. WHILE YOU ARE HERE: are the gates even installed? ────────────────────
-- If either says MISSING, the blocklist is off entirely for everyone and no
-- amount of formatting fixes it. Re-run booking-min-notice.sql (rev 2) and
-- tech-paywall-split.sql in that case.
select 'get_open_slots' as fn,
       case when prosrc like '%blocked_clients%' then 'blocklist gate present'
            else 'MISSING — re-run booking-min-notice.sql rev 2' end as state
from pg_proc where proname = 'get_open_slots' and pronamespace = 'public'::regnamespace
union all
select '_booking_gate',
       case when prosrc like '%blocked_clients%' then 'blocklist gate present'
            else 'MISSING — re-run tech-paywall-split.sql' end
from pg_proc where proname = '_booking_gate' and pronamespace = 'public'::regnamespace;
