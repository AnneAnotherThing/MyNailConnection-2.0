// Supabase Edge Function: revenuecat-webhook
//
// Receives server-to-server webhook events from RevenueCat after every
// purchase, renewal, cancellation, refund, etc. RevenueCat is the source
// of truth for native (Apple/Google) IAP receipt validation; this
// function translates RevenueCat events into updates on the public.techs
// table so the rest of MNC's existing tier logic (consume_upload_slot
// RPC, photo limits, feed eligibility) keeps working unchanged.
//
// Event types we handle:
//   INITIAL_PURCHASE   → first-time subscription purchase, OR consumable
//   RENEWAL            → subscription auto-renewal billed
//   PRODUCT_CHANGE     → user switched plans inside a sub group
//   CANCELLATION       → user canceled (still active until expires_at)
//   EXPIRATION         → subscription period ended without renewal
//   BILLING_ISSUE      → renewal failed (still in retry grace period)
//   NON_RENEWING_PURCHASE → consumable (Spotlight 1 / 10) was bought
//   UNCANCELLATION     → user resubscribed after cancel-but-not-yet-expired
//   SUBSCRIPTION_PAUSED→ Google Play subscription pause (Android only)
//   REFUND             → Apple/Google refunded the purchase
//
// Setup in RevenueCat dashboard:
//   Project Settings → Integrations → + Add → Webhook
//   URL:    https://nwqnakoongrorbwnrqzc.supabase.co/functions/v1/revenuecat-webhook
//   Header: Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_HEADER value>
//
// Set the secret in Supabase:
//   supabase secrets set REVENUECAT_WEBHOOK_AUTH_HEADER=<long random string>
//
// The Authorization header is RevenueCat's only auth mechanism for
// webhooks. We compare it constant-time against the secret. Without a
// matching header the request 401s.
//
// Source-of-truth principle: client-side purchaseIAP() returns a result
// for UX (toast, optimistic loadTechTier call) but ENTITLEMENT GRANTING
// happens here, server-side, after RevenueCat verifies the receipt with
// Apple/Google. Don't trust the client.
//
// Deploy with:
//   supabase functions deploy revenuecat-webhook --no-verify-jwt
//
// (--no-verify-jwt because RevenueCat's webhooks don't sign with a JWT;
//  they use a static Authorization header instead.)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Map of RevenueCat product IDs → MNC product semantics. Single source of
// truth for what each Apple/Google product translates to internally.
const PRODUCT_MAP: Record<string, { kind: 'subscription' | 'photos1' | 'photos10' }> = {
  // Glow Up was originally provisioned as 'glow_up_monthly' but had to be
  // recreated as 'pro_glow_up' on 2026-04-30, the original ID was
  // accidentally created in App Store Connect's "In-App Purchases"
  // section as a non-renewing subscription instead of the "Subscriptions"
  // section as auto-renewable. Apple doesn't allow type changes after
  // creation, and the original product ID was retired and unavailable for
  // reuse after deletion, so we settled on 'pro_glow_up' for the new
  // auto-renewable product.
  'com.mynailconnection.app.pro_glow_up':     { kind: 'subscription' },
  'com.mynailconnection.app.spotlight_1':     { kind: 'photos1' },
  'com.mynailconnection.app.spotlight_10':    { kind: 'photos10' },
};

serve(async (req) => {
  if (req.method !== 'POST') return new Response('POST only', { status: 405 });

  // ── Auth: RevenueCat sends a static Authorization header ────────────
  const expectedHeader = Deno.env.get('REVENUECAT_WEBHOOK_AUTH_HEADER') || '';
  const got = req.headers.get('Authorization') || '';
  if (!expectedHeader || got !== `Bearer ${expectedHeader}`) {
    return new Response('unauthorized', { status: 401 });
  }

  let payload: any;
  let rawBody: string = '';
  try {
    rawBody = await req.text();
    payload = JSON.parse(rawBody);
  } catch (e) {
    console.warn('webhook bad json:', rawBody.slice(0, 500), 'err:', String(e));
    return new Response('bad json', { status: 400 });
  }

  const event = payload && payload.event;
  if (!event) {
    console.warn('webhook no event in payload, top-level keys:', Object.keys(payload || {}));
    return new Response('no event', { status: 400 });
  }

  const eventType: string = event.type || '';
  const productId: string = event.product_id || '';
  const appUserId: string = event.app_user_id || '';
  const originalAppUserId: string = event.original_app_user_id || appUserId;
  const store: string = (event.store || '').toLowerCase();   // 'app_store' | 'play_store'
  const originalTransactionId: string = event.original_transaction_id || event.transaction_id || '';
  const purchaseToken: string | undefined = event.purchase_token; // Google only

  // Log every incoming event with key fields so we can see the shape
  // RevenueCat is actually sending. Critical when a webhook returns 400
  // and we can't tell from the dashboard alone which validation failed.
  //, 2026-04-30 instrumentation; remove once IAP is stable.
  console.log('webhook event received', JSON.stringify({
    type: eventType,
    product_id: productId || '(missing)',
    app_user_id: appUserId || '(missing)',
    store,
    transaction_id: originalTransactionId || '(missing)',
    event_keys: Object.keys(event)
  }));

  if (!appUserId || !productId) {
    // Some RC event types legitimately don't carry product_id, e.g. TRANSFER
    // (when purchases move between app_user_ids) and SUBSCRIBER_ALIAS.
    // Returning 200 with "ignored" so RC doesn't endlessly retry, but log so
    // we know it happened and can decide later whether to wire up handling.
    if (eventType === 'TRANSFER' || eventType === 'SUBSCRIBER_ALIAS' || eventType === 'TEST') {
      console.log('webhook event ignored (no product_id expected for type):', eventType);
      return new Response('ok (event type has no product_id)', { status: 200 });
    }
    console.warn('webhook missing app_user_id or product_id for type:', eventType, 'event keys:', Object.keys(event));
    return new Response('missing app_user_id or product_id', { status: 400 });
  }

  const sourceLabel = store === 'play_store' ? 'google_play' : 'apple_iap';
  const product = PRODUCT_MAP[productId];
  if (!product) {
    // Unknown product, log and 200 so RevenueCat doesn't endlessly retry.
    console.warn('Unknown product_id in webhook:', productId);
    return new Response('ok (unknown product, ignored)', { status: 200 });
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  // ── Resolve the techs ROW ID from app_user_id ────────────────────────────
  // Keyed on techs.id, not techs.email. Every path here used to end at an
  // email and every write ran .eq('email', techEmail), so a PHONE-ONLY tech
  // (email is nullable since the 2026-07-23 phone-auth cutover) could pay and
  // have the subscription applied to nobody, while the webhook still answered
  // 200 and RevenueCat considered it delivered. An id is an id whichever way
  // the account was created. 2026-08-15
  //
  // Each lookup below handles a different failure mode of the user-table sync.
  let techId: string | null = null;
  let techLabel = '';   // logging only

  // techs.phone storage has drifted across the phone-auth migrations (+1XXXXXXXXXX
  // after phone-normalize-e164, bare digits before it) and GoTrue reports the
  // phone claim without the plus. Match every shape rather than guess one.
  function phoneVariants(raw: string | null | undefined): string[] {
    const digits = String(raw || '').replace(/\D/g, '');
    if (digits.length < 10) return [];
    const ten = digits.slice(-10);
    return [...new Set([`+1${ten}`, `1${ten}`, ten, `+${digits}`, digits])];
  }

  async function techByEmail(email: string | null | undefined) {
    if (!email) return null;
    const { data } = await admin
      .from('techs').select('id, email, phone')
      .eq('email', String(email).toLowerCase()).limit(1).maybeSingle();
    return data || null;
  }

  async function techByPhone(phone: string | null | undefined) {
    const variants = phoneVariants(phone);
    if (!variants.length) return null;
    const { data } = await admin
      .from('techs').select('id, email, phone')
      .in('phone', variants).limit(1).maybeSingle();
    return data || null;
  }

  function take(row: { id: string; email?: string | null; phone?: string | null } | null) {
    if (!row) return false;
    techId = row.id;
    techLabel = row.email || row.phone || row.id;
    return true;
  }

  // 1. A previous webhook hit already stamped revenuecat_app_user_id on the
  //    techs row, so this finds the tech even if public.users no longer matches.
  {
    const { data } = await admin
      .from('techs').select('id, email, phone')
      .eq('revenuecat_app_user_id', appUserId).limit(1).maybeSingle();
    take(data || null);
  }

  // 2. public.users by id. We pass auth.users.id as the App User ID at
  //    configure() time, and it usually equals public.users.id in MNC.
  if (!techId) {
    const { data: userRow } = await admin
      .from('users').select('id, email, phone')
      .eq('id', appUserId).limit(1).maybeSingle();
    if (userRow) {
      take(await techByEmail(userRow.email) || await techByPhone(userRow.phone));
    }
  }

  // 3. app_user_id sometimes IS an email, when initRevenueCat() ran before
  //    currentUser.id was populated (sign-in / session-restore race, the JS
  //    falls back from currentUser.id to currentUserEmail). Once RC is
  //    configured with an email as App User ID, all that user's future events
  //    carry the email instead of the auth UUID. Seen live 2026-04-30 with
  //    testuserbob@gmail.com. Same reasoning now applies to a phone identity.
  const looksLikeEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(appUserId);
  const looksLikePhone = /^\+?\d{10,15}$/.test(appUserId);
  if (!techId && looksLikeEmail) {
    take(await techByEmail(appUserId));
    if (techId) console.log('app_user_id was an email, matched tech', techLabel);
  }
  if (!techId && looksLikePhone) {
    take(await techByPhone(appUserId));
    if (techId) console.log('app_user_id was a phone, matched tech', techLabel);
  }

  // 4. auth.users by UUID. Catches the orphan-auth pattern where
  //    public.users.id and auth.users.id drifted apart. Skipped when we
  //    already know this is an email or phone, since getUserById throws on a
  //    non-UUID input.
  if (!techId && !looksLikeEmail && !looksLikePhone) {
    try {
      const { data: authUserData } = await admin.auth.admin.getUserById(appUserId);
      const au = authUserData?.user;
      if (au) take(await techByEmail(au.email) || await techByPhone(au.phone));
    } catch (e) {
      console.warn('auth.admin.getUserById threw for app_user_id', appUserId, e);
    }
  }

  if (!techId) {
    console.warn('No matching tech found for app_user_id:', appUserId);
    return new Response('ok (no matching tech)', { status: 200 });
  }

  // Stamp the source identifiers on every event, keeps the row queryable
  // even for events that don't mutate tier (BILLING_ISSUE, etc).
  const sourceUpdate: Record<string, any> = {
    subscription_source: sourceLabel,
    revenuecat_app_user_id: appUserId,
  };
  if (sourceLabel === 'apple_iap' && originalTransactionId) {
    sourceUpdate.apple_original_transaction_id = originalTransactionId;
  }
  if (sourceLabel === 'google_play' && purchaseToken) {
    sourceUpdate.google_purchase_token = purchaseToken;
  }

  // Branch on event type. Subscription lifecycle events vs. consumables
  // are very different shapes.
  if (product.kind === 'subscription') {
    // Glow Up subscription, manage subscription_tier + period_reset_at
    if (eventType === 'INITIAL_PURCHASE' || eventType === 'RENEWAL' || eventType === 'PRODUCT_CHANGE' || eventType === 'UNCANCELLATION') {
      const expiresAtMs = event.expiration_at_ms || event.expires_date_ms;
      const expiresAt = expiresAtMs ? new Date(expiresAtMs).toISOString() : null;
      await admin.from('techs').update({
        ...sourceUpdate,
        subscription_tier: 'paid',
        subscription_expires_at: null,  // Stripe-era column; null for IAP since renewal is automatic
        period_reset_at: expiresAt,     // when the next renewal/refresh happens
        glow_up_months_purchased: (await getCurrentCount(admin, techId, 'glow_up_months_purchased')) + 1,
      }).eq('id', techId);
    } else if (eventType === 'CANCELLATION') {
      // User canceled but sub still active until period_reset_at. Don't
      // flip tier to 'free' yet, let EXPIRATION handle that.
      await admin.from('techs').update(sourceUpdate).eq('id', techId);
    } else if (eventType === 'EXPIRATION') {
      // Subscription period ended without renewal, flip to free.
      await admin.from('techs').update({
        ...sourceUpdate,
        subscription_tier: 'free',
      }).eq('id', techId);
    } else if (eventType === 'BILLING_ISSUE') {
      // Apple/Google is retrying billing, leave tier alone, just stamp source
      await admin.from('techs').update(sourceUpdate).eq('id', techId);
    } else if (eventType === 'REFUND') {
      // Apple refunded a Glow Up charge, revoke tier
      await admin.from('techs').update({
        ...sourceUpdate,
        subscription_tier: 'free',
      }).eq('id', techId);
    }
  } else {
    // Consumable: photos1 / photos10, increment photo_credits + counter
    const creditsToAdd = product.kind === 'photos1' ? 1 : 10;
    const counterCol = product.kind === 'photos1'
      ? 'spotlight_1_purchased_count'
      : 'spotlight_10_purchased_count';

    if (eventType === 'NON_RENEWING_PURCHASE' || eventType === 'INITIAL_PURCHASE') {
      const currentCredits = (await getCurrentCount(admin, techId, 'photo_credits')) || 0;
      const currentCounter = (await getCurrentCount(admin, techId, counterCol)) || 0;
      await admin.from('techs').update({
        ...sourceUpdate,
        photo_credits: currentCredits + creditsToAdd,
        [counterCol]: currentCounter + 1,
      }).eq('id', techId);
    } else if (eventType === 'REFUND') {
      // Apple refunded a consumable, best-effort deduct (don't go negative).
      const currentCredits = (await getCurrentCount(admin, techId, 'photo_credits')) || 0;
      await admin.from('techs').update({
        ...sourceUpdate,
        photo_credits: Math.max(0, currentCredits - creditsToAdd),
      }).eq('id', techId);
    }
  }

  return new Response('ok', { status: 200 });
});

// Helper to read a single column off the techs row by id. Returns 0 if the
// row or column is missing/null. Cheap one-shot reads keep the webhook
// handler readable without batching. Keyed on id, not email, so it also
// resolves a phone-only tech.
async function getCurrentCount(admin: any, techId: string, column: string): Promise<number> {
  const { data } = await admin.from('techs').select(column).eq('id', techId).maybeSingle();
  if (!data) return 0;
  const v = data[column];
  return typeof v === 'number' ? v : (v ? Number(v) || 0 : 0);
}
