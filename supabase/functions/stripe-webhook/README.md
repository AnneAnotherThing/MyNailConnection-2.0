# MNC Stripe Billing Setup

## Overview
- Free tier: 5 photos per tech
- Add-on: $1 per photo (one-time)
- Pack: 5 photos for $4 (one-time)
- All-time portfolio: $9/month subscription ("Glow Up") — every set preserved while the subscription is active; paused (not deleted) on cancellation

---

## Step 1: Run the Supabase migration

Run `sql/stripe-billing-migration.sql` in Supabase → SQL Editor. This adds:

- `subscription_tier`, `photo_credits`, `subscription_expires_at` on `techs`
- `stripe_customer_id` on `techs` (set when a tech first checks out, used to
  match later subscription events back to the tech row)
- `stripe_events` table for webhook deduplication

The migration is idempotent — safe to re-run.

---

## Step 2: Create Stripe Products

In Stripe Dashboard → Products → + Add Product:

1. **1 Photo Credit** — $1.00 one-time
2. **5 Photo Credits** — $4.00 one-time
3. **Glow Up** — $9.00/month recurring (your all-time portfolio)

**Add a `credits` metadata field on each of the one-time Prices** (not products —
prices). In the Stripe Dashboard, open the Price, scroll to Metadata:

- 1 Photo Credit price → metadata: `credits = 1`
- 5 Photo Credits price → metadata: `credits = 5`

This is the most durable way to signal credit amounts. If the metadata is
missing, the webhook falls back to matching the product name ("1 Photo Credit"
or "1 Photo Slot" — both work) and then to amount-based inference ($1 → 1,
$4 → 5). But metadata is the belt-and-suspenders option — use it.

---

## Step 3: Create Payment Links

For each product, Stripe → Payment Links → + New:

- Select the product
- Under "Advanced" → enable **"Collect client reference ID"** (this lets Stripe
  accept the `?client_reference_id=` URL param the app appends at checkout)
- Copy the link URL (looks like `https://buy.stripe.com/xxx`)

Paste all 3 URLs into `index.html` in the `STRIPE_CONFIG` object:

```javascript
const STRIPE_CONFIG = {
  link_1_photo:   'https://buy.stripe.com/YOUR_REAL_LINK',
  link_10_photos: 'https://buy.stripe.com/YOUR_REAL_LINK',
  link_glow_up:   'https://buy.stripe.com/YOUR_REAL_LINK',
  free_limit: 5
};
```

The app passes `client_reference_id = techs.id` (a UUID) on each checkout so
the webhook knows which tech to credit. **Don't** configure the Payment Link
to pre-fill `client_reference_id` with a template — the app sets it dynamically.

---

## Step 4: Deploy the webhook function

```bash
supabase functions deploy stripe-webhook
```

Webhook URL:
`https://ktiztunuifzbzwzyqrrq.supabase.co/functions/v1/stripe-webhook`

---

## Step 5: Register the webhook in Stripe

Stripe Dashboard → Developers → Webhooks → + Add Endpoint:

- URL: the webhook URL above
- Events to listen for (exactly these three):
  - `checkout.session.completed`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`

**Do NOT register `invoice.payment_succeeded`** — `customer.subscription.updated`
fires on monthly renewals and gives us the real `current_period_end` to use as
`subscription_expires_at`. Cleaner and more accurate.

Copy the **Signing Secret** (starts with `whsec_`) — you'll use it in Step 6.

### A note on customer-facing emails

Whether Stripe sends techs a receipt email on every charge/renewal is
controlled separately in **Stripe → Settings → Emails** — it has nothing to do
with which webhook events you register here. If you don't want techs getting
monthly invoice emails, disable "Successful payments" under Customer emails.
That's independent of whether our webhook runs.

---

## Step 6: Set secrets

```bash
supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_your_signing_secret"
supabase secrets set STRIPE_SECRET_KEY="sk_live_your_key"
```

When going from test → live, rotate both: use the live-mode signing secret
from the live webhook endpoint, and the live-mode secret key from Stripe →
Developers → API keys.

---

## How it works end-to-end

1. Tech hits free-photo limit → upgrade modal appears.
2. Tech picks an option → `index.html` opens the Stripe Payment Link in a
   new tab, appending `?client_reference_id=<techs.id>`.
3. Tech pays on Stripe.
4. Stripe fires `checkout.session.completed` to the webhook:
   - If it was a one-time payment, the webhook reads the line items,
     resolves credit amounts (price metadata → name → amount), and adds
     them to `techs.photo_credits`.
   - If it was a subscription, the webhook sets `subscription_tier = 'paid'`,
     stores `stripe_customer_id`, and sets `subscription_expires_at` from
     the subscription's `current_period_end`.
5. Every month thereafter, Stripe fires `customer.subscription.updated`
   when the renewal charge clears — webhook pushes `subscription_expires_at`
   forward.
6. When the tech cancels (or card fails past the grace window), Stripe fires
   `customer.subscription.deleted` — webhook flips them back to `free`.
7. Meanwhile, back in the app: a one-shot `visibilitychange` listener fires
   when the tech returns to the tab, re-fetches `techs` state, and updates
   the UI with a "credits added" / "Glow Up unlocked" toast.

## Idempotency

Every event's `event.id` is inserted into `public.stripe_events` before
processing. Stripe retries on non-2xx / timeouts, so duplicate deliveries
are expected; the unique-violation on `event_id` causes us to short-circuit
and return `{ received: true, duplicate: true }` without re-applying the
effect.

## Testing — dual-mode setup (added 2026-04-22)

The webhook verifies signatures against **both** live and test signing
secrets and uses the matching API key to retrieve event-referenced
objects. So you can run test purchases alongside live without a second
function, and the client has a `STRIPE_CONFIG.test_mode` flag that swaps
the Payment Link URLs.

### One-time dashboard setup (~15 min, no impact on live)

1. Stripe Dashboard → flip the **"Test mode"** toggle (top-left).
2. Products → recreate:
   - **1 Photo Credit** — $1.00 one-time (add Price metadata `credits = 1`)
   - **10 Photo Credits** — $5.00 one-time (add Price metadata `credits = 10`)
   - **Glow Up** — $9.00/month recurring
3. Payment Links → recreate each, enable "Collect client reference ID".
   Copy each test URL (`https://buy.stripe.com/test_...`) into
   `STRIPE_CONFIG.link_*_test` in `index.html`.
4. Developers → Webhooks → + Add endpoint:
   - URL: same as live (`.../functions/v1/stripe-webhook`)
   - Events: same three (`checkout.session.completed`,
     `customer.subscription.updated`, `customer.subscription.deleted`)
   - Copy the test signing secret (`whsec_...`).
5. Developers → API keys (test mode) → copy the Secret key (`sk_test_...`).
6. Set the test secrets on your Supabase function:

   ```bash
   supabase secrets set STRIPE_WEBHOOK_SECRET_TEST="whsec_your_test_signing_secret"
   supabase secrets set STRIPE_SECRET_KEY_TEST="sk_test_your_key"
   supabase functions deploy stripe-webhook   # pick up the dual-mode code
   ```

### Running tests

1. Flip `STRIPE_CONFIG.test_mode = true` in `index.html` (locally or on a
   preview build — DO NOT ship `true` to production).
2. Use a throwaway tech row as your test account (any real row in
   `public.techs` — its `id` gets passed as `client_reference_id`).
3. Hit the upgrade flow in the app, pay with `4242 4242 4242 4242` any
   exp / any CVC.
4. Verify:
   - Buy a 1-photo credit → `techs.photo_credits` incremented by 1.
   - Buy the $9/mo sub → `subscription_tier = 'paid'`,
     `subscription_expires_at` ~1 month out, `stripe_customer_id` populated.
   - Simulate a renewal: Stripe → Customers → your test sub → "Advance
     test clock" one month → `subscription_expires_at` moves forward.
   - Cancel the sub → tier flips back to `free`.
5. Check Supabase function logs — test events are logged with a `[TEST]`
   prefix so they're easy to tell apart from live traffic.
6. Clean up the test tech row's `photo_credits` / `subscription_tier` /
   `stripe_customer_id` back to defaults when you're done.
7. Flip `STRIPE_CONFIG.test_mode` back to `false` before shipping.

### Safety note

Both live and test events write to the same Supabase DB (the dual-mode
code only changes which Stripe API key is used to retrieve objects, not
which DB it writes to). Test events on real user rows would grant those
users real credits. Always use a dedicated throwaway test tech when
running with `test_mode = true`.
