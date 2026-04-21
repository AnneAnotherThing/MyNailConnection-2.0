# MNC Stripe Billing Setup

## Overview
- Free tier: 5 photos per tech
- Add-on: $1 per photo (one-time)
- Pack: 5 photos for $4 (one-time)  
- Unlimited: $9/month subscription

---

## Step 1: Supabase — Add columns to techs table

Run this SQL in Supabase SQL editor:

```sql
alter table techs
  add column if not exists subscription_tier text default 'free',
  add column if not exists photo_credits int default 0,
  add column if not exists subscription_expires_at timestamptz;
```

---

## Step 2: Create Stripe Products

In Stripe Dashboard → Products → + Add Product:

1. **1 Photo Slot** — $1.00 one-time
2. **5 Photo Slots** — $4.00 one-time  
3. **Unlimited Photos** — $9.00/month recurring

---

## Step 3: Create Payment Links

For each product, go to Stripe → Payment Links → + New:
- Select the product
- Under "Advanced" → enable "Pass client_reference_id"
- Copy the link URL (looks like https://buy.stripe.com/xxx)

Paste all 3 URLs into `index.html` in the `STRIPE_CONFIG` object:

```javascript
const STRIPE_CONFIG = {
  link_1_photo:   'https://buy.stripe.com/YOUR_REAL_LINK',
  link_5_photos:  'https://buy.stripe.com/YOUR_REAL_LINK',
  link_unlimited: 'https://buy.stripe.com/YOUR_REAL_LINK',
  free_limit: 5
};
```

---

## Step 4: Deploy Webhook Function

```bash
supabase functions deploy stripe-webhook
```

Your webhook URL will be:
`https://ktiztunuifzbzwzyqrrq.supabase.co/functions/v1/stripe-webhook`

---

## Step 5: Register Webhook in Stripe

Stripe Dashboard → Developers → Webhooks → + Add Endpoint:
- URL: your webhook URL above
- Events to listen for:
  - `checkout.session.completed`
  - `customer.subscription.deleted`

Copy the **Signing Secret** (starts with `whsec_`)

---

## Step 6: Set Secrets

```bash
supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_your_secret"
supabase secrets set STRIPE_SECRET_KEY="sk_live_your_key"
```

---

## How it works end-to-end

1. Tech hits 5-photo limit → upgrade modal appears
2. Tech picks option → Stripe Payment Link opens in browser
3. Tech pays → Stripe fires `checkout.session.completed` webhook
4. Edge Function reads `client_reference_id` (tech email) from session
5. Adds photo credits OR sets paid tier in Supabase
6. Tech returns to app → can now upload

## Testing

Use Stripe test mode keys (pk_test_... / sk_test_...) and test payment links
to verify the full flow before going live.
