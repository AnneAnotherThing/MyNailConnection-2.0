// Supabase Edge Function: stripe-webhook
// Handles Stripe payment events and updates tech tiers in Supabase
//
// Deploy:
//   supabase functions deploy stripe-webhook
//
// Set secrets:
//   supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_..."
//   supabase secrets set STRIPE_SECRET_KEY="sk_live_..."
//
// In Stripe Dashboard → Webhooks, add endpoint:
//   https://<your-project>.supabase.co/functions/v1/stripe-webhook
//   Listen for: checkout.session.completed, customer.subscription.deleted, invoice.payment_succeeded

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'npm:stripe@14';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, { apiVersion: '2023-10-16' });
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// Photo credit amounts by Stripe product name
// These MUST match the product names in your Stripe Dashboard exactly.
// Stripe Dashboard → Products → click each → the "Name" field is what shows up
// as item.description in the webhook line items.
//
// Pricing:
//   • 1 photo  = $1  (one-time)
//   • 5 photos = $4  (one-time, best value)
//   • Unlimited = $9/mo (subscription, handled separately below)
const CREDIT_MAP: Record<string, number> = {
  '1 Photo Credit':    1,
  '5 Photo Credits':   5,
};

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

  console.log('Stripe event:', event.type);

  // ── One-time payment completed ────────────────────────────────────────────
  if (event.type === 'checkout.session.completed') {
    const session = event.data.object as Stripe.Checkout.Session;
    const techEmail = session.client_reference_id;

    if (!techEmail) {
      console.warn('No client_reference_id — cannot identify tech');
      return new Response('OK', { status: 200 });
    }

    // Subscription purchase → set paid tier
    if (session.mode === 'subscription') {
      const expiresAt = new Date();
      expiresAt.setMonth(expiresAt.getMonth() + 1);
      await supabase.from('techs').update({
        subscription_tier: 'paid',
        subscription_expires_at: expiresAt.toISOString()
      }).eq('email', techEmail);
      console.log(`Set paid tier for ${techEmail} until ${expiresAt.toISOString()}`);
    }

    // One-time payment → add photo credits
    if (session.mode === 'payment') {
      // Get line items to determine credit amount
      const lineItems = await stripe.checkout.sessions.listLineItems(session.id);
      let creditsToAdd = 0;
      for (const item of lineItems.data) {
        const productName = item.description || '';
        creditsToAdd += CREDIT_MAP[productName] || 0;
      }
      if (creditsToAdd > 0) {
        // Fetch current credits
        const { data } = await supabase
          .from('techs')
          .select('photo_credits')
          .eq('email', techEmail)
          .single();
        const current = data?.photo_credits || 0;
        await supabase.from('techs').update({
          photo_credits: current + creditsToAdd
        }).eq('email', techEmail);
        console.log(`Added ${creditsToAdd} credits to ${techEmail} (now ${current + creditsToAdd})`);
      }
    }
  }

  // ── Subscription renewal (monthly invoice paid) ──────────────────────────
  if (event.type === 'invoice.payment_succeeded') {
    const invoice = event.data.object as Stripe.Invoice;
    // Only handle subscription renewals, not the first payment (that's checkout.session.completed)
    if (invoice.billing_reason === 'subscription_cycle') {
      const customerEmail = invoice.customer_email;
      if (customerEmail) {
        const expiresAt = new Date();
        expiresAt.setMonth(expiresAt.getMonth() + 1);
        await supabase.from('techs').update({
          subscription_tier: 'paid',
          subscription_expires_at: expiresAt.toISOString()
        }).eq('email', customerEmail);
        console.log(`Renewed paid tier for ${customerEmail} until ${expiresAt.toISOString()}`);
      }
    }
  }

  // ── Subscription cancelled/expired ───────────────────────────────────────
  if (event.type === 'customer.subscription.deleted') {
    const subscription = event.data.object as Stripe.Subscription;
    const customerId = subscription.customer as string;
    // Look up customer email from Stripe
    const customer = await stripe.customers.retrieve(customerId) as Stripe.Customer;
    const email = customer.email;
    if (email) {
      await supabase.from('techs').update({
        subscription_tier: 'free',
        subscription_expires_at: null
      }).eq('email', email);
      console.log(`Reverted ${email} to free tier`);
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' }
  });
});
