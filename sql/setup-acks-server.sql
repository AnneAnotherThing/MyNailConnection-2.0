-- MNC setup checklist: two choices move from the phone to the techs row
-- (Anne, 2026-10-11: "i have to keep selecting 'choose how clients reach you'
-- and 'tell clients when you have chair time' every time i log in again").
-- Sign-out wipes the device flags on purpose (shared phones), so the server
-- is the only place they can stick.
--
--   setup_calls_only  she chose calls and texts only, no booking link and no
--                     MNC booking (bkForkCallsOnly). Picking a link or MNC
--                     booking later clears it.
--   setup_avail_ack   she read the chair-time explainer (setupOpenAvailability).
--
-- Idempotent. Re-run freely. Techs update their own row through the existing
-- techs_update_self policy; no new grant needed.

begin;

alter table public.techs
  add column if not exists setup_calls_only boolean not null default false,
  add column if not exists setup_avail_ack  boolean not null default false;

commit;

-- Check, as 2314 after signing out and back in: the two steps stay ticked.
--   select setup_calls_only, setup_avail_ack from public.techs where phone like '%4402314';
