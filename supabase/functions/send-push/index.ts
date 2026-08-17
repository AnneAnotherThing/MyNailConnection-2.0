// Supabase Edge Function: send-push
// Sends a push notification to every device a user has registered:
//   - web/PWA rows  → Web Push (VAPID)   [p256dh = real key]
//   - Android rows  → FCM HTTP v1        [p256dh = 'native', auth = 'android']
//   - iOS rows      → APNs directly      [p256dh = 'native', auth = 'ios']
//     endpoint = the device token in every native case.
//
// Why iOS does NOT go through FCM (2026-08-15): this app has no Firebase
// SDK on iOS — no GoogleService-Info.plist, no FirebaseMessaging pod, and
// an AppDelegate that hands the raw APNs token straight to the Capacitor
// plugin. Capacitor's own docs: "On iOS it contains the APNS token. On
// Android it contains the FCM token." FCM cannot deliver to a raw APNs
// token, so every iPhone push failed at this function rather than on the
// device. Talking to Apple directly fixes that with zero native changes.
//
// Deploy with:
//   supabase functions deploy send-push
//
// Secrets required:
//   VAPID_PRIVATE_KEY / VAPID_PUBLIC_KEY / VAPID_SUBJECT   (web push)
//   FCM_SERVICE_ACCOUNT  — full JSON of a Firebase service account
//     (Firebase console → Project settings → Service accounts →
//      Generate new private key). Without it, Android rows are skipped
//      with a reason instead of erroring, so web push keeps working.
//   APNS_PRIVATE_KEY  — the ENTIRE .p8 file, BEGIN/END lines included
//     (Apple Developer → Certificates, IDs & Profiles → Keys → a key
//      with Apple Push Notifications service enabled). Downloadable once.
//   APNS_KEY_ID   — 10-char Key ID of that .p8
//   APNS_TEAM_ID  — 10-char Apple Team ID
//   APNS_BUNDLE_ID — optional, defaults to com.mynailconnection.app
//   APNS_ENV       — optional, 'production' (default) or 'sandbox'
//     Without APNS_PRIVATE_KEY, iOS rows skip the same way Android rows
//     do without FCM. Nothing else changes.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const VAPID_PUBLIC_KEY  = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY')!;
const VAPID_SUBJECT     = Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@mynailconnection.com';

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// ── FCM HTTP v1 ─────────────────────────────────────────────────────────────
// Google OAuth2 via service-account JWT, minted with WebCrypto (no SDK).
// Token cached at module scope; edge isolates live long enough for the
// cache to matter on bursts (reminder crons fan out dozens of sends).
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
          // priority HIGH: bookings and confirmations must wake a dozing
          // phone overnight, not wait for the next maintenance window.
          android: { priority: 'HIGH', notification: { tag } },
          apns: { headers: { 'apns-collapse-id': tag.slice(0, 63), 'apns-priority': '10' } },
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
// Auth is a short ES256 JWT signed with the .p8 key: header carries the Key
// ID, claims carry the Team ID and an issue time. Signed with WebCrypto,
// same as the FCM token above, so there's no SDK to vendor.
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
  // and rate-limits refreshes that come faster than every 20 minutes
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
// row) | 'skipped' (no key configured). Anything else throws so the caller
// surfaces the real reason instead of a silent zero.
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
      // 10 = deliver now. A booking that lands overnight has to wake a
      // dozing phone, not wait for the next battery window.
      'apns-priority':    '10',
      'apns-collapse-id': tag.slice(0, 64),
      'content-type':     'application/json',
    },
    body: payload,
  });

  let res  = await post(APNS_HOST);
  let text = res.ok ? '' : await res.text();

  // A token minted by a build signed for the OTHER APNs environment comes
  // back BadDeviceToken. TestFlight and App Store builds are production; a
  // debug build straight from Xcode is sandbox. Retry once on the other host
  // rather than pruning a subscription that is actually perfectly good —
  // that mistake is invisible and costs the device its notifications until
  // the app is reinstalled.
  if (res.status === 400 && text.includes('BadDeviceToken')) {
    res  = await post(APNS_ALT_HOST);
    text = res.ok ? '' : await res.text();
  }

  if (res.ok) return 'sent';
  // 410 Unregistered and 400 BadDeviceToken are final on both hosts by this
  // point: the token will never work again, so drop the row.
  if (res.status === 410 || text.includes('BadDeviceToken') || text.includes('Unregistered')) {
    return 'dead';
  }
  throw new Error(`APNs send failed: ${res.status} ${text}`);
}

// Shared CORS headers, included on EVERY response so the browser never
// blocks the reply. Previous version only set these on the success path,
// which made 400 / no-subscriptions / 500 look like network failures on
// the client and produced a misleading "Couldn't reach Anne" error even
// when the server logic ran fine.
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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const { user_id, title, body, url, tag } = await req.json();

    if (!user_id || !title) {
      return jsonResponse({ error: 'user_id and title required' }, 400);
    }

    // Get all subscriptions for this user
    const { data: subs, error } = await supabase
      .from('push_subscriptions')
      .select('*')
      .eq('user_id', user_id);

    if (error || !subs?.length) {
      return jsonResponse({ sent: 0, reason: 'no subscriptions found' }, 200);
    }

    const payload = JSON.stringify({ title, body, url: url || '/', tag: tag || 'mnc' });
    let sent = 0, failed = 0, skipped = 0;
    const errors: string[] = [];
    const skipReasons = new Set<string>();

    for (const sub of subs) {
      const isNative = sub.p256dh === 'native';
      // auth carries the platform on native rows ('ios' | 'android').
      const isApple  = isNative && String(sub.auth || '').toLowerCase() === 'ios';
      try {
        if (isNative) {
          const r = isApple
            ? await sendApns(sub.endpoint, title, body || '', url || '/', tag || 'mnc')
            : await sendFcm(sub.endpoint, title, body || '', url || '/', tag || 'mnc');
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
            keys: { p256dh: sub.p256dh, auth: sub.auth }
          }, payload);
          sent++;
        }
      } catch (err: any) {
        failed++;
        // Surface WHY (2026-08-03): swallowing the error made FCM setup
        // problems (bad secret JSON, API disabled) indistinguishable from
        // dead tokens. Capped + deduped so the response stays small.
        const msg = String(err?.message || err).slice(0, 300);
        if (errors.length < 3 && !errors.includes(msg)) errors.push(msg);
        // Remove expired/invalid web subscriptions (410 Gone)
        if (!isNative && (err.statusCode === 410 || err.statusCode === 404)) {
          await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
        }
      }
    }

    return jsonResponse({
      sent, failed,
      ...(skipped ? { skipped, note: [...skipReasons].join('; ') } : {}),
      ...(errors.length ? { errors } : {}),
    });

  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});
