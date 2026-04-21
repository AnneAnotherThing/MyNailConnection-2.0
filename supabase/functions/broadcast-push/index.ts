// Supabase Edge Function: broadcast-push
// Admin-only. Sends a Web Push notification to every active subscription
// whose user matches the requested audience ('all' | 'techs' | 'clients' |
// 'admins'). Returns a count of sent/failed/no-subscription users.
//
// Deploy with:
//   supabase functions deploy broadcast-push
//
// Requires the same secrets as send-push:
//   supabase secrets set VAPID_PRIVATE_KEY="<...>"
//   supabase secrets set VAPID_PUBLIC_KEY="<...>"
//   supabase secrets set VAPID_SUBJECT="mailto:admin@mynailconnection.com"

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const VAPID_PUBLIC_KEY  = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY')!;
const VAPID_SUBJECT     = Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@mynailconnection.com';

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

// Service-role client — reads across auth.users + public.users +
// push_subscriptions without RLS friction.
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

// Verify the caller is an admin. Expects a Bearer JWT from the signed-in
// user. We decode the email claim and check public.users for role='admin'.
// If this check fails, return 403 — never deliver a broadcast to an
// unauthenticated / non-admin caller.
async function callerIsAdmin(req: Request): Promise<boolean> {
  try {
    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) return false;
    // Use supabase.auth.getUser with the token to pull the user object.
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data?.user?.email) return false;
    const email = data.user.email.toLowerCase();
    const { data: rows } = await supabase
      .from('users')
      .select('role')
      .eq('email', email)
      .limit(1);
    return !!(rows && rows[0] && rows[0].role === 'admin');
  } catch (_) {
    return false;
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }

  // Admin gate — non-admins never reach the push loop.
  if (!(await callerIsAdmin(req))) {
    return jsonResponse({ error: 'admin access required' }, 403);
  }

  let audience: string, title: string, body: string, url: string | undefined, tag: string | undefined;
  try {
    const payload = await req.json();
    audience = String(payload.audience || '').toLowerCase();
    title    = String(payload.title || '').trim();
    body     = String(payload.body || '').trim();
    url      = payload.url ? String(payload.url) : undefined;
    tag      = payload.tag ? String(payload.tag) : undefined;
  } catch (_) {
    return jsonResponse({ error: 'invalid JSON body' }, 400);
  }

  const VALID_AUDIENCES = new Set(['all', 'techs', 'clients', 'admins']);
  if (!VALID_AUDIENCES.has(audience)) {
    return jsonResponse({ error: "audience must be 'all' | 'techs' | 'clients' | 'admins'" }, 400);
  }
  if (!title) return jsonResponse({ error: 'title required' }, 400);
  if (!body)  return jsonResponse({ error: 'body required'  }, 400);

  // ── Resolve target auth.user_ids from audience ─────────────────────────
  // 'all' → every row in push_subscriptions.
  // role-scoped audiences → lookup emails in public.users, then map to
  // auth.users.id, then filter subscriptions by user_id.
  let targetSubs: Array<{ endpoint: string; p256dh: string; auth: string; user_id: string }> = [];

  if (audience === 'all') {
    const { data, error } = await supabase
      .from('push_subscriptions')
      .select('endpoint, p256dh, auth, user_id');
    if (error) return jsonResponse({ error: 'could not load subscriptions', detail: String(error) }, 500);
    targetSubs = data || [];
  } else {
    const role = audience === 'techs' ? 'tech' : audience === 'clients' ? 'client' : 'admin';
    // Step 1: emails of users with the target role.
    const { data: users, error: uerr } = await supabase
      .from('users')
      .select('email')
      .eq('role', role);
    if (uerr) return jsonResponse({ error: 'could not load users', detail: String(uerr) }, 500);
    const emails = (users || []).map(u => String(u.email || '').toLowerCase()).filter(Boolean);
    if (!emails.length) return jsonResponse({ sent: 0, failed: 0, total_subs: 0, reason: 'no users match audience' });

    // Step 2: auth.users.id for each email.
    // Supabase admin API is the cleanest path here.
    const userIds: string[] = [];
    for (const email of emails) {
      try {
        // paginate-by-email isn't supported directly; use listUsers with filter.
        // For modest N this is fine; at scale consider indexing.
        const { data: au, error } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1, email });
        if (!error && au?.users?.length) userIds.push(au.users[0].id);
      } catch (_) { /* continue */ }
    }
    if (!userIds.length) return jsonResponse({ sent: 0, failed: 0, total_subs: 0, reason: 'no auth users match' });

    // Step 3: push_subscriptions for those user_ids.
    const { data: subs, error: serr } = await supabase
      .from('push_subscriptions')
      .select('endpoint, p256dh, auth, user_id')
      .in('user_id', userIds);
    if (serr) return jsonResponse({ error: 'could not load subscriptions', detail: String(serr) }, 500);
    targetSubs = subs || [];
  }

  if (!targetSubs.length) {
    return jsonResponse({ sent: 0, failed: 0, total_subs: 0, reason: 'no push subscriptions found' });
  }

  // ── Send in parallel, clean up 410 Gone subs as we go ──────────────────
  const payload = JSON.stringify({ title, body, url: url || '/', tag: tag || ('mnc-broadcast-' + Date.now()) });
  let sent = 0, failed = 0;

  await Promise.all(targetSubs.map(async (sub) => {
    try {
      await webpush.sendNotification({
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth },
      }, payload);
      sent++;
    } catch (err: any) {
      failed++;
      if (err?.statusCode === 410 || err?.statusCode === 404) {
        await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
      }
    }
  }));

  return jsonResponse({ sent, failed, total_subs: targetSubs.length, audience });
});
