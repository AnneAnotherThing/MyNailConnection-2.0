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
//   URL:    https://ktiztunuifzbzwzyqrrq.supabase.co/functions/v1/revenuecat-webhook
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
  // recreated as 'pro_glow_up' on 2026-04-30 — the original ID was
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
  try { payload = await req.json(); }
  catch { return new Response('bad json', { status: 400 }); }

  const event = payload && payload.event;
  if (!event) return new Response('no event', { status: 400 });

  const eventType: string = event.type || '';
  const productId: string = event.product_id || '';
  const appUserId: string = event.app_user_id || '';
  const originalAppUserId: string = event.original_app_user_id || appUserId;
  const store: string = (event.store || '').toLowerCase();   // 'app_store' | 'play_store'
  const originalTransactionId: string = event.original_transaction_id || event.transaction_id || '';
  const purchaseToken: string | undefined = event.purchase_token; // Google only

  if (!appUserId || !productId) {
    return new Response('missing app_user_id or product_id', { status: 400 });
  }

  const sourceLabel = store === 'play_store' ? 'google_play' : 'apple_iap';
  const product = PRODUCT_MAP[productId];
  if (!product) {
    // Unknown product — log and 200 so RevenueCat doesn't endlessly retry.
    console.warn('Unknown product_id in webhook:', productId);
    return new Response('ok (unknown product, ignored)', { status: 200 });
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  // Resolve the techs row from app_user_id. We use auth.users.id as the
  // RevenueCat App User ID at configure() time, so app_user_id should
  // match auth.users.id (which usually equals public.users.id in MNC).
  // Three lookup paths in order of preference, each handling a different
  // failure mode of the user-table sync:
  const { data: userRow } = await admin
    .from('users')
    .select('id, email')
    .eq('id', appUserId)
    .single();

  let techEmail: string | null = userRow?.email?.toLowerCase() || null;

  // Fallback 1: a previous webhook hit already stamped revenuecat_app_user_id
  // on the techs row, so we can find the tech by that id even if public.users
  // no longer matches.
  if (!techEmail) {
    const { data: techRow } = await admin
      .from('techs')
      .select('email')
      .eq('revenuecat_app_user_id', appUserId)
      .maybeSingle();
    techEmail = techRow?.email?.toLowerCase() || null;
  }

  // Fallback 2: query auth.users directly. The app_user_id IS auth.users.id
  // (set at Purchases.configure time from currentUser.id), so this lookup
  // can't miss for any signed-in purchaser. Catches the orphan-auth pattern
  // where public.users.id and auth.users.id drifted apart (account
  // recreation, manual data fixes, stale signups). Source of truth for
  // app_user_id → email mapping. — added 2026-04-30 after a TestFlight test
  // surfaced the drift on a recreated test account.
  if (!techEmail) {
    try {
      const { data: authUserData } = await admin.auth.admin.getUserById(appUserId);
      techEmail = authUserData?.user?.email?.toLowerCase() || null;
    } catch (e) {
      console.warn('auth.admin.getUserById threw for app_user_id', appUserId, e);
    }
  }

  if (!techEmail) {
    console.warn('No matching tech found for app_user_id:', appUserId);
    return new Response('ok (no matching tech)', { status: 200 });
  }

  // Stamp the source identifiers on every event — keeps the row queryable
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
    // Glow Up subscription — manage subscription_tier + period_reset_at
    if (eventType === 'INITIAL_PURCHASE' || eventType === 'RENEWAL' || eventType === 'PRODUCT_CHANGE' || eventType === 'UNCANCELLATION') {
      const expiresAtMs = event.expiration_at_ms || event.expires_date_ms;
      const expiresAt = expiresAtMs ? new Date(expiresAtMs).toISOString() : null;
      await admin.from('techs').update({
        ...sourceUpdate,
        subscription_tier: 'paid',
        subscription_expires_at: null,  // Stripe-era column; null for IAP since renewal is automatic
        period_reset_at: expiresAt,     // when the next renewal/refresh happens
        glow_up_months_purchased: (await getCurrentCount(admin, techEmail, 'glow_up_months_purchased')) + 1,
      }).eq('email', techEmail);
    } else if (eventType === 'CANCELLATION') {
      // User canceled but sub still active until period_reset_at. Don't
      // flip tier to 'free' yet — let EXPIRATION handle that.
      await admin.from('techs').update(sourceUpdate).eq('email', techEmail);
    } else if (eventType === 'EXPIRATION') {
      // Subscription period ended without renewal — flip to free.
      await admin.from('techs').update({
        ...sourceUpdate,
        subscription_tier: 'free',
      }).eq('email', techEmail);
    } else if (eventType === 'BILLING_ISSUE') {
      // Apple/Google is retrying billing — leave tier alone, just stamp source
      await admin.from('techs').update(sourceUpdate).eq('email', techEmail);
    } else if (eventType === 'REFUND') {
      // Apple refunded a Glow Up charge — revoke tier
      await admin.from('techs').update({
        ...sourceUpdate,
        subscription_tier: 'free',
      }).eq('email', techEmail);
    }
  } else {
    // Consumable: photos1 / photos10 — increment photo_credits + counter
    const creditsToAdd = product.kind === 'photos1' ? 1 : 10;
    const counterCol = product.kind === 'photos1'
      ? 'spotlight_1_purchased_count'
      : 'spotlight_10_purchased_count';

    if (eventType === 'NON_RENEWING_PURCHASE' || eventType === 'INITIAL_PURCHASE') {
      const currentCredits = (await getCurrentCount(admin, techEmail, 'photo_credits')) || 0;
      const currentCounter = (await getCurrentCount(admin, techEmail, counterCol)) || 0;
      await admin.from('techs').update({
        ...sourceUpdate,
        photo_credits: currentCredits + creditsToAdd,
        [counterCol]: currentCounter + 1,
      }).eq('email', techEmail);
    } else if (eventType === 'REFUND') {
      // Apple refunded a consumable — best-effort deduct (don't go negative).
      const currentCredits = (await getCurrentCount(admin, techEmail, 'photo_credits')) || 0;
      await admin.from('techs').update({
        ...sourceUpdate,
        photo_credits: Math.max(0, currentCredits - creditsToAdd),
      }).eq('email', techEmail);
    }
  }

  return new Response('ok', { status: 200 });
});

// Helper to read a single column off the techs row by email. Returns 0
// if the row or column is missing/null. Cheap one-shot reads keep the
// webhook handler readable without batching.
async function getCurrentCount(admin: any, email: string, column: string): Promise<number> {
  const { data } = await admin.from('techs').select(column).eq('email', email).single();
  if (!data) return 0;
  const v = data[column];
  return typeof v === 'number' ? v : (v ? Number(v) || 0 : 0);
}
