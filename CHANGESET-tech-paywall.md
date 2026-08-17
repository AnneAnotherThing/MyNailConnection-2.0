# CHANGE SET — techs pay to be bookable

**For Claude Code. Apply in the numbered order.**
Decided with Anne 2026-08-15. Companion migration: `sql/tech-paywall.sql` (to be written).

---

## The model, stated once

> **Clients: free forever.**
> **Techs: build your gallery and set your availability free. Your first three
> months of taking bookings are free. After that, $10.99/month — locked at that
> price for life for anyone who joins as a founding tech.**
> **The 21 techs already on the platform stay free for life.**

An unpaid tech is **invisible and unbookable** — off the Map, off the Gallery,
no open slots, no direct-link booking. Her account, photos, tags, hours and
settings all stay intact and come back the moment she pays.

Why the gate sits at *bookable* and not at signup: she gets to build the whole
thing and see it working before she's asked for money, and there's no paywall
in front of a stranger who's never seen the product.

Why nothing is left open for her own clients: if a direct `?tech=` link still
booked, a tech would put it in her Instagram bio and never pay. Anne's call,
and it's the right one.

### ⚠ SELL THE TOOLING, NOT THE DISCOVERY

The single most important thing in this file. An earlier draft of the purchase
copy promised *"clients can find you on the Map, in the Gallery"* — a
**discovery** promise. MNC has ~21 techs and no client base, so that promise
cannot be kept for months. A tech who buys it and gets nobody cancels the day
the trial ends and tells her friends MNC does not work.

There are two value propositions here and only one of them is deliverable today:

| | Works on day one? |
|---|---|
| **A — Booking tooling.** Her booking page, link + QR, standing appointments, reminders, private notes, walk-ins, no commission, nothing charged to her clients | **Yes.** Needs zero MNC clients — she brings her own |
| **B — Discovery.** New clients finding her in the Gallery | **No.** Needs density that does not exist yet |

**Every word of paid-tier copy sells A.** B is upside, never a promise. This
also matches the 3.0 pivot already in `docs/HANDOFF.md` ("the customer is the
TECH", clients arrive via her shared link) — discovery-first is the model that
already flopped once.

**Why three months and not one:** a nail client cycles every 2–3 weeks, so one
month is barely two fills — not long enough for a tech to judge whether the
booking system is working. Three months costs roughly **fifteen cents per tech**
in real infrastructure. There is no financial argument against it.

**Why the founding rate:** it converts the cold-start weakness into a reason to
join now instead of waiting. Say plainly that the price goes up later. Both
stores preserve an existing subscriber's price when you raise it, so this
promise is automatic to keep and requires no code.

**Do not conflate the two "founder" concepts.**
`techs.founder_free` = the 21 existing techs, **free forever, never charged**.
The *founding rate* = new techs who subscribe before the cutoff, who **do pay**
$10.99 and simply never see an increase. That one is store pricing, not a
database flag.

---

## ⚠ Before editing `index.html`

Per `CLAUDE.md`: the Edit/Write tools have **repeatedly truncated** this file
(1.3MB, ~22k lines), silently dropping closing `<script>` blocks and
`</body></html>`. Trigger is a large `new_string` near the END of the file.

- **Use bash** (`sed -i`, `python3` + heredoc, `cat`-splice) for every edit below.
- After **every** edit: `tail -c 200 index.html | grep '</body>'`
- `deploy/sync.sh`'s `validate_html` guard aborts on a missing `</body>` or a
  >10% line-count drop. Trust it.

**Note the guard's blind spot** (found 2026-08-15): it checks `</body>` only.
`marketing-v3.html` is currently missing its `</html>`, and `sw.js` shipped
truncated for 251 commits because the guard never looks at JS. If you touch
`sw.js`, run `node --check sw.js`.

---

## The good news: the off switch already exists

`techs.listing_paused` (from `sql/blocklist-pause-migration.sql`) is described
in its own header as *"the one-and-only off switch."* It already:

| Surface | Where | Effect today |
|---|---|---|
| Gallery | `index.html:12611` | `if (tech.listing_paused) return;` — off the Gallery |
| Map / tech cards | `index.html:11816` | filtered out |
| Contact buttons | `index.html:7337` | replaced with a "taking a break" note |
| Open slots | `get_open_slots()` | returns empty, **server-side** |
| Booking write | `create_booking()` | refuses, **server-side** |

That last pair matters enormously: enforcement lives inside SECURITY DEFINER
functions, so it cannot be bypassed by a modified client. **You are not
building a gate. You are wiring an existing gate to a new input.**

---

## 1. SQL first — `sql/tech-paywall.sql`

Write and run this before the app ships. Generous server + stingy client is
invisible; the reverse is a tech tapping something and getting an error.

**1a. Two new columns on `public.techs`:**

```sql
alter table public.techs
  add column if not exists founder_free   boolean     not null default false,
  add column if not exists paid_through   timestamptz;
```

- `founder_free` — the grandfather flag. **Do not reuse `tech_comps` for this.**
  That table is looked up by `tech_comps?email=eq.…` (see `loadTechTier`), and
  a phone-only tech has no email, so she could never be comped. A boolean on
  the row is id-keyed and immune to that.
- `paid_through` — when the current paid period (or the free month) ends.
  Written by the RevenueCat webhook; also the free-month expiry.

**1b. One helper, the single source of truth:**

```sql
create or replace function public.tech_is_live(p_tech_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select not coalesce(t.listing_paused, false)
        and (t.founder_free
             or t.subscription_tier = 'paid'
             or (t.paid_through is not null and t.paid_through > now()))
     from techs t where t.id = p_tech_id),
    false);
$$;
```

Note it folds in `listing_paused`, so a tech who paused herself stays paused
even while paid. One function, one answer.

**1c. Wire it into the two enforcement points.** Both already check
`listing_paused`; swap that check for `tech_is_live()`:

- `get_open_slots()` — currently `sql/booking-min-notice.sql:39` (that file is
  the union of every prior rev; check it's still the live version before editing)
- `create_booking()` — `sql/blocklist-pause-migration.sql:154`, later revised in
  `sql/phone-auth-stage-d-blocklist-phone.sql:101`

Also check `tech_create_booking` (the tech's own add-appointment path,
`index.html:14545`). **Leave that one ungated** — a lapsed tech must still be
able to manage the appointments already on her books. See §3.

**1d. A computed column so the client can filter in one condition:**

```sql
create or replace function public.is_live(public.techs)
returns boolean language sql stable as $$
  select public.tech_is_live($1.id);
$$;
```

Same PostgREST computed-column pattern as `photos_count`. The client then reads
`is_live` instead of `listing_paused`.

**1e. Grandfather the 28, and only the 28:**

```sql
update public.techs set founder_free = true
where joined < '2026-08-15' and coalesce(founder_free,false) = false;
```

Verify the count is what you expect **before** committing. Print the list.

---

## 2. App changes

### 2a. The visibility filter (3 sites)

Replace the `listing_paused` reads with `is_live`:

| Line | Now | Becomes |
|---|---|---|
| `index.html:12611` | `if (tech.listing_paused) return;` | `if (!tech.is_live) return;` |
| `index.html:11816` | `if (tech.listing_paused) return;` | `if (!tech.is_live) return;` |
| `index.html:7337` | `if (tech.listing_paused) {` | `if (!tech.is_live) {` |

And add `is_live` to the row mapper at `index.html:20109` (next to
`listing_paused: !!t.listing_paused`), which is where `_mapTechRow` builds the
objects the Gallery and Map read. The comment already sitting at
`index.html:20101` documents that omitting a field here is a known bug class —
don't repeat it.

### 2b. The gate itself

The tech-facing bookable toggle is `tbToggle` → `tbPatchTech({ listing_paused })`
at `index.html:14402–14406`, with the pill at `index.html:14042`.

When she flips herself bookable and `tech_is_live()` would still be false for
payment reasons, don't just refuse — **open the purchase sheet**. The buy path
already exists and is wired to RevenueCat + Stripe (`index.html:4403`,
`_stripeLink('link_glow_up', …)`).

Copy for the sheet, first time — note it promises tooling, never new clients:
> **Your book, your link, your rules.**
> Your own booking page and QR code, standing appointments for your regulars,
> automatic reminders, and private notes on every client. No commission, no
> per-booking fee, and never a charge to your clients.
>
> **Free for three months**, then $10.99/month — locked at that price for life
> as a founding tech. Cancel anytime.

Everything named there is live today and works with the clients she already
has. Nothing in it depends on strangers finding her. When the Gallery does
start delivering new clients, that lands as a surprise rather than an
expectation she has been waiting on.

### 2c. The role fork — leave it alone

`selectRole('tech')` at `index.html:13123` (cards at `1366` / `1370`) stays
exactly as it is. **Signup is still free.** This is the whole point of moving
the gate to "bookable"; do not add a paywall here.

### 2d. End-of-trial warning (day ~90)

A tech whose free period is ending and who has clients booked must not be
surprised. Warn **twice** — three months is long enough that she will have
forgotten the trial ever started:

- **7 days out** — a persistent banner on the Tech Portal
- **1 day out** — push notification (`sendPushToUser`, already built) + banner

Copy, seven days:
> *Your three free months are almost up. Keep your book open for $10.99/month —
> your founding-tech price, locked for good.*

Copy, one day:
> *Your free trial ends tomorrow. Keep bookings on for $10.99/month — your
> calendar, your gallery and everything you've built stays either way.*

The second half of that sentence matters and must not be cut: the biggest
reason a tech ignores a renewal prompt is fear that declining nukes her work.
It does not. Say so.

---

## 3. Lapse behavior — Anne's rule, exactly

> Existing appointments honor out. No new bookings. Hidden from discovery.

So on lapse:

- ✅ Hidden from Map + Gallery, contact buttons swap to the break note
- ✅ `get_open_slots()` returns empty → nobody can book her
- ✅ She keeps her calendar, and `tech_create_booking` still works so she can
  manage what's already there
- ✅ Already-confirmed appointments stay confirmed and still send reminders
- ❌ **Never** delete, hide, or pause photos. `docs/V3-PLAN.md` is explicit:
  *"Never write copy implying photos can expire. Forever means forever."*

**Do not touch `pause_photos_beyond_free_limit()`.** It exists from the 2.0
Stripe era to punish upload-then-cancel abuse. It has no role here and calling
it would break the permanence promise.

---

## 4. Store configuration

**Use a store-native introductory offer. Do not build your own free trial.**

Apple offers free-trial durations of 3 days / 1 week / 2 weeks / 1 month /
2 months / **3 months** / 6 months / 1 year, and Google Play supports a custom
free-trial period. So three months is a native option on both — no code, no
trial state in the database, the card is captured up front, and it converts
automatically. A homegrown "free now, we'll ask later" is more work and worse
conversion.

Configure on `com.mynailconnection.app.pro_glow_up`:
- **Introductory offer: 3 months free**, then $10.99/month recurring
- Apple: App Store Connect → the subscription → Introductory Offers
- Google: Play Console → the base plan → free-trial offer
- RevenueCat needs no change; it reports the trial as an active entitlement, so
  `subscription_tier` goes to `'paid'` from day one and `tech_is_live()` is
  true throughout the trial. **The database models no trial at all.**

**The founding rate needs no build.** Both stores let you preserve existing
subscribers' pricing when you raise a subscription price, so "locked for life"
is kept by simply not opting them into the increase. Pick and record the cutoff
date for who counts as founding.

**✅ Product ID confirmed 2026-08-17.** The live product is
`com.mynailconnection.app.pro_glow_up` — the constant `IAP_PRODUCT_GLOW_UP` was
correct and the comment above it was stale. The comment has been corrected in
`index.html`; do not "fix" the constant to match any older note.

Also: **enroll in the Apple Small Business Program.** It's a free application
and it's the difference between 15% and 30% — at 1,000 techs, $18k vs $36k a
year. Google already charges 15% on subscriptions from day one.

And put a **demo tech account in the App Review notes**. The client side is free
so reviewers can see the app works, but without a login they cannot evaluate the
tech half, and that's a rejection you'd never see coming.

---

## 5. Outside the app — DO NOT SKIP

This is the `CHANGESET-photos-free.md` sweep run **backwards**, and it is the
biggest single chunk of work here. Every surface currently promises free.

### `docs/STORE-CONTENT.md` → then both store listings
- **Subtitle** is literally `Free booking for nail techs` — no longer true
- Description: *"No commission, no per-booking fee, no charge to your clients"* —
  the first two are still true, keep them, they're your differentiator
- *"Free for all basic features. More features as the app gains momentum."* — replace
- Suggested subtitle: `Booking built for nail techs`
- Suggested line: *"Free to set up, free for three months, then $10.99/month —
  locked for life as a founding tech. No commission, no per-booking fee, and
  never a charge to your clients."*
- **Do not put a discovery promise in the store listing either.** The current
  description leads with the Gallery. Lead with the booking page, the shareable
  link and QR, standing appointments, and reminders. Keep the Gallery, but as a
  feature she gets, not as a stream of new clients she is being sold.

### `marketing-v3.html` — CRITICAL
This is the LIVE page (`sync.sh` copies it to `deploy/ghpages/index.html`).
- The **JSON-LD `Offer` block** — Google indexes this, so a stale price can
  surface in search long after the visible page changes. It was scrubbed to free
  in the photos-free pass; it now needs a real $10.99 offer.
- The visible pricing section
- Any body copy saying booking is free for techs
- **Also fix the missing `</html>`** while you're in there

### `tech-guide-v3.html` — HIGH
Grep for "free". Step copy describes free booking throughout.

### `index.html` in-app copy
- How It Works (`#how-it-works`) — the single "What it costs" card written in
  the photos-free pass says *"Nothing."* Rewrite.
- The tech tutorial slides
- The splash line `Free booking for nail techs. Always.` — this one is a direct
  contradiction. Replace with something true.

**Say the real number everywhere.** A tech who finds a price after being told
free is a tech you lied to — that's the same rule the photos-free changeset
opened with, and it cuts both directions.

---

## 6. Ship order

1. Write + run `sql/tech-paywall.sql`. Verify the grandfather count and print the list.
2. Confirm the IAP product ID in App Store Connect. Configure the 1-month intro offer.
3. App changes §2, bash only, `tail -c 200 index.html | grep '</body>'` after each.
4. The §5 marketing sweep — all files, JSON-LD included.
5. `bash deploy/sync.sh` (rebuilds bundles, bumps `CACHE_NAME`, runs the guard).
6. `bash deploy/bump-marketing.sh` if the prior iOS deploy reached App Store Connect.
7. Commit `v3`, mirror to `main`, push. Then the native build.

---

## Not in this changeset

- **targetSdk 36 / AGP upgrade** — ships in the separate compliance build. Request
  Google's extension to Nov 1 so this doesn't share a deadline with a paywall.
- **Password auth** — saves ~$2/month at current size. Revisit around 500 techs,
  and bundle it with a build that's happening anyway.
- **Deposits, waitlist, client history** — the *next* revenue conversation, not
  this one.
- **Glow Up as a photo tier** — dead. `$10.99` now buys bookability. The 150/month
  upload cap and the 50/month free cap are unchanged and unrelated.

---

## Open question for Anne

A tech signs up, builds a gallery, never turns bookings on. She sits in the
database forever, invisible, costing ~5¢/month. Fine — but should her photos
count toward the Gallery that clients browse?

**Recommendation: no.** If she's not bookable, a client who taps her photo hits
a dead end. Keep the Gallery to techs who can actually take the booking. That's
what `is_live` already does in §2a — flagging it so it's a decision and not an
accident.
