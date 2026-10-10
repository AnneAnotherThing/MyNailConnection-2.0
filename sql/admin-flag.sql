-- MNC: admin access by flag, separate from role.
-- Anne, 2026-10-10: every test identity opens the admin panel, Leslie included.
--
-- Why a flag and not role = 'Admin': the app routes on users.role at sign-in.
-- Flipping Leslie's role would land her on the admin home instead of her
-- Tech Portal every time she signs in. The flag leaves role alone, so the
-- app behaves exactly as before, while is_admin() (which gates admin-stats,
-- the admin RPCs and every admin RLS policy) says yes.
--
-- Idempotent. Re-run freely. Add a number to the list at the bottom to
-- grant, set the flag false to revoke.

begin;

alter table public.users add column if not exists admin boolean not null default false;
comment on column public.users.admin is 'Admin access without changing role. Read by public.is_admin(). Set by hand in SQL.';

create or replace function public.is_admin() returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where (lower(coalesce(u.role, '')) = 'admin' or coalesce(u.admin, false))
      and (
        (u.email is not null and lower(u.email) = public.current_email())
        or (length(coalesce(public.phone_digits(u.phone), '')) >= 10
            and length(coalesce(public.current_phone(), '')) >= 10
            and right(public.phone_digits(u.phone), 10) = right(public.current_phone(), 10))
      )
  );
$$;

-- The test identities (Supabase test phone numbers), by their last ten digits.
update public.users
   set admin = true
 where right(public.phone_digits(phone), 10) in (
   '4804402314',   -- Anne, admin
   '4806996166',   -- Anne, tech
   '6025021813',   -- Leslie, tech
   '5555550100'    -- MNC Test Client
 );

commit;

-- Check: every row below should show admin = true. A number missing from the
-- list has no users row yet; sign in with it once in the app and re-run.
select name, phone, role, admin
  from public.users
 where right(public.phone_digits(phone), 10) in ('4804402314','4806996166','6025021813','5555550100')
 order by name;
