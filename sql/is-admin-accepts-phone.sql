-- ============================================================================
-- is_admin() ACCEPTS PHONE IDENTITY  (2026-07-24)
-- ============================================================================
-- The email-login door is hidden in the app as of today (Anne's call: no
-- active users yet, phone is THE identity). But is_admin() only accepted
-- the two admin EMAILS, so signing in by phone would silently drop Anne's
-- and Leslie's admin powers everywhere the RLS policies say "or is_admin()".
--
-- BEFORE RUNNING: replace ANNE_DIGITS and LESLIE_DIGITS with the real
-- 10-digit numbers (digits only, e.g. 4805551234).
--
-- Safe to re-run. Requires Stage A (public.current_phone).
-- ============================================================================

create or replace function public.is_admin() returns boolean
language sql stable security definer as $$
  select coalesce(
    (auth.jwt() ->> 'email') in (
      'annewilson1021@gmail.com',
      'leslie@mynailconnection.com'
      -- add more admin emails here, one per line, each ending with a comma
      -- except the last one.
    ),
    false
  )
  or coalesce(
    right(public.current_phone(), 10) in (
      'ANNE_DIGITS',
      'LESLIE_DIGITS'
      -- add more admin phones here, 10 digits each, comma-separated
    ),
    false
  );
$$;

-- ── Confirm (read-only): shows the definition now live ──────────────────────
select pg_get_functiondef('public.is_admin()'::regprocedure);
