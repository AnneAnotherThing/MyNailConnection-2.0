// Supabase Edge Function: stripe-webhook
// Handles Stripe payment events and updates tech tiers in Supabase.
//
// Deploy:
//   supabase functions deploy stripe-webhook
//
// Set secrets:
//   supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_..."
//   supabase secrets set STRIPE_SECRET_KEY="sk_live_..."
//
// Register THREE events in Stripe Dashboard → Developers → Webhooks:
//   - checkout.session.completed       (credit packs + first subscription payment)
//   - customer.subscription.updated    (monthly renewals, plan changes, card updates)
//   - customer.subscription.deleted    (cancellations)
//
// DO NOT register invoice.payment_succeeded — customer.subscription.updated
// covers renewals and is cleaner. The tech-facing monthly receipt email is
// controlled separately under Stripe → Settings → Emails.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'npm:stripe@14';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, { apiVersion: '2023-10-16' });
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// Resolve credits for a Checkout Session line item. Tries several strategies
// in order, so we don't silently no-op if Anne ever renames products or tweaks
// pricing in the Stripe Dashboard.
//
// Preferred setup: add a `credits` metadata field on each Price in Stripe
// (e.g. { credits: "1" }, { credits: "10" }). That's the most explicit signal
// and survives any product renaming.
function creditsForLineItem(item: Stripe.LineItem): number {
  const qty = item.quantity || 1;

  // 1. Price metadata — most explicit
  const priceMeta = (item.price as Stripe.Price | null)?.metadata?.credits;
  if (priceMeta) return (parseInt(priceMeta, 10) || 0) * qty;

  // 2. Product metadata — requires listLineItems to expand the product
  const product = (item.price as any)?.product;
  const productMeta = product?.metadata?.credits;
  if (productMeta) return (parseInt(productMeta, 10) || 0) * qty;

  // 3. Fall back to name matching. Keeps old "Slot" variants + pre-pivot
  //    "5 Photo Credits" so historical events still resolve correctly if
  //    ever replayed; current active products are "1 Photo Credit" and
  //    "10 Photo Credits" per the 2026-04-22 pricing pivot.
  const name = (item.description || '').trim();
  const byName: Record<string, number> = {
    '1 Photo Credit':   1,
    '1 Photo Slot':     1,
    '10 Photo Credits': 10,
    '5 Photo Credits':  5,   // legacy — kept for replay of pre-pivot events
    '5 Photo Slots':    5,   // legacy
  };
  if (byName[name]) return byName[name] * qty;

  // 4. Last-resort price inference aligned to current live pricing:
  //    $1 → 1 credit, $5 → 10 credits. Legacy $4 → 5 retained for replay.
  const cents = item.amount_total || 0;
  if (cents === 100) return 1 * qty;
  if (cents === 500) return 10 * qty;
  if (cents === 400) return 5 * qty; // legacy pre-pivot bundle

  console.warn(`creditsForLineItem: no match for "${name}" ($${cents / 100})`);
  return 0;
}

serve(async (req) => {
  const signature = req.headers.get('stripe-signature');
  if (!signature) return new Response('No signature', { status: 400 });

  let event: Stripe.Event;
  try {
    const body = await req.text();
    event = stripe.webhooks.constructEvent(body, signature, webhookSecret);
  } catch (err) {
    console.error('Webhook signature failed:', err);
    return new Response(`Webhook error: ${err}`, { status: 400 });
  }

  // ── Idempotency ──────────────────────────────────────────────────────────
  // Insert the event.id into public.stripe_events. If it fails with a
  // unique_violation (23505) it's a Stripe retry — short-circuit so we
  // don't double-credit on duplicate deliveries.
  const { error: dedupeErr } = await supabase
    .from('stripe_events')
    .insert({ event_id: event.id, type: event.type });
  if (dedupeErr) {
    if (dedupeErr.code === '23505') {
      console.log(`Duplicate event ${event.id} — already processed`);
      return new Response(JSON.stringify({ received: true, duplicate: true }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }
    // Any other DB error — log and continue rather than fail-closed, because
    // Stripe will retry and we don't want the dedupe layer to block real events.
    console.error('stripe_events insert error (proceeding):', dedupeErr);
  }

  console.log('Stripe event:', event.type, event.id);

  // ── Checkout completed (one-time credits OR first subscription payment) ──
  if (event.type === 'checkout.session.completed') {
    const session = event.data.object as Stripe.Checkout.Session;
    const techId = session.client_reference_id;  // now a techs.id (UUID)

    if (!techId) {
      console.warn('No client_reference_id — cannot identify tech');
      return new Response('OK', { status: 200 });
    }

    if (session.mode === 'subscription') {
      // Pull the sub so we can store current_period_end as the real
      // expires_at (authoritative source, beats computing +1 month).
      const sub = await stripe.subscriptions.retrieve(session.subscription as string);
      const expiresAt = new Date(sub.current_period_end * 1000);
      const customerId = session.customer as string;
      const { error } = await supabase.from('techs').update({
        subscription_tier: 'paid',
        subscription_expires_at: expiresAt.toISOString(),
        stripe_customer_id: customerId,
      }).eq('id', techId);
      if (error) console.error(`techs.update failed for ${techId}:`, error);
      else console.log(`Set paid tier for tech ${techId} until ${expiresAt.toISOString()}`);

      // If this is a re-subscribe after a previous cancellation, restore
      // any photos we paused on the way out. Safe no-op when nothing paused.
      const { error: rpcErr } = await supabase.rpc('resume_paused_photos', {
        p_customer_id: customerId,
      });
      if (rpcErr) console.error(`resume_paused_photos failed on checkout:`, rpcErr);
    }

    if (session.mode === 'payment') {
      const lineItems = await stripe.checkout.sessions.listLineItems(session.id, {
        expand: ['data.price.product'],
      });
      let creditsToAdd = 0;
      for (const item of lineItems.data) {
        creditsToAdd += creditsForLineItem(item);
      }
      if (creditsToAdd > 0) {
        const { data } = await supabase
          .from('techs')
          .select('photo_credits')
          .eq('id', techId)
          .single();
        const current = data?.photo_credits || 0;
        const { error } = await supabase.from('techs').update({
          photo_credits: current + creditsToAdd,
        }).eq('id', techId);
        if (error) console.error(`techs.update failed for ${techId}:`, error);
        else console.log(`Added ${creditsToAdd} credits to tech ${techId} (now ${current + creditsToAdd})`);
      } else {
        console.warn(`No credits matched for session ${session.id} — check product metadata in Stripe`);
      }
    }
  }

  // ── Subscription renewed, plan changed, card updated, etc. ───────────────
  // This fires on monthly renewals (current_period_end moves forward),
  // status transitions (past_due → active, etc.), and plan swaps. We use
  // Stripe's current_period_end as the source of truth for expires_at.
  if (event.type === 'customer.subscription.updated') {
    const sub = event.data.object as Stripe.Subscription;
    const customerId = sub.customer as string;
    const expiresAt = new Date(sub.current_period_end * 1000);
    const isActive = sub.status === 'active' || sub.status === 'trialing';

    const { error } = await supabase.from('techs').update({
      subscription_tier: isActive ? 'paid' : 'free',
      subscription_expires_at: isActive ? expiresAt.toISOString() : null,
    }).eq('stripe_customer_id', customerId);

    if (error) console.error(`techs.update failed for customer ${customerId}:`, error);
    else console.log(`Sub updated for ${customerId}: status=${sub.status}, expires=${expiresAt.toISOString()}`);

    // When the subscription transitions back to active (reactivation,
    // dunning recovery, trial end, etc.), restore any previously paused
    // photos. No-op when nothing paused.
    if (isActive) {
      const { error: rpcErr } = await supabase.rpc('resume_paused_photos', {
        p_customer_id: customerId,
      });
      if (rpcErr) console.error(`resume_paused_photos failed:`, rpcErr);
    }
  }

  // ── Subscription cancelled ───────────────────────────────────────────────
  // Flip tier back to free AND pause any photos beyond free_limit. This
  // closes the "pay once, upload-everything, cancel" abuse vector: the
  // tech's work isn't deleted, but it's hidden from public view until they
  // re-subscribe (or buy specific photos out with Spotlight credits).
  if (event.type === 'customer.subscription.deleted') {
    const sub = event.data.object as Stripe.Subscription;
    const customerId = sub.customer as string;

    const { error } = await supabase.from('techs').update({
      subscription_tier: 'free',
      subscription_expires_at: null,
    }).eq('stripe_customer_id', customerId);

    if (error) console.error(`techs.update failed for customer ${customerId}:`, error);
    else console.log(`Reverted customer ${customerId} to free tier`);

    const { data: pauseResult, error: rpcErr } = await supabase.rpc(
      'pause_photos_beyond_free_limit',
      { p_customer_id: customerId, p_free_limit: 5 },
    );
    if (rpcErr) console.error(`pause_photos_beyond_free_limit failed:`, rpcErr);
    else console.log(`Paused photos for ${customerId}:`, pauseResult);
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
