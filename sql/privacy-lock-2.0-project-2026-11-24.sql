-- MNC privacy lock for the RETIRED 2.0 project, 2026-11-24
-- (board line t1124-mnc-techs-table).
--
-- Project: ktiztunuifzbzwzyqrrq (the old 2.0 project).
-- NOT nwqnakoongrorbwnrqzc (3.0, live): that one was locked Nov 13
-- (sql/privacy-lock-2026-11-09.sql) and refuses guests on techs (401).
--
-- What was open on Nov 24, read with the public key and no sign-in:
--   public.techs        33 rows, every column: email, phone, street address,
--                       lat/lng, stripe_customer_id, apple_original_transaction_id,
--                       google_purchase_token, revenuecat_app_user_id, billing dates.
--   public.board_posts  16 rows, tech_id holds the tech's email on all 16.
--
-- Nothing live reads this project: mynailconnection.com, /app/ and every
-- deploy/ghpages file point at the 3.0 project. Only a phone still running a
-- pre-3.0 store build would, and after this lock such a phone can still sign
-- in and read its own tech row, but no longer browse other techs. That is
-- the intended trade: 3.0 store builds have been out since Aug 17.
--
-- HOW TO RUN: Supabase dashboard, open the OLD project (ktiztunuifzbzwzyqrrq,
-- the 2.0 one), SQL editor, paste this whole file, Run once. It is one
-- transaction and checks itself; if a check fails nothing changes.
--
-- ROLL BACK (only if a real need turns up):
--   grant select on public.techs, public.board_posts to anon, authenticated;
--   create policy techs_select_all on public.techs for select using (true);
--   create policy board_posts_select_all on public.board_posts for select using (true);

begin;

-- 1. Row level security on, for both tables.
alter table public.techs       enable row level security;
alter table public.board_posts enable row level security;

-- 2. Drop every existing SELECT (or ALL) policy on both, whatever its name,
--    so no old "using (true)" read survives.
do $$
declare p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('techs', 'board_posts')
      and cmd in ('SELECT', 'ALL')
  loop
    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end $$;

-- 3. Guests get nothing on either table. Signed-in users keep table rights
--    so the policies below decide which rows they see.
revoke all on public.techs       from anon;
revoke all on public.board_posts from anon;

-- 4. A signed-in tech reads only their own row (matched on the sign-in
--    email, which is how the 2.0 app looks a tech up).
create policy techs_select_own on public.techs
  for select to authenticated
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));

-- 5. A signed-in tech reads only their own feed posts.
create policy board_posts_select_own on public.board_posts
  for select to authenticated
  using (lower(tech_id) = lower(coalesce(auth.jwt() ->> 'email', '')));

-- 6. Self-checks. Any failure raises and rolls the whole file back.
do $$
begin
  if has_table_privilege('anon', 'public.techs', 'select') then
    raise exception 'check failed: anon can still select techs';
  end if;
  if has_table_privilege('anon', 'public.board_posts', 'select') then
    raise exception 'check failed: anon can still select board_posts';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename in ('techs', 'board_posts')
      and cmd in ('SELECT', 'ALL')
      and policyname not in ('techs_select_own', 'board_posts_select_own')
  ) then
    raise exception 'check failed: another read policy is still on techs or board_posts';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.techs'::regclass) then
    raise exception 'check failed: RLS is off on techs';
  end if;
end $$;

commit;

-- After it runs, the expected result is "Success. No rows returned."
-- Claude then re-reads both tables with the public key: both should answer 401.
