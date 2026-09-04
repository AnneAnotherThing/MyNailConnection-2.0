-- ============================================================================
-- FEED + HEARTS FOR PHONE-ONLY TECHS: uuid keys on board_posts + user_inspo
-- ============================================================================
-- Found by the 2026-09-04 email-reliance sweep. Every tech who signed up
-- since the 2026-07-23 phone-only cutover:
--   * never appears on the home feed — the release wizard skipped the
--     board_posts insert for email-less techs (board_posts.tech_id is a
--     TEXT email and its RLS couldn't admit them), and the feed renderer
--     matched posts to techs by email anyway;
--   * shows "Posts: 0" forever on the Tech Portal (same email key);
--   * shows ♥ 0 forever — hearts on her photos are written with
--     user_inspo.tech_email = NULL, which no count can ever attribute.
--
-- THE FIX, same move as phone-auth-stage-e-favorites-tech-id.sql made for
-- user_favorites: key the tech by techs.id (uuid), which exists for every
-- tech no matter how they signed up.
--   1. board_posts.tech_uuid  (legacy tech_id TEXT email kept for old rows
--      and old app builds; RLS accepts either identity)
--   2. user_inspo.tech_id     (legacy tech_email kept, same reasons)
--   3. The four popularity RPCs (tech_fav_count/_counts,
--      tech_heart_count/_counts) are redefined IN PLACE with the same
--      names, signatures and return shapes: each incoming key (an email
--      OR a phone) resolves to a techs row and counts via the uuid
--      column, plus a legacy fallback for rows the backfill couldn't
--      claim. Old app builds calling them with emails keep working and
--      instantly gain phone support.
--
-- ⚠️ ORDER MATTERS: run this BEFORE deploying the app build that writes
--    tech_uuid / tech_id — PostgREST 400s an INSERT naming a column that
--    doesn't exist (same rule stage E had).
--
-- Hearts written between the cutover and this migration were stored with
-- tech_email NULL and cannot be attributed; they stay countable per-photo
-- (photo_heart_count is url-keyed) but not per-tech. Nothing to backfill.
--
-- Run in the Supabase SQL editor (nwqnakoongrorbwnrqzc). Safe to re-run.
-- Depends on: phone-auth stage A (current_email / current_phone /
-- phone_digits), stage E (user_favorites.tech_id), is_admin().
-- ============================================================================

begin;

-- ── 1. board_posts: the real key ────────────────────────────────────────────
alter table public.board_posts
  add column if not exists tech_uuid uuid references public.techs(id) on delete cascade;

-- Phone-only posts have no email to store in the legacy column.
alter table public.board_posts alter column tech_id drop not null;

-- Backfill: legacy rows key the tech by email.
update public.board_posts p
   set tech_uuid = t.id
  from public.techs t
 where p.tech_uuid is null
   and p.tech_id is not null
   and t.email is not null
   and lower(btrim(t.email)) = lower(btrim(p.tech_id));

create index if not exists board_posts_tech_uuid_idx
  on public.board_posts (tech_uuid);

-- RLS: self = legacy email match OR uuid match via email-or-phone identity.
-- (Replaces the stage-A policy whose phone leg selected the tech's EMAIL —
-- NULL for exactly the techs it was meant to rescue, so IN (NULL) never
-- admitted anyone.)
drop policy if exists board_insert_self on public.board_posts;
create policy board_insert_self on public.board_posts
  for insert to authenticated
  with check (
    (tech_id is not null and lower(tech_id) = public.current_email())
    or (tech_uuid is not null and tech_uuid in (
          select id from public.techs
           where (email is not null and lower(email) = public.current_email())
              or (public.phone_digits(phone) is not null
                  and public.phone_digits(phone) = public.current_phone())))
    or public.is_admin()
  );

drop policy if exists board_update_self on public.board_posts;
create policy board_update_self on public.board_posts
  for update to authenticated
  using (
    (tech_id is not null and lower(tech_id) = public.current_email())
    or (tech_uuid is not null and tech_uuid in (
          select id from public.techs
           where (email is not null and lower(email) = public.current_email())
              or (public.phone_digits(phone) is not null
                  and public.phone_digits(phone) = public.current_phone())))
    or public.is_admin()
  )
  with check (
    (tech_id is not null and lower(tech_id) = public.current_email())
    or (tech_uuid is not null and tech_uuid in (
          select id from public.techs
           where (email is not null and lower(email) = public.current_email())
              or (public.phone_digits(phone) is not null
                  and public.phone_digits(phone) = public.current_phone())))
    or public.is_admin()
  );

drop policy if exists board_delete_self on public.board_posts;
create policy board_delete_self on public.board_posts
  for delete to authenticated
  using (
    (tech_id is not null and lower(tech_id) = public.current_email())
    or (tech_uuid is not null and tech_uuid in (
          select id from public.techs
           where (email is not null and lower(email) = public.current_email())
              or (public.phone_digits(phone) is not null
                  and public.phone_digits(phone) = public.current_phone())))
    or public.is_admin()
  );

-- ── 2. user_inspo: the real tech key ────────────────────────────────────────
alter table public.user_inspo
  add column if not exists tech_id uuid references public.techs(id) on delete cascade;

update public.user_inspo i
   set tech_id = t.id
  from public.techs t
 where i.tech_id is null
   and i.tech_email is not null
   and t.email is not null
   and lower(btrim(t.email)) = lower(btrim(i.tech_email));

create index if not exists user_inspo_tech_id_idx
  on public.user_inspo (tech_id);

commit;


-- ── 3. Popularity RPCs, redefined in place ──────────────────────────────────
-- Resolve one text key (email or phone) to a techs row. A key whose digits
-- are shorter than 10 is never treated as a phone — emails contain digits
-- too ("tech123@…") and must not phone-match by accident.
create or replace function public._tech_id_for_key(p_key text)
returns uuid language sql stable security definer set search_path = public as $$
  select t.id from public.techs t
   where p_key is not null and btrim(p_key) <> ''
     and (   (t.email is not null and lower(btrim(t.email)) = lower(btrim(p_key)))
          or (length(coalesce(public.phone_digits(p_key), '')) >= 10
              and public.phone_digits(t.phone) = public.phone_digits(p_key)))
   limit 1;
$$;

create or replace function public.tech_fav_count(p_tech_email text)
  returns bigint language sql stable security definer set search_path = public as $$
  select (select count(*) from public.user_favorites f
           where f.tech_id is not null
             and f.tech_id = public._tech_id_for_key(p_tech_email))
       + (select count(*) from public.user_favorites f
           where f.tech_id is null and f.tech_email is not null
             and lower(btrim(f.tech_email)) = lower(btrim(coalesce(p_tech_email, ''))));
$$;

create or replace function public.tech_heart_count(p_tech_email text)
  returns bigint language sql stable security definer set search_path = public as $$
  select (select count(*) from public.user_inspo i
           where i.tech_id is not null
             and i.tech_id = public._tech_id_for_key(p_tech_email))
       + (select count(*) from public.user_inspo i
           where i.tech_id is null and i.tech_email is not null
             and lower(btrim(i.tech_email)) = lower(btrim(coalesce(p_tech_email, ''))));
$$;

-- Batch versions keep the (input-key, count) return shape: tech_email in
-- the result is the CALLER'S key verbatim-lowercased, exactly what the
-- app's cache expects, whether it was an email or a phone.
create or replace function public.tech_fav_counts(p_tech_emails text[])
  returns table(tech_email text, cnt bigint)
  language sql stable security definer set search_path = public as $$
  select lower(btrim(k)) as tech_email, public.tech_fav_count(k) as cnt
    from unnest(p_tech_emails) k
   where k is not null and btrim(k) <> '';
$$;

create or replace function public.tech_heart_counts(p_tech_emails text[])
  returns table(tech_email text, cnt bigint)
  language sql stable security definer set search_path = public as $$
  select lower(btrim(k)) as tech_email, public.tech_heart_count(k) as cnt
    from unnest(p_tech_emails) k
   where k is not null and btrim(k) <> '';
$$;

grant execute on function public._tech_id_for_key(text)      to anon, authenticated;
grant execute on function public.tech_fav_count(text)        to anon, authenticated;
grant execute on function public.tech_heart_count(text)      to anon, authenticated;
grant execute on function public.tech_fav_counts(text[])     to anon, authenticated;
grant execute on function public.tech_heart_counts(text[])   to anon, authenticated;


-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- 1. Columns exist:
select table_name, column_name from information_schema.columns
 where table_schema = 'public'
   and ((table_name = 'board_posts' and column_name = 'tech_uuid')
     or (table_name = 'user_inspo'  and column_name = 'tech_id'));

-- 2. Backfill coverage (unmatched = deleted techs / seed junk, fine to leave):
select 'board_posts' as t,
       count(*) filter (where tech_uuid is not null) as keyed,
       count(*) filter (where tech_uuid is null)     as unmatched
  from public.board_posts
union all
select 'user_inspo',
       count(*) filter (where tech_id is not null),
       count(*) filter (where tech_id is null)
  from public.user_inspo;

-- 3. RPCs resolve a phone key: pick any phone-only tech and run
--    select public.tech_heart_count('+1XXXXXXXXXX');
--    (0 is a legitimate answer; an error is not.)

-- 4. Policy sanity — all three board policies must name tech_uuid:
select polname from pg_policy p join pg_class c on c.oid = p.polrelid
 where c.relname = 'board_posts'
   and pg_get_expr(coalesce(p.polqual, p.polwithcheck), p.polrelid) not like '%tech_uuid%';
-- must return 0 rows (board_select_all has no self clause and won't appear).
