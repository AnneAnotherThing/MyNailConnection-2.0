# CHANGE SET — 3.0 goes free (photos)

**For Claude Code. Apply in the numbered order.**
Companion migration: `sql/photos-free-3.0.sql` (rev 3, in this folder).

---

## Goal

Photos stop being a paywall, permanently. A tech gets her profile, her
booking system, and **50 looks a month, free, forever**. No lifetime
ceiling. The monthly allowance exists only to prevent abuse and refills on
its own. Pay-per-photo (Spotlight) is retired. Glow Up comes off all
tech-facing screens until it means booking tools (no-show deposits,
rebooking reminders, salon accounts).

Nothing is deleted. Stripe, the IAP config, `photo_credits` and the Glow Up
subscription all stay live and functional — they simply stop being
advertised.

---

## ⚠ Read before editing `index.html`

Per the repo's own `CLAUDE.md`: the Edit/Write tools have **repeatedly
truncated** this file (1.3MB, ~20k lines), silently dropping the closing
`<script>` blocks and `</body></html>`. Trigger is a large `new_string`
replacing content near the END of the file.

- **Use bash** (`sed -i`, `python3` + heredoc, `cat`-splice) for every edit below.
- After **every** edit: `tail -c 200 index.html | grep '</body>'`
- `deploy/sync.sh` has a `validate_html` guard that aborts on a missing
  `</body>` or a >10% line-count drop vs git HEAD. Trust it.

---

## 1. Run the SQL first

```
sql/photos-free-3.0.sql
```

Run in the Supabase SQL editor (project `ktiztunuifzbzwzyqrrq`). Idempotent.

It is a **restructure, not a number swap**: the free tier moves off the
`lifetime_free_used` lifetime counter and onto the same
`period_upload_count` / `period_reset_at` monthly mechanic subscribers
already use. One model for everybody; only the cap differs.

Two constants at the top are the only knobs:

| Constant | Value | Meaning |
|---|---|---|
| `v_free_cap` | `50` | free tech, per month, forever |
| `v_glowup_cap` | `150` | subscriber, per month (was 25) |

Also in that file:
- The lazy monthly reset now runs for **everybody**, not just subscribers.
- `lifetime_free_used` is still incremented for analytics but **no longer
  gates anything**.
- `weekly_reset_at` (wire-compat name; it's the monthly refill timestamp)
  is now returned on **every** call including the refusal, so the UI can
  name the refill date.
- `photo_credits` still spend and can burst **past** the monthly allowance.
- `tech_comps` lookup and the `for update` row lock are unchanged.
- **A one-time `UPDATE`** at the bottom nulls `period_reset_at` /
  `period_upload_count` for non-paid, non-comped techs (they never used
  those columns) so their next upload opens a clean window. Subscribers and
  comps are explicitly excluded.

Verify with the sanity-check query at the bottom of the file — it prints
every tech, her tier, her cap, and her refill date.

**Order matters.** SQL before the app ship. Generous server + stingy client
is invisible; stingy server + generous client is a tech tapping Upload and
getting an error.

---

## 2. Three numbers in `index.html`

Two are fixed lines, the third is a grep. All three must match the SQL.

| Line | Was | Now |
|---|---|---|
| 4238 | `const NEW_TECH_FREE_PHOTOS = 1;` | `const NEW_TECH_FREE_PHOTOS = 50;` |
| 5058 | `free_limit: 1,` (inside `STRIPE_CONFIG`) | `free_limit: 50,` |
| grep `25 photos a month` | subscriber monthly cap | `150 a month` |

**Leave `PHOTO_FREE_CUTOVER` alone** (line 4237, parked at `'2099-01-01'`).
`mncFreeLimit()` falls through to `STRIPE_CONFIG.free_limit` for everyone,
so once both numbers read 50 both branches return 50 and the cutover logic
is harmless. Delete it in a later cleanup, not now.

> Note: the comment at line 4233 claims pre-cutover techs "keep the original
> 5-free promise." They weren't — because `free_limit` was also 1, that
> fallback quietly handed everyone a single photo. This change fixes it.

---

## 3. Copy edits (15)

Keep the surrounding markup in every case. Swap the words only.

### Tech Portal (`#tech-home`)

**Line 2088** — section heading
- was: `Photos are what get you seen`
- now: `Post everything.`

**Line 2089** — section subline
- was: `Every photo you post becomes your own personal ad, running in the live feed where clients are scrolling right now.`
- now: `Your whole portfolio, free. Every look you add is one more way a client can find you — and it keeps working for you forever.`
- Drop "personal ad" language everywhere; it was invented to justify a price.

**Line 2093** — card heading
- was: `You're in charge of your ad spend`
- now: `Your gallery, all free`

**Lines 2095–2101** — the three bullets (same markup, same checkmark icons)
1. `Post up to 50 looks a month, free — forever.`
2. `More looks means more of the Gallery is yours; your share is exactly proportional to your photo count.`
3. `Photos stay up forever. Upload once, get found for years.`
- Say the real number, never "no limits." A tech who finds a cap after being
  told there isn't one is a tech you lied to. Bullet 2 is the
  honest-algorithm promise from How It Works — worth having on the daily screen.

**Line 2119** — slots card label
- was: `uploads available`
- now: `free uploads left this month`

### Slot subtitle strings

**Lines 3585, 3586, 3587** — three branches, all quoting prices. Return the
same sentence from all three:
- now: `Post up to 50 looks a month, free — on us, forever.`

**Line 3647** — slots card subtitle
- was: `Your first photo is on us, ... After that, $1 each, 10 for $5, or Glow Up: 25 photos a month for $10.99.`
- now: `Photos are free. Post your whole portfolio.`

### At-capacity messages — **must not sell**

Hitting 50 is not an upgrade moment, it's a "come back next month" moment.
The SQL returns the refill timestamp on every call including the refusal, so
print the real date.

**Lines 3948–3949**
- now: `That's 50 looks this month — you have been busy. Your next 50 unlock on {date}, and everything you have posted stays up.`

**Lines 9169 and 9351** — same string in two places, change both
- was: `Add a photo credit or Glow Up to post.`
- now: `That's your 50 for this month — your next 50 unlock on {date}.`

### Tutorial

**Line 4344** — tech tutorial slide 3 body, first paragraph
- was: `Every photo you post joins the one Gallery every client scrolls. Photos are $1 each, $5 for a 10-pack, or Glow Up's monthly bundle, and each one is your own personal ad, running until you take it down.`
- now: `Every photo you post joins the one Gallery every client scrolls — and they are free. Post your whole portfolio, and it stays up until you take it down.`
- **Keep the second paragraph about tagging Shape / Type / Style exactly as
  is.** It's genuinely useful and unrelated to price.

### How It Works (`#how-it-works`)

**Lines 2540–2570** — replace all three plan cards with **one** card.
Keep the section shell and the star icon header.

> ### What it costs
> **Nothing.** Your profile, your booking system, and up to 50 looks a month
> in the Gallery — free, forever, no commission, no fees for your clients, no
> monthly charge.
>
> *The 50-a-month limit is only there to keep things running smoothly. Almost
> nobody reaches it, and it refills every month.*

Delete Starter, Spotlight **and** Glow Up from this screen. A visible paid
tier that does nothing for her invites "what am I missing out on?" when the
answer is nothing. Bring Glow Up back the day it means no-show deposits.
Naming the cap as plumbing rather than a tier is what makes it read generous.

**Line 2625** — tip 4 (currently the only upsell in a list of good advice)
- was: `Upgrade when it is paying for itself` / `Glow Up is the best per-photo price...`
- now title: `Post a look every time you finish a set`
- now body: `It takes fifteen seconds and it is the single best thing you can do for how often you turn up in the Gallery. A tech with twenty looks appears four times as often as one with five.`

### Splash (`#splash`)

**~Line 1240** — add one line under `BEAUTY. CONNECTED.`
- now: `Free booking for nail techs. Always.`
- The splash currently never states the offer. A tech scanning a QR code
  learns nothing before deciding whether to install.

---

## 4. Hide, don't delete

**The upgrade modal** (`#upgrade-modal`, line 19100) — nothing should reach
it. Leave the markup, stop calling it, and fix line 19105 which hardcodes
"all 5 free photo slots" via `upgrade-limit-text` so a stray open can't show
a stale number. It returns when Glow Up means booking tools.

**The slots-remaining card** (`#td-slots-card`, line 2113) — already
`display:none`, revealed by `updateSlotsRemainingDisplay()`. Keep it hidden
below ~40 used. A number counting down from 50 all month invites rationing,
which is the behaviour we're trying to stop. A countdown is a late warning,
never a budget.

**Spotlight, everywhere** — How It Works line 2554, upgrade modal lines
19117–19136, nudge line 3948. Delete the cards/rows. Keep the Stripe payment
links in `STRIPE_CONFIG` and both IAP product IDs
(`com.mynailconnection.app.spotlight_1` / `_10`) in the code — inert with
nothing linking to them.

**Glow Up, on tech-facing screens** — grep `10.99`. Take it off the tech
screens for launch. The subscription stays live in Stripe, in the IAP config
and in the SQL (150/month) so existing subscribers and comps keep working.

**App Store / Play Console** — keep the Glow Up subscription configured. The
two consumables can stay configured but unreferenced; Apple doesn't require
an app to surface every IAP, and fewer purchase paths means a simpler review.
Check whether the store listing copy quotes photo prices.

---

## 5. Outside the app — DO NOT SKIP

Pricing is baked into five files. If these still say "$1 per photo" on
launch day, techs arrive expecting to pay and the "completely free"
announcement gets fact-checked in public.

### `marketing-v3.html` — CRITICAL
The 3.0 version, and the one that ships as root `index.html`.
- Lines **134, 135** — JSON-LD `Offer` entries with real prices ($1.00
  Spotlight, $10.99 Glow Up). **Google has indexed these**, so they can
  surface in search results even after the visible page is edited.
- Line **147** — FAQ answer spelling out "$1 each, $5 for ten, or Glow Up at
  $10.99 a month for 25 uploads."
- Lines **1891, 1970** — body copy quoting prices.
- Lines **2004–2021** — the visible Pricing section cards.

### `marketing.html` — CRITICAL
Same JSON-LD `Offer` entries and FAQ answer (lines 134, 135, 147), same
visible price cards (1907–1926), plus lines 1794, 1861, 1862, 1873. Note
this file is still on **2.0 copy** ("unlimited photo uploads", "5 new slots
every Sunday", "What's Happening feed") which doesn't match 3.0 at all.

### `tech-guide-v3.html` — HIGH
- Lines **795–806** — a photo-slots **graphic** with four `$1` labels and an
  "or 10 for $5" arrow. This is a visual, so find-and-replace will miss the
  impression it leaves.
- Line **1286** — states the model outright: *"That is the entire business
  model: we only earn when you choose to show more of your work."* Good
  sentence, wrong model now.
- Line **1302** — Glow Up per-photo maths.

### `tech-guide.html` — MEDIUM
Line **1300** — old 2.0 guide, references "Glow Up's 5 new slots every
Sunday," a mechanic that no longer exists. Decide whether this file should
still be reachable; `CLAUDE.md` lists it as shipping to the marketing bundle.

### `deploy/ghpages/tech-guide.html` — MEDIUM
Line **1300** — the already-built deploy copy carrying the same stale line.
Fix the source and re-run `sync.sh` rather than editing this by hand, but
don't forget it's currently live.

---

## 6. Ship

1. **Run the SQL** in Supabase. Verify with the sanity-check query.
2. **The three numbers** in `index.html` (4238, 5058, and the Glow Up cap grep).
3. **The 15 copy edits.** Bash only. `tail -c 200 index.html | grep '</body>'` after each.
4. **The four hidden surfaces** (upgrade modal, slots card, Spotlight, Glow Up).
5. **`marketing-v3.html` + `marketing.html`** — visible cards AND the JSON-LD
   `Offer` blocks AND the FAQ answers. Then `tech-guide-v3.html` including
   the dollar-sign graphic.
6. **`bash deploy/sync.sh`** — rebuilds `deploy/ghpages/` and auto-bumps the
   service-worker `CACHE_NAME` so returning techs actually pick up the new
   code instead of the cached old one. The `validate_html` guard also catches
   a truncated file.
7. **Push `main`.** If the previous Capacitor iOS deploy succeeded, run
   `bash deploy/bump-marketing.sh` **before** pushing, or the build fails ten
   minutes in on a closed pre-release train.

---

## While you're in there (optional, 5 minutes)

`index.html:2513` in How It Works says *"Open **Bookings** on your
**Dashboard**."* There is no Dashboard — the tab is called **Tech Portal**.
Global-replace `Dashboard` → `Tech Portal` across `index.html` (also lines
1547, 4339, 4349, 4359 and several comments). This is punch-list item 1 from
the design review and it's the single most-reported source of tester
confusion.

---

## Also worth checking (not a copy edit)

Does the Gallery grid request the thumbnails generated by
`deploy/backfill-thumbs.py`, or full-size images? Thumbs are worth roughly
**4×** on bandwidth (a browsing session drops from ~17MB to ~4MB), which
matters far more than any upload cap — egress is driven by clients browsing,
not by techs uploading.
