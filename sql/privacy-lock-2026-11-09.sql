-- MNC privacy lock, 2026-11-09 (board line c-privacyhole, contact half).
--
-- Closes the last two places a guest with the public key can read a
-- tech's contact details:
--   A. public.board_posts.tech_id still holds the tech's EMAIL on older
--      feed posts (19 of 50 rows on Nov 9), and the app still writes it
--      on every new post for techs who have an email on file.
--   B. public.techs is readable in full by anon and by every signed-in
--      user: email, phone, street address (even when the tech hid it),
--      exact lat/lng, last_password_change, billing dates.
--
-- This is the Build 0 step 4 lock (sql/build0-step4-revoke-public-techs.sql,
-- run once on 2026-10-10 and rolled back that night so phones on the
-- pre-techs_public store build kept their Gallery). Every store build since
-- 3.0.7 browses through techs_public, and 3.0.9 is released, so the gate
-- that held it back is cleared.
--
-- What keeps working, and why:
--   - Guest and client browse, Near Me map, profiles: public.techs_public
--     (owner-rights view, no email/phone/address, location rounded to two
--     decimals, stealth techs hidden). Not touched here.
--   - Call / Text / address on a profile: public.tech_contact(uuid), a
--     security definer RPC for signed-in users that drops the address when
--     the tech hid it. Not touched here.
--   - A signed-in tech reading and editing their own row: the new select
--     policy matches the JWT phone (or email) to the row. Updates keep the
--     existing techs_update_self policy.
--   - Admin (2314) screens and admin-stats: public.is_admin() in the policy.
--   - Booking, What's happening, push, webhooks, delete-account: service
--     role or security definer functions, which skip RLS.
--
-- HOW TO RUN: paste the whole file into the Supabase SQL editor for project
-- "My Nail Connection 3" (nwqnakoongrorbwnrqzc, NOT the 2.0 project) and
-- Run once. It runs as one transaction and checks itself at the end; if any
-- check fails it raises an error and nothing is changed.
--
-- ROLL BACK (techs only; restores today's open read):
--   create policy techs_select_all on public.techs for select using (true);
--   grant select on public.techs to anon;
-- Roll back (board_posts emails), only if a real need turns up:
--   update public.board_posts p set tech_id = b.tech_id
--     from private.board_posts_tech_id_backup b where b.id = p.id;
--   drop trigger if exists board_posts_strip_email on public.board_posts;

begin;

-- ── A. board_posts: email out of tech_id ───────────────────────────────

-- A1. Keep the old values somewhere the API cannot reach. The private
--     schema is not exposed by PostgREST, and anon/authenticated get no
--     rights on it.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.board_posts_tech_id_backup (
  id        uuid primary key,
  tech_id   text,
  saved_at  timestamptz not null default now()
);
revoke all on private.board_posts_tech_id_backup from public, anon, authenticated;

insert into private.board_posts_tech_id_backup (id, tech_id)
select p.id, p.tech_id
  from public.board_posts p
 where p.tech_id like '%@%'
on conflict (id) do nothing;

-- A2. Link any post that still only has the email (same match the
--     2026-09-04 backfill used), then clear the email.
update public.board_posts p
   set tech_uuid = t.id
  from public.techs t
 where p.tech_uuid is null
   and p.tech_id like '%@%'
   and t.email is not null
   and lower(btrim(t.email)) = lower(btrim(p.tech_id));

update public.board_posts
   set tech_id = null
 where tech_id like '%@%';

-- A3. Installed builds still send tech_id = email on a new post. Swap it
--     for the tech's id before the row is stored. Runs before the RLS
--     check, so the insert policy sees tech_uuid and passes on it.
create or replace function public.board_posts_strip_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.tech_id is not null and position('@' in new.tech_id) > 0 then
    if new.tech_uuid is null then
      select t.id into new.tech_uuid
        from public.techs t
       where t.email is not null
         and lower(btrim(t.email)) = lower(btrim(new.tech_id))
       limit 1;
    end if;
    new.tech_id := null;
  end if;
  return new;
end;
$$;
revoke all on function public.board_posts_strip_email() from public, anon, authenticated;

drop trigger if exists board_posts_strip_email on public.board_posts;
create trigger board_posts_strip_email
  before insert or update of tech_id on public.board_posts
  for each row execute function public.board_posts_strip_email();

-- ── B. techs: own row or admin only ────────────────────────────────────

drop policy if exists techs_select_all on public.techs;
drop policy if exists techs_select_own_or_admin on public.techs;

create policy techs_select_own_or_admin on public.techs
  for select to authenticated
  using (
    (email is not null and lower(email) = public.current_email())
    or (length(coalesce(public.phone_digits(phone), '')) >= 10
        and length(coalesce(public.current_phone(), '')) >= 10
        and right(public.phone_digits(phone), 10) = right(public.current_phone(), 10))
    or public.is_admin()
  );

revoke select on public.techs from anon;

-- ── C. Self-checks (raise, and roll everything back, if any fail) ──────

do $$
declare
  open_policies int;
  email_posts   int;
  public_rows   int;
begin
  if has_table_privilege('anon', 'public.techs', 'SELECT') then
    raise exception 'anon can still SELECT public.techs';
  end if;

  -- Any other permissive SELECT policy on techs would OR back open.
  select count(*) into open_policies
    from pg_policies
   where schemaname = 'public' and tablename = 'techs'
     and cmd in ('SELECT', 'ALL')
     and policyname <> 'techs_select_own_or_admin';
  if open_policies > 0 then
    raise exception 'techs still has % other SELECT policies, list them with: select policyname, roles, qual from pg_policies where tablename = ''techs''', open_policies;
  end if;

  select count(*) into email_posts from public.board_posts where tech_id like '%@%';
  if email_posts > 0 then
    raise exception 'board_posts still has % emails in tech_id', email_posts;
  end if;

  if not has_table_privilege('anon', 'public.techs_public', 'SELECT') then
    raise exception 'anon lost techs_public, browse would go blank';
  end if;
  select count(*) into public_rows from public.techs_public;
  if public_rows = 0 then
    raise exception 'techs_public returns no rows';
  end if;

  raise notice 'privacy lock OK: anon locked out of techs, % techs on techs_public, 0 emails in board_posts', public_rows;
end;
$$;

commit;

-- Probe from outside afterwards (Claude runs these after "ship it"):
--   techs?select=email,phone,address,lat,lng      expect 401, never a row
--   techs_public?select=id,name,city               expect the tech list
--   board_posts?select=tech_id                     expect no @ anywhere
