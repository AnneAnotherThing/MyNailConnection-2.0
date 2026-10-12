-- MNC 3.0.7 go-wide: near-me pushes reach every tech, not only admins.
-- Run AFTER 3.0.7 is on phones (Play and App Store rolled out), so a push
-- never points a tech at a board her installed build does not have.
-- Idempotent. Re-run freely.

update public.wh_settings set value = 'false' where key = 'near_push_admin_only';

-- Check: should say false.
select key, value from public.wh_settings where key = 'near_push_admin_only';

-- To pause it again later (testing, or a bad day):
--   update public.wh_settings set value = 'true' where key = 'near_push_admin_only';
