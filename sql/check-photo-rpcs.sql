-- MNC: read-only check before sql/photo-rpcs-owner-check.sql (2026-10-11).
-- Changes nothing. Paste the rows back to Claude.
-- Expected if live matches the repo:
--   append_tech_photo         body_md5 ad9a8fe3735b41373f2ed94ea93ec30b, has_hash_guard true
--   remove_tech_photo_by_url  body_md5 67014157f0b3abbf47e57fb269fcb18b
--   is_admin                  helper_body mentions u.admin

select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef as security_definer,
       md5(replace(p.prosrc, E'\r', '')) as body_md5,
       position('src_hash' in p.prosrc) > 0 as has_hash_guard,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_run,
       has_function_privilege('authenticated', p.oid, 'execute') as signed_in_can_run,
       case when p.proname not like '%photo%' then p.prosrc end as helper_body
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('append_tech_photo', 'remove_tech_photo_by_url', 'is_admin', 'current_email', 'current_phone', 'phone_digits')
 order by p.proname;
