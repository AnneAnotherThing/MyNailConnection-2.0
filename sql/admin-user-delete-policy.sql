-- ─────────────────────────────────────────────────────────────────────────
-- MNC — Admin DELETE policy on public.users
--
-- Bug found 2026-04-30 post-launch: admin "Delete user" in the admin
-- panel silently no-op'd. Two stacked causes:
--   1. Client used the anon key for the DELETE (now fixed in index.html
--      to send the admin's JWT).
--   2. No RLS policy on public.users allowed admin DELETE — there's a
--      `techs_delete_admin` on public.techs but its `users` counterpart
--      was never created. Even with the JWT fixed, the DELETE was being
--      rejected by RLS.
--
-- This migration adds the missing policy. Mirrors `techs_delete_admin`
-- exactly: only authenticated callers whose `is_admin()` returns true
-- can DELETE. Self-deletion is intentionally NOT allowed via this
-- policy — users delete their own account through the delete-account
-- edge function, which uses the service-role key end-to-end and also
-- removes the auth.users row (which RLS can't touch).
--
-- Safe to re-run.
-- Apply via Supabase SQL editor.
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists users_delete_admin on public.users;
create policy users_delete_admin
  on public.users
  for delete
  to authenticated
  using (public.is_admin());

comment on policy users_delete_admin on public.users is
  'Admins (per is_admin()) can delete any users row. Mirrors techs_delete_admin on public.techs. Required by the admin panel "Delete user" flow in index.html → deleteUser(). Does NOT cascade to auth.users — that requires service-role and currently must be done manually in the Supabase dashboard until an admin-side delete edge function exists.';
