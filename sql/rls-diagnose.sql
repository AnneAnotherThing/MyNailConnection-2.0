-- Run this and paste the output back. It lists every active RLS policy
-- on every public table, plus whether RLS is on.

select
  c.relname           as table_name,
  c.relrowsecurity    as rls_enabled,
  p.polname           as policy_name,
  case p.polpermissive when true then 'PERMISSIVE' else 'RESTRICTIVE' end as kind,
  case p.polcmd
    when 'r' then 'SELECT'
    when 'a' then 'INSERT'
    when 'w' then 'UPDATE'
    when 'd' then 'DELETE'
    when '*' then 'ALL'
  end                 as command,
  coalesce(
    (select string_agg(rolname, ', ')
     from pg_roles where oid = any(p.polroles)), 'public'
  )                   as applies_to,
  pg_get_expr(p.polqual,   p.polrelid)  as using_expr,
  pg_get_expr(p.polwithcheck, p.polrelid) as check_expr
from pg_policy p
join pg_class  c on c.oid = p.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
order by c.relname, p.polname;
