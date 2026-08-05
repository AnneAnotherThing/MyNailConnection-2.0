-- ============================================================================
-- PHONE-IDENTITY AUDIT FIXES (2026-08-03)
-- ============================================================================
-- From the full email-keying audit. Three fixes + two verifications.
-- Run in: Supabase dashboard → nwqnakoongrorbwnrqzc → SQL editor.
-- Safe to re-run.
--
-- ⚠ PREREQUISITE (discovered 2026-08-03 when this file first errored):
-- run sql/phone-auth-stage-e-favorites-tech-id.sql FIRST. It adds
-- user_favorites.tech_id, which section 2 joins on — and the app already
-- writes that column on every favorite-save, so until Stage E runs,
-- saving a favorite fails live for EVERYONE. Order: stage-e → this file.

begin;

-- ── 1. Contact Anne was fully blocked for phone-only users ──────────────────
-- camsg_insert_self checked lower(user_email) = current_email() only. A
-- phone session has current_email() NULL, so every insert failed. The app
-- writes the caller's phone string into user_email for phone users, so the
-- phone leg compares digits of that column against the JWT phone.
drop policy if exists camsg_insert_self on public.contact_anne_messages;
create policy camsg_insert_self on public.contact_anne_messages
  for insert to authenticated
  with check (
    lower(user_email) = public.current_email()
    or (public.current_phone() is not null
        and public.phone_digits(user_email) = public.current_phone())
  );

-- ── 2. Favorite counts for phone-only techs ─────────────────────────────────
-- tech_favorite_count(p_tech_email) can never match a tech whose email is
-- null. v2 resolves the tech by email OR phone digits and counts via the
-- uuid tech_id column that Stage E backfilled.
create or replace function public.tech_favorite_count_v2(p_key text)
returns integer
language sql stable security definer
set search_path = public
as $$
  select count(*)::int
  from public.user_favorites f
  join public.techs t on t.id = f.tech_id
  where p_key is not null and btrim(p_key) <> ''
    and (
      (t.email is not null and lower(t.email) = lower(btrim(p_key)))
      or (public.phone_digits(t.phone) is not null
          and public.phone_digits(t.phone) = public.phone_digits(p_key))
    );
$$;
grant execute on function public.tech_favorite_count_v2(text) to authenticated;
grant execute on function public.tech_favorite_count_v2(text) to anon;

-- ── 3. Photos-free hygiene NULL trap ────────────────────────────────────────
-- photos-free-3.0.sql cleared stale period_reset_at with
-- `email not in (select email from tech_comps)` — NULL email makes that
-- predicate NULL, so phone-only techs were never cleared and their first
-- upload window could be mis-anchored. Re-run with a NULL-safe shape.
update public.techs
   set period_reset_at = null
 where period_reset_at is not null
   and coalesce(period_upload_count, 0) = 0
   and (email is null
        or email not in (select email from public.tech_comps where email is not null));

commit;

-- ── Verification (read-only) ────────────────────────────────────────────────
-- V1: get_open_slots must contain the Stage-D blocklist leg. If this says
--     MISSING, rev 1 of booking-min-notice.sql clobbered rev 2's union and
--     BLOCKED PHONE CLIENTS CAN BOOK AGAIN — re-run booking-min-notice.sql
--     (rev 2) immediately.
select case when prosrc like '%blocked_clients%' and prosrc like '%listing_paused%'
            then 'OK — blocklist + pause gates present'
            else 'MISSING — re-run booking-min-notice.sql rev 2 NOW' end as get_open_slots_check
from pg_proc
where proname = 'get_open_slots' and pronamespace = 'public'::regnamespace;

-- V2: the new bits exist.
select 'camsg policy' as what,
       case when qual is null and with_check like '%current_phone%' then 'phone-aware ✓' else 'still email-only ✗' end as state
from pg_policies where tablename = 'contact_anne_messages' and policyname = 'camsg_insert_self'
union all
select 'fav count v2',
       case when count(*) > 0 then 'installed ✓' else 'missing ✗' end
from pg_proc where proname = 'tech_favorite_count_v2';
