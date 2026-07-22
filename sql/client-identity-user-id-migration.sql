-- ============================================================================
-- MNC 3.0, CLIENT IDENTITY: key client-owned data on auth.uid(), not email
-- ============================================================================
-- THE BUG THIS FIXES
--   Booking moved to phone sign-in (Path A, Supabase Phone Auth). A phone-only
--   user has NO email claim in their JWT. But user_inspo and user_favorites
--   identify their owner with a TEXT column called `user_email`, and their RLS
--   policies compare it to current_email(), which reads that missing claim:
--
--       with check (lower(user_email) = public.current_email())
--
--   For a phone user current_email() is null, and `'+16025551234' = null` is
--   null, never true. So phone-signup clients would be able to book (bookings
--   key on client_id = auth.uid(), which is correct) but SILENTLY unable to
--   save inspo or favourites. Not yet hit in production only because Twilio
--   is not configured yet.
--
--   Worse, the app was already writing a phone number INTO a column named
--   user_email:  currentUserEmail = (user.email || user.phone)
--
-- THE FIX
--   auth.uid() is stable no matter how someone authenticated, survives a
--   client adding an email later, and survives a phone number change. It is
--   what bookings already uses. Bring the other two tables in line.
--
-- WHAT THIS DOES NOT DO
--   Does not create a clients table. public.users already is one, already
--   independent of techs, and already has id / phone / email / role.
--   Does not drop user_email. Kept as a nullable audit trail; drop it in a
--   later migration once you are confident, see the bottom of this file.
--
-- Safe to re-run. Adds a column, backfills, replaces policies. No data loss.
-- 2026-07-21
-- ============================================================================

begin;

-- ── 1. Add the real key ─────────────────────────────────────────────────────
alter table public.user_inspo
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

alter table public.user_favorites
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

-- ── 2. Backfill from whatever is sitting in user_email ──────────────────────
-- Two passes, because the app has been stuffing BOTH emails and phone numbers
-- into that column since the phone-auth pivot.
update public.user_inspo t
   set user_id = u.id
  from auth.users u
 where t.user_id is null
   and t.user_email is not null
   and lower(u.email) = lower(t.user_email);

update public.user_inspo t
   set user_id = u.id
  from auth.users u
 where t.user_id is null
   and t.user_email is not null
   and u.phone is not null
   and regexp_replace(u.phone, '\D', '', 'g') = regexp_replace(t.user_email, '\D', '', 'g');

update public.user_favorites t
   set user_id = u.id
  from auth.users u
 where t.user_id is null
   and t.user_email is not null
   and lower(u.email) = lower(t.user_email);

update public.user_favorites t
   set user_id = u.id
  from auth.users u
 where t.user_id is null
   and t.user_email is not null
   and u.phone is not null
   and regexp_replace(u.phone, '\D', '', 'g') = regexp_replace(t.user_email, '\D', '', 'g');

-- ── 3. Tell us what could not be matched ────────────────────────────────────
-- Rows left with a null user_id belong to an address with no auth user, i.e.
-- seed data (@mnc-seed.test) or an account that was deleted. Under the new
-- policies they are invisible to everyone except admin, which is correct:
-- nobody can prove they own them. Reported, not deleted. Your call.
do $$
declare i_orphans int; f_orphans int;
begin
  select count(*) into i_orphans from public.user_inspo     where user_id is null;
  select count(*) into f_orphans from public.user_favorites where user_id is null;
  raise notice '── unmatched after backfill ──';
  raise notice '   user_inspo     : % row(s) with no auth user', i_orphans;
  raise notice '   user_favorites : % row(s) with no auth user', f_orphans;
  raise notice '   (inspect with the SELECTs at the bottom of this file)';
end $$;

create index if not exists user_inspo_user_id_idx     on public.user_inspo (user_id);
create index if not exists user_favorites_user_id_idx on public.user_favorites (user_id);

-- ── 4. Repoint RLS at auth.uid() ────────────────────────────────────────────
drop policy if exists inspo_select_self on public.user_inspo;
drop policy if exists inspo_insert_self on public.user_inspo;
drop policy if exists inspo_update_self on public.user_inspo;
drop policy if exists inspo_delete_self on public.user_inspo;

alter table public.user_inspo enable row level security;
create policy inspo_select_self on public.user_inspo for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy inspo_insert_self on public.user_inspo for insert to authenticated
  with check (user_id = auth.uid() or public.is_admin());
create policy inspo_update_self on public.user_inspo for update to authenticated
  using  (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());
create policy inspo_delete_self on public.user_inspo for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists fav_select_self on public.user_favorites;
drop policy if exists fav_insert_self on public.user_favorites;
drop policy if exists fav_delete_self on public.user_favorites;
drop policy if exists fav_update_self on public.user_favorites;

alter table public.user_favorites enable row level security;
create policy fav_select_self on public.user_favorites for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy fav_insert_self on public.user_favorites for insert to authenticated
  with check (user_id = auth.uid() or public.is_admin());
create policy fav_update_self on public.user_favorites for update to authenticated
  using  (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());
create policy fav_delete_self on public.user_favorites for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- A tech legitimately needs the COUNT of who favourited them. That read is
-- owner-scoped above, so expose just the aggregate, no client identities.
create or replace function public.tech_favorite_count(p_tech_email text)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from public.user_favorites
   where lower(tech_email) = lower(p_tech_email);
$$;
grant execute on function public.tech_favorite_count(text) to anon, authenticated;

commit;

-- ============================================================================
-- INSPECT THE UNMATCHED ROWS (read-only, run separately)
-- ============================================================================
-- select user_email, count(*) from public.user_inspo
--  where user_id is null group by 1 order by 2 desc;
-- select user_email, count(*) from public.user_favorites
--  where user_id is null group by 1 order by 2 desc;

-- ============================================================================
-- LATER, once the app has been on user_id for a while and nothing has broken
-- ============================================================================
-- alter table public.user_inspo     drop column user_email;
-- alter table public.user_favorites drop column user_email;
-- Do NOT run this yet. It is one-way, and user_email is currently the only
-- record of who the unmatched rows above belonged to.
-- ============================================================================
