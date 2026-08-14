-- ============================================================================
-- phone-normalize-e164.sql
--
-- Fixes: "I logged into 4804402314 as tech and my tags are gone" — Anne,
-- 2026-08-14. Not (only) a tags bug. The tech's whole row stopped resolving.
--
-- THE PROBLEM: two write formats, one exact-match read.
--
--   Writers disagreed on the shape of users.phone / techs.phone:
--     create_signup_profile_phone()  → '+14804402314'  (E.164, raw p_phone)
--     admin user-edit modal          → '4804402314'    (digits only)
--     booking flow                   → '4804402314'    (digits only)
--
--   But every profile lookup in index.html is an EXACT match:
--     /rest/v1/techs?or=(email.eq.X,phone.eq.X)
--   where X comes from mncIdentity(), which always yields the '+1…' form.
--
--   So a row written as digits-only can never be found by its own owner.
--   The tech signs in fine (auth.users is separate and holds E.164), lands on
--   the dashboard, and every fetch for their techs row returns []. Photos,
--   tags, bio, availability all render empty. It looks exactly like data loss.
--
--   The RLS policies were never affected — they compare with phone_digits()
--   on both sides, which is format-agnostic. Only the app's REST reads broke.
--   That's why this was invisible from the database side.
--
-- THE FIX: normalize the column itself, with a trigger, so it cannot drift
-- again no matter which writer touches it — app, admin modal, RPC, or a
-- hand-run UPDATE in the SQL editor. Reads then need no changes at all
-- (32 call sites left alone, which is the point).
--
-- Safe to re-run.
-- ============================================================================

begin;

-- ── Canonical form: '+1XXXXXXXXXX' for US 10-digit, '+<digits>' otherwise ──
-- NULL/blank stays NULL. Anything under 10 digits is left ALONE rather than
-- mangled — it's junk data and silently rewriting it would hide the problem.
create or replace function public.normalize_e164(p text) returns text
language sql immutable as $$
  select case
    when nullif(btrim(coalesce(p, '')), '') is null then null
    when length(regexp_replace(p, '\D', '', 'g')) = 10
      then '+1' || regexp_replace(p, '\D', '', 'g')
    when length(regexp_replace(p, '\D', '', 'g')) = 11
     and left(regexp_replace(p, '\D', '', 'g'), 1) = '1'
      then '+' || regexp_replace(p, '\D', '', 'g')
    when length(regexp_replace(p, '\D', '', 'g')) > 11
      then '+' || regexp_replace(p, '\D', '', 'g')
    else p
  end;
$$;

create or replace function public.tg_normalize_phone() returns trigger
language plpgsql as $$
begin
  new.phone := public.normalize_e164(new.phone);
  return new;
end;
$$;

drop trigger if exists users_normalize_phone on public.users;
create trigger users_normalize_phone
  before insert or update of phone on public.users
  for each row execute function public.tg_normalize_phone();

drop trigger if exists techs_normalize_phone on public.techs;
create trigger techs_normalize_phone
  before insert or update of phone on public.techs
  for each row execute function public.tg_normalize_phone();

commit;

-- ============================================================================
-- BACKFILL — run this SECOND, and read the collision check FIRST.
--
-- There is a UNIQUE constraint on phone. If the same person exists twice —
-- once as '4804402314' and once as '+14804402314' — normalizing collapses them
-- onto the same value and the UPDATE will fail with 23505. That is the correct
-- outcome: those are duplicate accounts and need a human decision about which
-- one survives. Do NOT work around it by dropping the constraint.
--
-- STEP 1 — find collisions (expect zero rows; if not, resolve before step 2):
--
--   select public.normalize_e164(phone) as normalized,
--          count(*), array_agg(id), array_agg(phone), array_agg(email)
--     from public.users
--    where phone is not null
--    group by 1 having count(*) > 1;
--
--   select public.normalize_e164(phone) as normalized,
--          count(*), array_agg(id), array_agg(phone), array_agg(email)
--     from public.techs
--    where phone is not null
--    group by 1 having count(*) > 1;
--
-- STEP 2 — see what will change (dry run):
--
--   select id, email, phone as before, public.normalize_e164(phone) as after
--     from public.techs
--    where phone is not null
--      and phone is distinct from public.normalize_e164(phone);
--
-- STEP 3 — apply:
--
--   update public.users set phone = phone
--    where phone is not null
--      and phone is distinct from public.normalize_e164(phone);
--
--   update public.techs set phone = phone
--    where phone is not null
--      and phone is distinct from public.normalize_e164(phone);
--
--   (`set phone = phone` looks like a no-op — the BEFORE trigger rewrites it.
--    That keeps the normalization logic in exactly one place.)
--
-- STEP 4 — verify Anne's tech specifically:
--
--   select id, name, email, phone, jsonb_array_length(photos) as photo_count
--     from public.techs where phone_digits(phone) = '4804402314';
--
--   If photo_count is 0, the photos really were lost and the tags need
--   re-entering. If it's non-zero, the row was just unreachable and
--   everything comes back as soon as phone is '+14804402314'.
--
--   Tag state per photo:
--     select p->>'url' as url, p->'tags' as tags
--       from public.techs t, jsonb_array_elements(t.photos) p
--      where phone_digits(t.phone) = '4804402314';
-- ============================================================================
