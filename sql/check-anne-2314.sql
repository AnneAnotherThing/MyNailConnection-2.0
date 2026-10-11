-- MNC: read-only check that Anne's 480-440-2314 account is fully set up.
-- Expect one row per check, every "ok" column true.

select 'users row' as check_name,
       count(*) = 1 as ok,
       string_agg(coalesce(name,'') || ' / role=' || coalesce(role,'') || ' / admin=' || coalesce(admin::text,'null'), '; ') as detail
  from public.users
 where right(public.phone_digits(phone), 10) = '4804402314'
union all
select 'admin flag',
       bool_or(coalesce(admin,false) or lower(coalesce(role,'')) = 'admin'),
       null
  from public.users
 where right(public.phone_digits(phone), 10) = '4804402314'
union all
select 'tech row stealth',
       bool_and(coalesce(stealth,false)),
       string_agg(id::text || ' / ' || coalesce(name,''), '; ')
  from public.techs
 where right(public.phone_digits(phone), 10) = '4804402314'
union all
select 'signup RPC trusts JWT',
       bool_or(position('current_phone()' in pg_get_functiondef(p.oid)) > 0),
       count(*)::text || ' version(s)'
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'create_signup_profile_phone';
