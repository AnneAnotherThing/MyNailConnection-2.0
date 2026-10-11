-- MNC: stealth off and on for Anne's tech row (2314) around the Build 2 test
-- run's booking leg (2026-10-11). Stealth hides the row from every browse
-- surface except its owner and admins; the made-up client has to find her on
-- Near Me and in the Gallery to book her.
--
-- Run ONE statement at a time. The first one now, the second after cleanup.
-- Proof this is the right row: the name comes back as Anne Wilson.

-- 1. Before Part 4 of the test run: stealth OFF.
update public.techs set stealth = false
 where id = '029a4de3-75ba-4a05-8da6-8658c313e676'
returning id, name, stealth;

-- 2. After cleanup (Part 6): stealth back ON. Uncomment and run.
-- update public.techs set stealth = true
--  where id = '029a4de3-75ba-4a05-8da6-8658c313e676'
-- returning id, name, stealth;
