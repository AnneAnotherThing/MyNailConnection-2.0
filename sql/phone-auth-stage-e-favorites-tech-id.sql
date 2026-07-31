-- ============================================================================
-- PHONE-AUTH, STAGE E: user_favorites keys the TECH on techs.id, not email
-- ============================================================================
-- THE BUG THIS FIXES
--   Stage A made techs.email optional (phone-first techs may have none), but
--   user_favorites still identifies the favorited tech with a TEXT column
--   called tech_email. The app papered over a missing email with
--   `currentTech.email || currentTech.name`, so favoriting a phone-only tech
--   stores their NAME in an email column. Two techs with the same name
--   collide, unfavorite deletes by that shared value, and the favorites list
--   can't resolve the row back to a tech profile.
--
-- THE FIX
--   techs.id (uuid, PK) identifies a tech no matter how they signed up and
--   survives them adding or changing an email later. Same move that
--   client-identity-user-id-migration.sql made for the USER side of this
--   table; this migration does the TECH side.
--
-- TRANSITION WINDOW
--   tech_email is KEPT and the app keeps writing it (the real email or null,
--   never the name fallback) because the popularity RPCs
--   (tech_fav_count/tech_fav_counts) still aggregate on it. Drop it in a
--   later migration once those move to tech_id, see the bottom of this file.
--
-- ORDER MATTERS: run this BEFORE deploying the app build that writes
--   tech_id, PostgREST 400s an INSERT naming a column that doesn't exist.
--
-- Safe to re-run. Adds a column, backfills, dedupes, indexes. No data loss.
-- Depends on: client-identity-user-id-migration.sql (user_id column + RLS,
-- already run; RLS keys on user_id only, so nothing here touches policies).
-- 2026-07-24
-- ============================================================================

begin;

-- ── 1. Add the real key ─────────────────────────────────────────────────────
alter table public.user_favorites
  add column if not exists tech_id uuid references public.techs(id) on delete cascade;

-- tech_email becomes transitional: phone-only techs have no email to store.
alter table public.user_favorites alter column tech_email drop not null;

-- ── 2. Backfill, pass 1: match on the tech's email ──────────────────────────
update public.user_favorites f
   set tech_id = t.id
  from public.techs t
 where f.tech_id is null
   and f.tech_email is not null
   and t.email is not null
   and lower(btrim(t.email)) = lower(btrim(f.tech_email));

-- ── 3. Backfill, pass 2: name fallback the app used to write ────────────────
-- Rows saved for a tech with no email hold the tech's NAME in tech_email.
-- Only claim a row when exactly ONE tech has that name, an ambiguous name
-- stays unmatched rather than guessing.
update public.user_favorites f
   set tech_id = t.id
  from public.techs t
 where f.tech_id is null
   and f.tech_email is not null
   and lower(btrim(t.name)) = lower(btrim(f.tech_email))
   and (select count(*) from public.techs t2
         where lower(btrim(t2.name)) = lower(btrim(f.tech_email))) = 1;

-- ── 4. Tell us what could not be matched ────────────────────────────────────
-- Leftovers point at a tech that no longer exists (deleted account, seed
-- data) or an ambiguous name. They keep working exactly as before via
-- tech_email; reported, not deleted.
do $$
declare n_orphans int;
begin
  select count(*) into n_orphans from public.user_favorites where tech_id is null;
  raise notice '── unmatched after backfill ──';
  raise notice '   user_favorites : % row(s) with no techs match', n_orphans;
  raise notice '   (inspect with the SELECT at the bottom of this file)';
end $$;

-- ── 5. Dedupe, then enforce one favorite per (user, tech) ───────────────────
-- The old email key had no uniqueness, so a user could hold duplicate rows
-- for one tech (e.g. saved under both email and name at different times,
-- now backfilled to the same tech_id). Keep the OLDEST row.
delete from public.user_favorites a
 using public.user_favorites b
 where a.user_id is not null and a.tech_id is not null
   and b.user_id = a.user_id and b.tech_id = a.tech_id
   and (b.created_at < a.created_at
        or (b.created_at = a.created_at and b.id < a.id));

create index if not exists user_favorites_tech_id_idx
  on public.user_favorites (tech_id);

create unique index if not exists user_favorites_user_tech_uniq
  on public.user_favorites (user_id, tech_id)
  where user_id is not null and tech_id is not null;

commit;

-- ============================================================================
-- INSPECT THE UNMATCHED ROWS (read-only, run separately)
-- ============================================================================
-- select tech_email, count(*) from public.user_favorites
--  where tech_id is null group by 1 order by 2 desc;

-- ============================================================================
-- LATER, once the popularity RPCs aggregate on tech_id and nothing has broken
-- ============================================================================
-- alter table public.user_favorites drop column tech_email;
-- Do NOT run this yet. tech_fav_count / tech_fav_counts still read it, and
-- it is the only record of who the unmatched rows above pointed at.
-- ============================================================================
