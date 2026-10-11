-- MNC: the notification badge and "Mark all read" count only your own.
-- Anne, 2026-10-11: her badge read 96 when she had 1 unread. notif_is_mine()
-- says yes to every row for an admin (so admins can read anyone's history),
-- and the unread count and both mark-read functions reused it. Result: an
-- admin's badge counted everyone's unread notifications, and an admin tapping
-- "Mark all read" marked EVERY user's notifications read. Admins now (2026-10-10)
-- include 2314 and Leslie.
--
-- notif_is_own() is the same check without the admin clause. The read
-- policies keep notif_is_mine(), so admins can still look at any history.
--
-- Idempotent. Re-run freely.

begin;

create or replace function public.notif_is_own(p_recipient text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (public.current_email() is not null and lower(p_recipient) = public.current_email())
      or (length(coalesce(public.current_phone(), '')) >= 10
          and right(public.phone_digits(p_recipient), 10) = right(public.current_phone(), 10));
$$;

create or replace function public.notifications_mark_read(p_ids bigint[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.notifications
     set read_at = now()
   where id = any(p_ids)
     and read_at is null
     and public.notif_is_own(recipient);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.notifications_mark_all_read()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.notifications
     set read_at = now()
   where read_at is null
     and public.notif_is_own(recipient);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.notifications_unread_count()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.notifications
   where read_at is null
     and public.notif_is_own(recipient);
$$;

revoke all on function public.notif_is_own(text) from public, anon;
revoke all on function public.notifications_mark_read(bigint[])   from public;
revoke all on function public.notifications_mark_all_read()       from public;
revoke all on function public.notifications_unread_count()        from public;
grant execute on function public.notifications_mark_read(bigint[]) to authenticated;
grant execute on function public.notifications_mark_all_read()     to authenticated;
grant execute on function public.notifications_unread_count()      to authenticated;

commit;

-- Check, signed in as 2314: select public.notifications_unread_count();  -- 1, not 96
