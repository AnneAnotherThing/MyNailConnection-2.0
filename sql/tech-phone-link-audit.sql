-- ============================================================================
-- tech-phone-link-audit.sql  (2026-09-20)
--
-- Phone-only login matches a tech by techs.phone in E.164. A tech whose row has
-- a null or non-E.164 phone will NOT match their own row on phone login, so they
-- lose their gallery (it lives in techs.photos on that row) and can create a
-- duplicate account. This audit buckets every tech so we know who is safe to
-- invite, who needs a normalize, and who needs their number found by hand.
--
-- Read-only. Paste into the Supabase SQL editor (project nwqnakoongrorbwnrqzc).
-- ============================================================================

-- Summary counts
select
  count(*)                                                                as total_techs,
  count(*) filter (where phone ~ '^\+[1-9][0-9]{9,14}$')                  as e164_ready,
  count(*) filter (where phone is not null and btrim(phone) <> ''
                     and phone !~ '^\+[1-9][0-9]{9,14}$')                 as needs_normalize,
  count(*) filter (where phone is null or btrim(phone) = '')              as no_phone_manual,
  count(*) filter (where jsonb_typeof(to_jsonb(photos)) = 'array'
                     and jsonb_array_length(to_jsonb(photos)) > 0)        as have_a_gallery
from public.techs;

-- Per-tech detail, worst first (the ones that will not match on phone login)
select
  name,
  email,
  phone,
  case
    when phone ~ '^\+[1-9][0-9]{9,14}$'                    then 'ready'
    when phone is not null and btrim(phone) <> ''          then 'needs normalize'
    else 'NO PHONE - manual'
  end                                                       as phone_state,
  coalesce(jsonb_array_length(to_jsonb(photos)), 0)         as photo_count
from public.techs
order by
  case
    when phone is null or btrim(phone) = ''      then 0    -- most urgent first
    when phone !~ '^\+[1-9][0-9]{9,14}$'         then 1
    else 2
  end,
  photo_count desc,
  name;
