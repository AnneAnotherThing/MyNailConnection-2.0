# Launch verification — 2026-08-19

Not a to-do list. Every line is something to **look at and confirm**, with
where to look and what "pass" means. Tick as you go; anything that fails is
the real work.

Ordered so a failure early doesn't waste time on the things below it.

---

## Already verified (by Claude, against live systems — no action)

| | Evidence |
|---|---|
| Repo fully pushed | `git ls-remote` = local = `069a09c`, 0 unpushed |
| Live web serving current code | `sw.js` cache matches, `confirmSignOut` present |
| Paywall split live in DB | `is_visible` / `is_bookable` return 200, `is_live` 400 (dropped) |
| Founder grandfathering removed | `founder_free` → 400, column gone |
| Paywall OFF | `paywall_enabled()` = false; all techs visible + bookable |
| **Nobody strands when you flip it** | 0 techs with `booking_enabled` and no subscription |
| ZZ TEST accounts | none in `techs` or `users` |
| Paused photos | 0 techs with `paused_count > 0` |
| targetSdk 36 + AGP 8.9.1 | in the tree, and build #114 compiled all 132 tasks |

## Already confirmed by Anne

- **Tech push works** — a tech device receives pushes. The APNs/FCM sender
  and the edge functions are proven.
- **iOS 3.0 is built**, not yet submitted.

---

## 1 · Twilio — blocks everything ✅ CLEARED 2026-08-21

Nothing else matters if techs can't sign in. Anne confirmed this section
passed on 2026-08-21. Left in place because it is the first thing to
re-check if sign-ins start failing.

- **console.twilio.com** — is there an "Upgrade" banner top-left?
  **Pass:** no banner.
- **Billing → Billing Overview** — real payment method, real balance?
  **Pass:** a card on file, not a trial/promotional balance.
- **Decisive test:** have someone whose number has *never* been used in
  testing sign in. **Pass:** code arrives.

> On trial, Twilio only delivers to **5 manually verified numbers**. Everything
> looks perfect on your handsets and fails silently for tech number six.
> Upgrading needs a card *and* an approved compliance profile — a review with
> lead time, so find out now, not on launch day.

---

## 2 · Push — two of three still unproven

Tech push is confirmed. These are not:

- **Client push.** Sign in as a client on a second phone, accept
  notifications, wait for "Notifications are on 💅". Book an appointment.
  **Pass:** the tech's phone buzzes. Then the tech confirms —
  **pass:** the client's phone buzzes.
- **Admin broadcast.** Admin → 📢 Push → send to Everyone.
  **Pass:** it arrives on a native device, not just web.

If a push doesn't land, check which half failed:

```sql
select user_id, auth as platform, updated_at from push_subscriptions order by updated_at desc limit 10;
select * from public.push_log_recent limit 10;
```

No row in `push_subscriptions` = the device never registered (client-side).
A row plus `{"sent":0}` = the server couldn't match the recipient key.

---

## 3 · Store setup — the subscription can't be tested without it

- **App Store Connect → Subscriptions.** Does
  `com.mynailconnection.app.pro_glow_up` exist, priced $10.99, **Ready to
  Submit** or better? **Pass:** yes.
  ⚠ The ID must match `IAP_PRODUCT_GLOW_UP` in `index.html` exactly.
- **Play Console → Subscriptions.** Same product, same price.
- **RevenueCat → Products / Entitlements.** Is `pro_glow_up` attached to an
  entitlement, and are the App Store + Play credentials connected?
- **RevenueCat → Integrations → Webhooks.** Is the webhook pointing at
  `…/functions/v1/revenuecat-webhook`, with **Verify JWT OFF** on that
  function? (RevenueCat sends a static Authorization header, not a JWT.)
- **Apple Small Business Program** — enrolled? Free, and it's 15% vs 30%.
  At 1,000 techs that's $18k/yr vs $36k/yr.

**Leave the 3-month intro offer OFF for the first test.** Without it a
sandbox purchase goes straight to *purchased* — an unambiguous signal. With
it the entitlement reads *trialing*, and you'd be testing two things at once.

---

## 4 · The subscription test itself

Flip the paywall on temporarily:

```sql
create or replace function public.paywall_enabled() returns boolean language sql immutable as $fn$ select true; $fn$;
```

Then, on a device, turn booking on as a tech. Each step can fail alone:

1. Subscribe sheet opens
2. Product **found** — a wrong ID dies here
3. Sandbox purchase completes
4. **`subscription_tier` flips to `paid`** ← the webhook, never yet proven
5. Toast reads *"You're all set — your book is open ✨"*
6. Book button appears on her profile

> Toast says *"Subscription received, it will activate shortly"* instead?
> The purchase worked and the **webhook** didn't. That's step 4, and it's the
> phone-only fix that has never run in anger.

Flip it back afterwards with `select false` until the intro offer is set.

---

## 5 · Android device pass — the edge-to-edge unknowns

Splash is confirmed good. These are not:

- **Booking form with the keyboard up.** **Pass:** no white gap, WebView not
  shrunken.
- **Scroll inside that form.** **Pass:** it scrolls and does *not* navigate back.
- **Back gesture from a deep screen.** **Pass:** goes back one screen.

> If the keyboard tests fail, that's the known Capacitor 7 issue and the
> answer is Capacitor 8 — not more plugin config. Worth knowing before you
> spend a day tuning.

Build stamp must match `APP_BUILD.android` in `index.html` — **572** as of
2026-08-21. If it doesn't, you're testing old code and nothing above counts.

> This line said **561** until 2026-08-21 and had already gone stale, which
> would have failed you for the wrong reason. `sync.sh` bumps the build on
> every edit batch, so any number written here is out of date by the next
> commit. Read it out of `index.html` instead:
> `grep -m1 "android:" index.html`

---

## 6 · Housekeeping

- **Uptime monitoring** — UptimeRobot, two monitors: `mynailconnection.com`
  and the Supabase REST root (401 without a key still proves it's alive).
- **Store listings** — paste from `docs/STORE-CONTENT.md`. Currently the
  listings still say "free booking" while the app says $10.99.
- **App Review demo account** — reviewers can see the free client side, but
  without a tech login they can't evaluate the half you're charging for.

---

## Then, and only then

```sql
create or replace function public.paywall_enabled() returns boolean language sql immutable as $fn$ select true; $fn$;
```

One statement. No rebuild, no resubmission. Verified: zero techs strand.
