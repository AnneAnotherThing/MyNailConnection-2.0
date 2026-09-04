-- ============================================================================
-- SWEEP FIXES, 2026-09-04: is_admin phone leg · feedback policies ·
-- tech_events_count phone-ready
-- ============================================================================
-- Closes the remaining server-side items from the 2026-09-04 email-reliance
-- sweep. Run in the Supabase SQL editor (nwqnakoongrorbwnrqzc). Idempotent.
-- Requires: phone-auth stage A (current_phone / phone_digits),
--           feed-hearts-phone-techs.sql (_tech_id_for_key).
-- ============================================================================


-- ── 1. is_admin(): match the caller by email OR verified phone ──────────────
-- The previous definition (admin-management-migration.sql) read ONLY the
-- JWT email claim, so a phone-only session could never be admin — every
-- admin policy (users, techs, notifications, push_log, contact messages,
-- manual-booking exemption, ~15 in all) silently denied it. Role compare is
-- also case-insensitive now: rows were seeded 'Admin' while two consumers
-- tested 'admin'.
--
-- Admin GRANTING is unchanged: a users row with role Admin. Anne's email
-- account keeps working exactly as before; if her phone identity shares
-- that users row (same row carries her phone), a phone-only session now
-- inherits admin too.
create or replace function public.is_admin() returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where lower(coalesce(u.role, '')) = 'admin'
      and (
        (coalesce(auth.jwt() ->> 'email', '') <> ''
         and lower(u.email) = lower(auth.jwt() ->> 'email'))
        or (coalesce(public.current_phone(), '') <> ''
            and public.phone_digits(u.phone) = public.current_phone())
      )
  );
$$;


-- ── 2. feedback: admin read/update via is_admin() ───────────────────────────
-- The originals inlined their own users lookup with TWO bugs: no lower()
-- on the email compare, and role = 'admin' (lowercase) against rows seeded
-- 'Admin' — so admin reads of feedback likely failed for everyone. Route
-- through is_admin(), which is now the single, phone-aware source of truth.
drop policy if exists feedback_select_admin on public.feedback;
create policy feedback_select_admin
  on public.feedback for select to authenticated
  using (public.is_admin());

drop policy if exists feedback_update_admin on public.feedback;
create policy feedback_update_admin
  on public.feedback for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());


-- ── 3. tech_events_count: phone-ready ───────────────────────────────────────
-- NOTE: nothing writes tech_events yet (popularity "foundation" that never
-- got a writer), so this is future-proofing, not a live fix. Same name and
-- signature; the key now resolves via email OR phone, and the tech-owner
-- privacy leg matches the caller's email OR verified phone against the
-- resolved techs row instead of email-only.
create or replace function public.tech_events_count(
  p_tech_email text,
  p_event_type text,
  p_since      timestamptz default (now() - interval '7 days')
) returns bigint
  language sql
  security definer
  set search_path = public
as $$
  with target as (
    select t.id, t.email, t.phone
      from public.techs t
     where t.id = public._tech_id_for_key(p_tech_email)
  )
  select count(*)
    from public.tech_events e, target t
   where lower(btrim(e.tech_email)) = lower(btrim(coalesce(t.email, p_tech_email)))
     and e.event_type = p_event_type
     and e.created_at >= p_since
     and (
       public.is_admin()
       or (coalesce(auth.jwt() ->> 'email', '') <> ''
           and lower(coalesce(t.email, '')) = lower(auth.jwt() ->> 'email'))
       or (coalesce(public.current_phone(), '') <> ''
           and public.phone_digits(t.phone) = public.current_phone())
     );
$$;

grant execute on function public.tech_events_count(text, text, timestamptz)
  to authenticated;


-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- 1. is_admin carries both identity legs and the case-insensitive role:
select case when prosrc like '%current_phone%' and prosrc like '%lower(coalesce(u.role%'
            then 'is_admin phone-aware ✓' else 'is_admin NOT updated' end as is_admin_state
  from pg_proc where proname = 'is_admin' and pronamespace = 'public'::regnamespace;

-- 2. Signed in as YOU (email account), this must return true:
--    select public.is_admin();

-- 3. Feedback policies route through is_admin (0 rows = pass):
select polname from pg_policy p join pg_class c on c.oid = p.polrelid
 where c.relname = 'feedback' and polname like 'feedback_%_admin'
   and pg_get_expr(coalesce(p.polqual, p.polwithcheck), p.polrelid) not like '%is_admin%';

-- 4. As admin, the feedback inbox should now actually return rows:
--    select created_at, category, left(message, 60) from public.feedback
--     order by created_at desc limit 10;
