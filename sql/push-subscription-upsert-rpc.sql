-- ============================================================================
-- push-subscription-upsert-rpc.sql
--
-- Fixes: "Notification setup hit a snag (native save: 403)" — Anne, 2026-08-14,
-- hit while testing CLIENT notifications on a phone that had already registered
-- under a different account.
--
-- WHY 403 AND NOT 409:
--   The app writes push_subscriptions as an upsert on the unique `endpoint`
--   column (added 2026-08-03 to stop reinstall 409s, since FCM/APNs often hand
--   back the SAME device token). When that endpoint row already exists and
--   belongs to a DIFFERENT user_id, Postgres takes the ON CONFLICT branch and
--   runs an UPDATE. RLS evaluates push_update_self's USING clause against the
--   row AS IT EXISTS NOW — still owned by the previous account — so the check
--   fails and PostgREST returns 403 / 42501. push_insert_self never gets a say.
--
--   Net effect: a device can register for push exactly once, for one account,
--   ever. Every later account on that phone silently gets no subscription row,
--   which is exactly the "client never gets notifications" symptom.
--
-- THE FIX:
--   A SECURITY DEFINER function that (a) verifies the caller genuinely owns the
--   identity they're claiming, then (b) upserts/rebinds the endpoint with RLS
--   out of the way. Rebinding is the CORRECT behaviour: one physical device has
--   one push token, and it belongs to whoever is signed in on it right now. The
--   previous owner's row must go, or they'd keep receiving the new user's
--   notifications on a phone they no longer use.
--
-- Depends on: public.current_email(), public.current_phone(), public.is_admin()
--   (sql/rls-fix.sql + sql/phone-auth-stage-a-foundation.sql, already run).
--
-- Safe to re-run. Run this in the Supabase SQL editor.
-- ============================================================================

begin;

create or replace function public.save_push_subscription(
  p_user_id  text,
  p_endpoint text,
  p_p256dh   text,
  p_auth     text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := lower(trim(coalesce(p_user_id, '')));
begin
  if v_key = '' or coalesce(trim(p_endpoint), '') = '' then
    raise exception 'save_push_subscription: user_id and endpoint are required'
      using errcode = '22023';
  end if;

  -- Identity check. SECURITY DEFINER bypasses RLS, so this stands in for it:
  -- you may only claim an identity that is actually yours. Same three-way test
  -- the push_* policies use, kept deliberately identical so the two can't drift.
  --
  -- `is not true`, NOT `if not (...)`: current_email() is NULL for a phone-only
  -- account and current_phone() is NULL for an email account, so this OR can
  -- evaluate to NULL rather than false. RLS treats NULL as "denied" (a policy
  -- must be TRUE), but plpgsql's IF treats NULL as "don't take the branch" —
  -- which would have SKIPPED the raise and let anyone write any user's row.
  if (
       v_key = public.current_email()
    or public.phone_digits(v_key) = public.current_phone()
    or public.is_admin()
  ) is not true then
    raise exception 'save_push_subscription: % is not your identity', v_key
      using errcode = '42501';
  end if;

  -- Rebind: this endpoint belongs to exactly one account — whoever is signed in
  -- on the device now. Delete-then-insert rather than ON CONFLICT DO UPDATE so
  -- a stale row keyed to an old account can't survive on a partial match.
  delete from public.push_subscriptions where endpoint = p_endpoint;

  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, updated_at)
  values (v_key, p_endpoint, p_p256dh, p_auth, now());
end;
$$;

revoke all on function public.save_push_subscription(text, text, text, text) from public, anon;
grant execute on function public.save_push_subscription(text, text, text, text) to authenticated;

commit;

-- ============================================================================
-- VERIFY / TRIAGE
--
-- 1. Who currently owns rows, and are any native?
--      select user_id, p256dh as kind, auth as platform, updated_at
--        from public.push_subscriptions
--       order by updated_at desc limit 50;
--    p256dh = 'native' → FCM/APNs row (auth is 'ios' or 'android').
--    Anything else     → web-push row.
--
-- 2. Is the test client actually missing a row?
--      select * from public.push_subscriptions where lower(user_id) = 'client@example.com';
--
-- 3. Duplicate device bound to the wrong account (the 403 cause):
--      select endpoint, count(*), array_agg(distinct user_id)
--        from public.push_subscriptions group by endpoint having count(*) > 1;
--
-- 4. After deploying the app change, a fresh sign-in on the device should
--    produce a row keyed to the NEW account and no row for the old one.
--
-- NOTE: native rows only actually DELIVER if FCM_SERVICE_ACCOUNT is set on the
-- send-push edge function. Without it send-push reports
-- `note: 'native rows skipped: FCM_SERVICE_ACCOUNT not set'` and returns sent=0
-- with no error — a saved row is necessary but not sufficient.
-- ============================================================================
