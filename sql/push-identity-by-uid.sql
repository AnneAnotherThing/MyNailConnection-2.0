-- ============================================================================
-- push-identity-by-uid.sql  (2026-09-19)
--
-- Make push_subscriptions ownership checks verify identity by auth.uid()
-- against the auth.users row directly, instead of the JWT claims
-- current_email() / current_phone().
--
-- WHY. A correctly-configured phone-only tech account (phone confirmed, no
-- email, single clean auth row with the E.164 phone) was rejected 42501 when
-- saving its native push token, while an identically-configured account
-- saved fine. The only thing that varies between two identical accounts is
-- runtime: what the live session token happens to carry. The old check
-- compares user_id against the token's phone/email CLAIMS, so any account
-- whose token does not present the phone the way the check expects (orphaned
-- identity, claim quirk, format) is silently denied. Reading auth.users by
-- auth.uid() is immune to all of that: it asks "does the signed-in account
-- actually own this identity?" straight from the source of truth.
--
-- ALSO: this removes the email dependency from the write path. Identity is a
-- phone (last-10, so +1 / country-code drift never matters); email still
-- works if present but is no longer required for anyone. A step toward
-- getting email out of identity entirely (Anne, 2026-09-19: "nothing tied to
-- email anymore").
--
-- Paste this whole file into the Supabase SQL editor (project
-- nwqnakoongrorbwnrqzc) and run it. Re-runnable. No app rebuild needed: the
-- app already calls save_push_subscription first and only falls back to a
-- direct insert (which this also re-gates) if the RPC is absent.
-- ============================================================================

-- ── 1. Owner check: does the CURRENT session own this identity string? ──────
-- Reads auth.users by auth.uid(), not the JWT claims. Phone compared on the
-- last 10 digits so "+14804402314" / "14804402314" / "4804402314" all agree.
-- security definer + explicit search_path so it can read auth.users regardless
-- of the caller.
create or replace function public.uid_owns_push_identity(p_identity text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = auth.uid()
      and (
        (u.email is not null
           and lower(u.email) = lower(trim(coalesce(p_identity, ''))))
        or
        (u.phone is not null
           and nullif(right(regexp_replace(u.phone, '\D', '', 'g'), 10), '')
             = nullif(right(regexp_replace(coalesce(p_identity, ''), '\D', '', 'g'), 10), ''))
      )
  );
$$;

revoke all on function public.uid_owns_push_identity(text) from public, anon;
grant execute on function public.uid_owns_push_identity(text) to authenticated;

comment on function public.uid_owns_push_identity(text) is
  'True if auth.uid() owns the given identity (email match, or phone last-10 match) read straight from auth.users. Replaces the JWT-claim identity test for push_subscriptions writes. 2026-09-19.';

-- ── 2. RPC: swap the identity gate to the uid-based check ───────────────────
-- Body unchanged except the gate. Still SECURITY DEFINER (bypasses RLS), so
-- this gate stands in for the policy and is kept identical to it below.
create or replace function public.save_push_subscription(
  p_user_id  text,
  p_endpoint text,
  p_p256dh   text,
  p_auth     text
) returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_key text := lower(trim(coalesce(p_user_id, '')));
begin
  if v_key = '' or coalesce(trim(p_endpoint), '') = '' then
    raise exception 'save_push_subscription: user_id and endpoint are required'
      using errcode = '22023';
  end if;

  -- You may only claim an identity your signed-in account actually owns.
  -- uid-based, so a phone-only account whose token does not surface the phone
  -- claim is still correctly recognized as the owner.
  if not (public.uid_owns_push_identity(v_key) or public.is_admin()) then
    raise exception 'save_push_subscription: % is not your identity', v_key
      using errcode = '42501';
  end if;

  -- Rebind: this endpoint belongs to exactly one account, whoever is signed in
  -- on the device now. Delete-then-insert so a stale row for an old account
  -- can't survive on a partial match.
  delete from public.push_subscriptions where endpoint = p_endpoint;

  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, updated_at)
  values (v_key, p_endpoint, p_p256dh, p_auth, now());
end;
$$;

revoke all on function public.save_push_subscription(text, text, text, text) from public, anon;
grant execute on function public.save_push_subscription(text, text, text, text) to authenticated;

-- ── 3. RLS policies (the direct-insert fallback path) ───────────────────────
-- Kept byte-for-byte in step with the RPC gate so the two can never drift.
drop policy if exists push_insert_self on public.push_subscriptions;
create policy push_insert_self on public.push_subscriptions for insert to authenticated
  with check (public.uid_owns_push_identity(user_id) or public.is_admin());

drop policy if exists push_update_self on public.push_subscriptions;
create policy push_update_self on public.push_subscriptions for update to authenticated
  using       (public.uid_owns_push_identity(user_id) or public.is_admin())
  with check  (public.uid_owns_push_identity(user_id) or public.is_admin());

drop policy if exists push_delete_self on public.push_subscriptions;
create policy push_delete_self on public.push_subscriptions for delete to authenticated
  using (public.uid_owns_push_identity(user_id) or public.is_admin());

drop policy if exists push_select_self on public.push_subscriptions;
create policy push_select_self on public.push_subscriptions for select to authenticated
  using (public.uid_owns_push_identity(user_id) or public.is_admin());

-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- After running, the tech account signs in on the device again and saves its
-- push token: the RPC path now recognizes it by uid. Then:
--   select auth, count(*) from public.push_subscriptions group by auth;
-- should show an ios row for the tech.
--
-- If it STILL returns 42501 for that account, the account's SESSION is riding
-- an auth.users row that does NOT carry that phone (a genuine orphan): the
-- next diagnostic build prints auth.uid() so we can point at it and repair the
-- data, rather than loosening the check further.
