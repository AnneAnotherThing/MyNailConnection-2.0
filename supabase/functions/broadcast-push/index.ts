// Supabase Edge Function: broadcast-push
// Admin-only. Sends a push notification to every active subscription
// whose user matches the requested audience ('all' | 'techs' | 'clients' |
// 'admins'):
//   - web/PWA rows  → Web Push (VAPID)   [p256dh = real key]
//   - Android rows  → FCM HTTP v1        [p256dh = 'native', auth = 'android']
//   - iOS rows      → APNs directly      [p256dh = 'native', auth = 'ios']
//     endpoint = the device token in every native case.
// Returns a count of sent/failed/skipped subscriptions.
//
// iOS goes straight to Apple, not through FCM, for the reason spelled out
// at the top of send-push: there is no Firebase SDK on iOS in this app, so
// Capacitor hands back a raw APNs token that FCM can never deliver to.
//
// Deploy with:
//   supabase functions deploy broadcast-push
//
// Requires the same secrets as send-push:
//   supabase secrets set VAPID_PRIVATE_KEY="<...>"
//   supabase secrets set VAPID_PUBLIC_KEY="<...>"
//   supabase secrets set VAPID_SUBJECT="mailto:admin@mynailconnection.com"
//   FCM_SERVICE_ACCOUNT  — full JSON of a Firebase service account
//     (Firebase console → Project settings → Service accounts →
//      Generate new private key). Without it, Android rows are skipped
//      with a 'skipped' count instead of erroring, so web push keeps
//      working during rollout.
//   APNS_PRIVATE_KEY / APNS_KEY_ID / APNS_TEAM_ID   — the .p8 contents,
//     its 10-char Key ID, and the 10-char Apple Team ID. Optional:
//     APNS_BUNDLE_ID (default com.mynailconnection.app) and APNS_ENV
//     ('production' default, or 'sandbox'). Without them iOS rows skip
//     the same way Android rows do without FCM.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const VAPID_PUBLIC_KEY  = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY')!;
const VAPID_SUBJECT     = Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@mynailconnection.com';

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

// Service-role client, reads across auth.users + public.users +
// push_subscriptions without RLS friction.
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ── FCM HTTP v1 ─────────────────────────────────────────────────────────────
// Google OAuth2 via service-account JWT, minted with WebCrypto (no SDK).
// Token cached at module scope; edge isolates live long enough for the
// cache to matter on bursts (a broadcast fans out to every device at once).
const FCM_SA_RAW = Deno.env.get('FCM_SERVICE_ACCOUNT') || '';
let _fcmToken: { token: string; exp: number } | null = null;

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function fcmAccessToken(): Promise<{ token: string; projectId: string } | null> {
  if (!FCM_SA_RAW) return null;
  const sa = JSON.parse(FCM_SA_RAW);
  const now = Math.floor(Date.now() / 1000);
  if (_fcmToken && _fcmToken.exp > now + 60) {
    return { token: _fcmToken.token, projectId: sa.project_id };
  }
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[A-Z ]+-----/g, '').replace(/\s/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = new Uint8Array(await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`)
  ));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${jwt}`,
  });
  if (!res.ok) throw new Error(`FCM token exchange failed: ${res.status} ${await res.text()}`);
  const j = await res.json();
  _fcmToken = { token: j.access_token, exp: now + (j.expires_in || 3600) };
  return { token: j.access_token, projectId: sa.project_id };
}

// deviceToken → FCM. Returns 'sent' | 'dead' (token invalid, delete row) |
// 'skipped' (FCM unconfigured) — anything else throws.
async function sendFcm(
  deviceToken: string, title: string, body: string, url: string, tag: string
): Promise<'sent' | 'dead' | 'skipped'> {
  const auth = await fcmAccessToken();
  if (!auth) return 'skipped';
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${auth.projectId}/messages:send`,
    {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${auth.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          notification: { title, body },
          data: { url, tag },
          android: { notification: { tag } },
          apns: { headers: { 'apns-collapse-id': tag.slice(0, 63) } },
        },
      }),
    }
  );
  if (res.ok) return 'sent';
  const text = await res.text();
  // UNREGISTERED / INVALID_ARGUMENT on a stale token → prune the row.
  if (res.status === 404 || text.includes('UNREGISTERED')) return 'dead';
  throw new Error(`FCM send failed: ${res.status} ${text}`);
}

// ── APNs, token-based, straight to Apple ────────────────────────────────────
// Kept byte-identical to the block in send-push. Both functions are
// paste-deployed from the dashboard, so a _shared import would break the
// paste; duplication is the deliberate trade. Change one, change both.
const APNS_KEY_ID      = Deno.env.get('APNS_KEY_ID')     || '';
const APNS_TEAM_ID     = Deno.env.get('APNS_TEAM_ID')    || '';
const APNS_PRIVATE_KEY = Deno.env.get('APNS_PRIVATE_KEY') || '';
const APNS_BUNDLE_ID   = Deno.env.get('APNS_BUNDLE_ID')  || 'com.mynailconnection.app';
const APNS_SANDBOX     = (Deno.env.get('APNS_ENV') || 'production').toLowerCase() === 'sandbox';
const APNS_HOST        = APNS_SANDBOX ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
const APNS_ALT_HOST    = APNS_SANDBOX ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';

let _apnsJwt: { token: string; iat: number } | null = null;

async function apnsJwt(): Promise<string | null> {
  if (!APNS_PRIVATE_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) return null;
  const now = Math.floor(Date.now() / 1000);
  // Apple rejects a provider token older than an hour (ExpiredProviderToken)
  // and rate-limits refreshes faster than every 20 minutes
  // (TooManyProviderTokenUpdates). 50 minutes sits safely between the two.
  if (_apnsJwt && now - _apnsJwt.iat < 50 * 60) return _apnsJwt.token;

  const header = b64url(JSON.stringify({ alg: 'ES256', kid: APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: APNS_TEAM_ID, iat: now }));
  const pem = APNS_PRIVATE_KEY.replace(/-----[A-Z ]+-----/g, '').replace(/\s/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']
  );
  // WebCrypto hands back the raw r||s pair that JWS ES256 wants. Do NOT
  // reach for a DER unwrap here — that's the OpenSSL shape, not this one.
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${header}.${claims}`)
  ));
  const token = `${header}.${claims}.${b64url(sig)}`;
  _apnsJwt = { token, iat: now };
  return token;
}

// deviceToken → APNs. Same contract as sendFcm: 'sent' | 'dead' (prune the
// row) | 'skipped' (no key configured). Anything else throws.
async function sendApns(
  deviceToken: string, title: string, body: string, url: string, tag: string
): Promise<'sent' | 'dead' | 'skipped'> {
  const jwt = await apnsJwt();
  if (!jwt) return 'skipped';

  const payload = JSON.stringify({
    aps: {
      alert: { title, body },
      sound: 'default',
      'thread-id': tag,
    },
    // Mirrors FCM's `data` block so pushNotificationActionPerformed reads
    // the same two fields whichever platform delivered the notification.
    url,
    tag,
  });

  const post = (host: string) => fetch(`${host}/3/device/${deviceToken}`, {
    method: 'POST',
    headers: {
      'authorization':    `bearer ${jwt}`,
      'apns-topic':       APNS_BUNDLE_ID,
      'apns-push-type':   'alert',
      // 10 = deliver now, don't wait for a battery window.
      'apns-priority':    '10',
      'apns-collapse-id': tag.slice(0, 64),
      'content-type':     'application/json',
    },
    body: payload,
  });

  let res  = await post(APNS_HOST);
  let text = res.ok ? '' : await res.text();

  // A token minted by a build signed for the OTHER APNs environment comes
  // back BadDeviceToken. Retry once on the other host rather than pruning a
  // subscription that is actually perfectly good.
  if (res.status === 400 && text.includes('BadDeviceToken')) {
    res  = await post(APNS_ALT_HOST);
    text = res.ok ? '' : await res.text();
  }

  if (res.ok) return 'sent';
  if (res.status === 410 || text.includes('BadDeviceToken') || text.includes('Unregistered')) {
    return 'dead';
  }
  throw new Error(`APNs send failed: ${res.status} ${text}`);
}

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
// If this check fails, return 403, never deliver a broadcast to an
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

  // Admin gate, non-admins never reach the push loop.
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

  // ── Send in parallel, clean up dead subs as we go ──────────────────────
  const effUrl = url || '/';
  const effTag = tag || ('mnc-broadcast-' + Date.now());
  const payload = JSON.stringify({ title, body, url: effUrl, tag: effTag });
  let sent = 0, failed = 0, skipped = 0;
  const skipReasons = new Set<string>();

  await Promise.all(targetSubs.map(async (sub) => {
    const isNative = sub.p256dh === 'native';
    // auth carries the platform on native rows ('ios' | 'android').
    const isApple  = isNative && String(sub.auth || '').toLowerCase() === 'ios';
    try {
      if (isNative) {
        const r = isApple
          ? await sendApns(sub.endpoint, title, body, effUrl, effTag)
          : await sendFcm(sub.endpoint, title, body, effUrl, effTag);
        if (r === 'sent') sent++;
        else if (r === 'skipped') {
          skipped++;
          skipReasons.add(isApple
            ? 'iOS rows skipped: APNS_PRIVATE_KEY / APNS_KEY_ID / APNS_TEAM_ID not all set'
            : 'Android rows skipped: FCM_SERVICE_ACCOUNT not set');
        }
        else {
          failed++;
          await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
        }
      } else {
        await webpush.sendNotification({
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth },
        }, payload);
        sent++;
      }
    } catch (err: any) {
      failed++;
      // Remove expired/invalid web subscriptions (410 Gone)
      if (!isNative && (err?.statusCode === 410 || err?.statusCode === 404)) {
        await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
      }
    }
  }));

  return jsonResponse(
    skipped
      ? { sent, failed, skipped, total_subs: targetSubs.length, audience, note: [...skipReasons].join('; ') }
      : { sent, failed, total_subs: targetSubs.length, audience }
  );
});
