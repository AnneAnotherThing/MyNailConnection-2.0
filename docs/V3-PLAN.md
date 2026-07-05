# MNC 3.0, Rebrand + Free Booking

## What 3.0 is

Pivot from discovery-first ("be found") to one-stop shop: **free booking**
plus post-your-photos-at-your-pace. Booking is the daily-use hook that
works for a tech on day one with zero audience; photos become the
self-paced marketing layer on top. Visual identity moves from rose gold
and ivory ("In full bloom") to a **red and black** identity, launched
with a countdown campaign.

## Where this lives

- Branch: `v3`, worked in this folder (`My Nail Connection 3.0`), a git
  worktree of the main repo. The `My Nail Connection` folder stays on
  `main` for 2.0 maintenance. Hotfixes to 2.0 land on `main` and get
  merged into `v3` periodically (`git merge main` from here).
- Nothing on `v3` can deploy. The Pages Action only fires on pushes to
  `main`. Cutover = merge `v3` into `main`, run `deploy/sync.sh`, push.
  Rollback = revert the merge commit.

## Workstreams, in build order

1. **Booking system** (the big one, everything else waits on it)
   STATUS 2026-07-04: v1 code complete in index.html + sql migration.
   NOT yet run against Supabase, run sql/booking-system-migration.sql
   in the SQL editor before testing. Deferred: day-before reminders
   (needs pg_cron), deposits/Stripe, tech blocked-dates/time-off.
   - Tech side: services + durations + prices, weekly availability,
     calendar view, manage/cancel appointments.
   - Client side: pick a tech, pick a service, pick a slot, book.
   - Reminders: push + email in the free tier. NO SMS in free tier
     (per-message cost scales with the least profitable users).
   - Supabase: new tables + RLS in `sql/`, edge functions as needed.
2. **Visual rebrand**: red/black palette, new logo treatment, CSS
   variables throughout `index.html` and `marketing.html`. Keep one
   thread of continuity (logo mark or name treatment) so existing
   users recognize it.
3. **Two-path onboarding**: quick question at tech signup routing to
   the full one-stop pitch (booking + portfolio) or the lighter
   discovery-only pitch (just post and be found).
4. **Countdown component**: landing page or banner for the campaign.
   Built last, launched last.

## Hard rules

- Countdown does not start until booking is built AND tested. Zero
  risk of hitting day zero without a working product.
- "Free booking" stays free. The boundary is what free includes
  (push/email reminders yes, SMS and deposit-taking are later paid
  add-ons), never a bait-and-switch on booking itself.
- All the 2.0 house rules in CLAUDE.md still apply here: bash for big
  HTML edits, run `deploy/sync.sh` after source edits, tail-check for
  `</body>`.

## Open decisions

- Deposits / no-show protection: techs want it, it means Stripe fees.
  Scope and pricing TBD, not in the initial 3.0 cut.
- Exact red/black palette values and logo treatment: TBD with Anne.
- Whether the "MyNailConnection-2.0" GitHub repo gets renamed at
  cutover (cosmetic, GitHub redirects old URLs, no rush).
