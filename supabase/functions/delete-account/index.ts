// Supabase Edge Function: delete-account
//
// Allows a signed-in user to delete their OWN account end-to-end. Required
// for Apple App Store Guideline 5.1.1(v) — apps that support account
// creation must offer in-app account deletion that doesn't require email,
// phone, or other customer-service rounds.
//
// Flow:
//   1. Verify the caller's JWT, extract their auth user_id + email.
//   2. Delete the user's rows from public schema in dependency order
//      (children before parents). Best-effort per row — collected errors
//      surface as warnings but don't abort the auth-user deletion, since
//      a stranded auth row is worse than an orphan public row.
//   3. Delete the auth.users row via admin.deleteUser. This invalidates
//      all active sessions for the user and is the irreversible step.
//   4. Return ok=true to the client. Client should immediately sign out
//      locally (the JWT is now dead) and route the user out of the app.
//
// Security model:
//   - This function NEVER reads a target user_id from the request body.
//     It only ever deletes the JWT-authenticated caller. Removes any
//     "delete-by-id" admin abuse vector — admins must use a separate
//     admin-side flow if they need to delete other users.
//   - Service-role key is used only for the admin operations
//     (auth.admin.deleteUser) where the anon key has no permission.
//
// Storage cleanup is NOT done here yet. The protect_delete() trigger
// blocks DELETE on storage.objects from SQL (per memory note
// reference_supabase_storage_delete_blocked.md), and cleaning storage
// requires per-object Storage API calls. For App Review compliance the
// data-row deletion + auth deletion is what matters; orphaned storage
// objects can be swept by a separate admin job later.
//
// Deploy with:
//   supabase functions deploy delete-account
//
// No extra secrets needed — SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
// are auto-populated by the Supabase runtime.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST')    return json({ error: 'POST only' }, 405);

  try {
    // ── Step 1: extract + verify caller's JWT ─────────────────────────────
    const auth = req.headers.get('Authorization') || '';
    const token = auth.replace(/^Bearer\s+/i, '');
    if (!token) return json({ error: 'missing auth token' }, 401);

    const anon = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: `Bearer ${token}` } } }
    );
    const { data: userRes, error: userErr } = await anon.auth.getUser(token);
    if (userErr || !userRes?.user) {
      return json({ error: 'invalid token' }, 401);
    }
    const userId = userRes.user.id;
    const userEmail = (userRes.user.email || '').toLowerCase();

    // ── Step 2: admin client for cross-table + auth deletion ──────────────
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const warnings: string[] = [];

    // Best-effort delete helper. We collect errors but don't throw —
    // a missing-table or an FK violation on one row should not block
    // deleting the auth.users row, which is the irreversible step Apple
    // is checking for. Stranded public-schema orphan rows can be cleaned
    // up by an admin sweep later if needed.
    async function bestEffortDelete(table: string, column: string, value: string) {
      try {
        const { error } = await admin.from(table).delete().eq(column, value);
        if (error) warnings.push(`${table}.${column}: ${error.message}`);
      } catch (e) {
        warnings.push(`${table}.${column}: ${String(e)}`);
      }
    }

    // Order: tables keyed by email or user_id first, then the parent
    // user row, then auth (irreversible) last.

    // push_subscriptions — keyed on auth user_id per project memory
    await bestEffortDelete('push_subscriptions', 'user_id', userId);

    // board_posts — feed posts authored by this tech (keyed by email)
    await bestEffortDelete('board_posts', 'tech_email', userEmail);

    // tech_comps — comped/grandfathered grant rows
    await bestEffortDelete('tech_comps', 'email', userEmail);

    // techs — main tech profile row (keyed by email)
    await bestEffortDelete('techs', 'email', userEmail);

    // users — base public.users row (keyed on auth.users.id per memory
    // note: project_mnc_push_notifications_wiring — user_id = public.users.id convention)
    await bestEffortDelete('users', 'id', userId);

    // ── Step 3: irreversible — delete the auth.users row ────────────────
    // This invalidates the caller's JWT immediately. After this, any
    // subsequent request from the same client with the same token will
    // 401. The client should treat ok=true as a signal to clear local
    // session state and navigate away from any signed-in screen.
    const { error: authErr } = await admin.auth.admin.deleteUser(userId);
    if (authErr) {
      // Auth deletion is the meaningful action — if it fails, the account
      // still effectively exists. Surface the error so the client can
      // tell the user something went wrong, and so they can retry.
      return json({
        ok: false,
        error: 'Could not delete account. Please contact support.',
        detail: authErr.message,
        warnings,
      }, 500);
    }

    return json({ ok: true, warnings: warnings.length ? warnings : undefined });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}
