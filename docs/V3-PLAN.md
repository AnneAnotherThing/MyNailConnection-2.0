# MNC 3.0, Rebrand + Free Booking

## What 3.0 is (model v2, locked with Anne 2026-07-05)

One-stop shop for nail techs. A tech's profile either links to their
existing booking system or opens MNC's own, and MNC booking is **free
and stays free**. Photos are the revenue: **paid from the first upload**
(one free starter photo), and they double as the tech's advertising,
every photo joins the ONE app Gallery that clients scroll and filter.
No live feed, no posts feature, no ranking math: presence in the
Gallery is exactly proportional to photo count, and techs who flip
"Available now" glow in the grid. Visual identity moves from rose gold
and ivory ("In full bloom") to the copper/charcoal/gold direction in
`3.0.png` ("Rooted, Rebuilt, unstoppable."), launched with a countdown
campaign.

Pricing detail:
- New techs (joined on/after `PHOTO_FREE_CUTOVER` in index.html): 1
  free photo, then $1/photo, $5/10-pack, or Glow Up $10.99/mo (40/mo).
- Grandfathered techs (joined before cutover): keep the original 5
  free ("first five are free, always" was promised to them, it stays true).
- Glow Up's pitch is now purely best-per-photo-price (the live feed
  perk died with the feed).

## Where this lives

- Branch: `v3`, worked in this folder (`My Nail Connection 3.0`), a git
  worktree of the main repo. The `My Nail Connection` folder stays on
  `main` for 2.0 maintenance. Hotfixes to 2.0 land on `main` and get
  merged into `v3` periodically (`git merge main` from here).
- Nothing on `v3` can deploy. The Pages Action only fires on pushes to
  `main`. Cutover = merge `v3` into `main`, run `deploy/sync.sh`, push.
  Rollback = revert the merge commit.

## Workstreams

1. **Booking system**, STATUS: BUILT + migrated + e2e-tested 11/11
   (2026-07-05), including double-booking rejection and RLS. Three 2.0
   bookings-table landmines fixed (NOT NULL legacy cols, both FKs).
   Tier 1 (time off, buffer, pg_cron push reminders), STANDING
   APPOINTMENTS, the quiet client BLOCKLIST, and the "Not taking new
   clients" pause switch are all BUILT (app + SQL). PENDING: run these
   in the SQL editor, in order:
     1. sql/booking-tier1-migration.sql
     2. sql/booking-standing-migration.sql
     3. sql/blocklist-pause-migration.sql
   Remaining tier 2: waitlist, deposits (Venmo-note first, Stripe
   Connect later, 0% cut), client history, ICS export. NO SMS free.
   INTERNATIONAL pass DONE (2026-07-05): postal code free text, state
   dropdowns -> free text, Places worldwide, world-map default, mi/km
   by locale, tel/sms keep +, booking timezone auto-detect.
2. **Model v2 mechanics + copy**, STATUS: BUILT (2026-07-05). Feed and
   posts feature removed, one 3-col Gallery with linear weighting and
   available-now glow, 1-free-photo billing with grandfathering
   (`mncFreeLimit()`), tutorial/welcome/how-it-works rewritten.
   NOT yet done: marketing.html + tech-guide.html still describe the
   old model, they get rewritten with the rebrand (workstream 3).
3. **Visual rebrand**: palette from 3.0.png (copper/charcoal/gold),
   new logo treatment, CSS variables in `index.html` + full
   `marketing.html` and `tech-guide.html` rewrite (copy AND look).
   Keep one thread of continuity so existing users recognize it.
4. **Two-path onboarding**: quick question at tech signup routing to
   the full pitch (booking + gallery) or bring-your-own-booking pitch.
5. **Countdown component**: built last, launched last.

## Hard rules

- Countdown does not start until booking is built AND tested.
- "Free booking" stays free, never a bait-and-switch.
- Photo-model wording: mock says "Free Booking for New Techs";
  campaign copy must make clear booking is free for EVERYONE, and
  paid-photos applies to uploads, not photos already posted.
- All the 2.0 house rules in CLAUDE.md still apply here: bash for big
  HTML edits, run `deploy/sync.sh` after source edits, tail-check for
  `</body>`.

## Photo permanence (decided 2026-07-05)

Every paid photo is a PERMANENT ad. Subscription lapse never hides
photos (pause-on-cancel removed from stripe-webhook on v3; the pause
RPC stays in the DB, uncalled, for rollback). The ONLY thing that
takes photos down is the tech no longer wanting new clients. The
self-serve mechanism for that ("Not taking new clients" switch that
hides photos + booking + contact, without deleting the account) is a
small follow-up, build with workstream 3's onboarding work. Never
write copy implying photos can expire. Forever means forever.

## Before cutover

- Set `PHOTO_FREE_CUTOVER` in index.html to the launch date (it's
  parked at 2099-01-01 so everyone stays grandfathered until then).
- Deploy the updated stripe-webhook (`supabase functions deploy
  stripe-webhook`). Until deployed, live 2.0 cancellations still
  pause photos, that's intended, the change ships WITH 3.0.
- Run sql/restore-paused-photos.sql, the relaunch gift: every tech
  gets their paused photos back, permanently.
- Remove the dev quick-login block (`devLogin` / `devQuickLoginInit`)
  from index.html.
- Run the CLEANUP block in sql/test-booking-accounts.sql to delete the
  ZZ TEST accounts.
- Dead-code sweep (optional): the feed/posts JS (loadHomeFeed,
  loadMyBoardPosts, openNewPostModal, etc.) is unreachable but still
  in the file. Safe to leave; nice to remove.

## Open decisions

- Deposits / no-show protection: techs want it, it means Stripe fees.
  Scope and pricing TBD, not in the initial 3.0 cut.
- Whether the "MyNailConnection-2.0" GitHub repo gets renamed at
  cutover (cosmetic, GitHub redirects old URLs, no rush).
