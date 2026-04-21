// Supabase Edge Function: send-push
// Sends a Web Push notification to a user
//
// Deploy with:
//   supabase functions deploy send-push
//
// Set secrets:
//   supabase secrets set VAPID_PRIVATE_KEY="<your private key pem>"
//   supabase secrets set VAPID_PUBLIC_KEY="BINTHftWbkLsZZkNn0tafTXmhmgV6gvk46zmMeAC7wmJl5HWeUeWgGSoMDX9DRu7drBtS5XruZVPvduhoH4gSO4"
//   supabase secrets set VAPID_SUBJECT="mailto:admin@mynailconnection.com"

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

// Shared CORS headers — included on EVERY response so the browser never
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
    let sent = 0, failed = 0;

    for (const sub of subs) {
      try {
        await webpush.sendNotification({
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth }
        }, payload);
        sent++;
      } catch (err: any) {
        failed++;
        // Remove expired/invalid subscriptions (410 Gone)
        if (err.statusCode === 410 || err.statusCode === 404) {
          await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
        }
      }
    }

    return jsonResponse({ sent, failed });

  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});
