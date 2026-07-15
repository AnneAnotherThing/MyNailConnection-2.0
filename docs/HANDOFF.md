# MNC 3.0 — Handoff Summary (as of 2026-07-09)

Paste this into a new chat to continue with full context.

---

## What this is
**My Nail Connection (MNC)** is Anne's nail-tech app. **3.0** is a pivot +
rebrand: discovery-first flopped, so the new model is **free booking as the
hook**, **photos paid and permanent** (they double as the tech's advertising),
**one Gallery**, launched under a new visual identity. The build is
essentially DONE; it is blocked from launching by a database outage
(see "THE BLOCKER").

## Where the code lives
- **Repo (3.0 work):** `C:\Users\amwhi\repos\My Nail Connection 3.0` — this is
  a **git worktree on branch `v3`**.
- **2.0 maintenance:** `C:\Users\amwhi\repos\My Nail Connection` — branch `main`.
- **Deploy:** GitHub Pages Action publishes `deploy/ghpages/` ONLY on push to
  `main`. Nothing on `v3` can deploy. Cutover = merge `v3`→`main`, run
  `deploy/sync.sh`, Anne pushes `main` via GitHub Desktop.
- **The app is one giant file:** `index.html` (~18k lines, single-page).
  Marketing site is `marketing.html`. Edit big HTML via bash/python scripts,
  never risk Edit-tool truncation; always tail-check for `</body>` and
  node --check the `<script>` blocks after edits; run `deploy/sync.sh`.
- **Key docs in repo:** `docs/V3-PLAN.md` (full plan), `docs/MIGRATION-RUNBOOK.md`
  (the database migration steps), this file.

---

## THE BLOCKER (the one thing gating launch)
The **old free-tier Supabase database is down** and has been since ~July 6.
- Old project ref: `ktiztunuifzbzwzyqrrq`, in the **free** org "My Nail Connection".
- Supabase's platform-wide incident is **RESOLVED (July 8)** — so the project
  is now *individually stuck*, not caught in their outage. It is therefore
  **safe to act**.
- **Anne's next move:** in the Supabase dashboard → project → Settings →
  General → "Project availability", click **Restart project**. If not back in
  ~10 min, do **Pause → Resume** (forces a fresh cold start).
- The free tier has **NO backups**, so the only copy of all tech/client/photo/
  login data is on that stuck instance. It must wake at least once to rescue it.
- **A self-firing rescue is armed:** `rescue/watch_and_rescue.py` polls the old
  DB and auto-dumps schema+data+roles the moment it connects (via the pooler:
  `aws-1-us-east-1.pooler.supabase.com:5432`, user `postgres.ktiztunuifzbzwzyqrrq`).
  DB passwords are in **Anne's password manager** (not in the repo).

## The new home (already built, waiting)
- New project: **"My Nail Connection 3"**, ref `nwqnakoongrorbwnrqzc`, in the
  **Hive-Rise Pro org**, micro compute (1GB), us-east-1. ~$10–15/mo covered by
  Pro credits. Gets **daily backups** + real support (the whole point).
- Already configured: **Auth URL config done** — Site URL
  `https://mynailconnection.com/app/`; Redirect URLs
  `https://mynailconnection.com/app/**` and `http://localhost:8123/**`.
- It is **empty**. The base schema (techs/users/bookings tables) exists ONLY in
  the dead old project, so the SQL migrations can't run on the new project until
  the rescue delivers the schema. New project's URL + anon key not yet pulled
  (needed later for the app-key swap; get from dashboard → Settings → API).

---

## WHAT'S BUILT (all committed on `v3`, tested where noted, NOT deployed)

**The model (v2, locked with Anne):**
- Free booking = the hook, free forever.
- Photos paid from the first upload: **1 free for new techs, 5 grandfathered**
  for pre-cutover techs (`PHOTO_FREE_CUTOVER` constant parked at 2099 until
  launch day). Photos are **permanent ads** — never expire; the only thing that
  removes them is a tech choosing "not taking new clients" (pause switch).
  Pause-on-cancel was removed from the Stripe webhook.
- **ONE Gallery** — the feed and posts features were removed entirely. Presence
  is **linear** (share ∝ photo count, no damping). Techs who flip "available
  now" **glow** in the grid.

**The booking engine (end-to-end tested 11/11 on old prod before it died):**
- Services + durations + prices, weekly hours, server-side open-slot math,
  atomic **double-booking-proof** `create_booking` (advisory lock).
- Pending-then-confirm default + per-tech **auto-confirm** toggle. My Appointments.
- **Tier 1:** time off / blocked dates, buffer time, pg_cron **push reminders**
  (day-before + 3-hour, to client AND tech). Push only (no email sender).
- **Standing appointments:** convert-to-standing every 1–4 weeks, materialized
  as real bookings, daily top-up cron. (The flagship "beat the paid tools" feature.)
- **Blocklist** (quiet, client never told) + **"not taking new clients"** pause
  switch (hides photos, pauses booking + contact, keeps the account).
- **International/location-agnostic:** postal codes not just ZIPs, state
  dropdowns → free text, mi/km by locale, world map default, booking timezone
  auto-detected. No country lists to maintain.

**Migration landmines already fixed** (found during the e2e test): bookings table
had NOT-NULL legacy columns + FKs pointing at the wrong/legacy tables — all
repointed. These fixes are in `sql/booking-system-migration.sql`.

**SQL migration files (run in this order once the schema is restored):**
`booking-system-migration.sql` → `booking-tier1-migration.sql` →
`booking-standing-migration.sql` → `blocklist-pause-migration.sql`.
Plus `restore-paused-photos.sql` (the relaunch gift) and
`test-booking-accounts.sql` (ZZ TEST accounts + DEV logins).

**The rebrand (Leslie's Pat-Nagel-inspired direction — Anne approved "LOVE"):**
- Palette: black `#141317` / mauve `#BFA6BB` / deep-mauve `#7D6478` / blush
  `#F7E8EE` / ivory `#EDEAE5`, applied app-wide (off the old rose-gold). Type:
  Playfair Display + DM Sans.
- Splash: the **hat-lady artwork** (`newlogo.jpeg`) edge-to-edge on ivory with
  vertical-only fades, **deep-etched MNC wordmark**, **convex light-based 3D
  buttons** (Anne rejected keyline-ring buttons), letterpressed subtitles,
  vertically centered.
- Flowers removed from all headers, **admin panel removed** from the app (Anne
  runs admin herself via dashboards/Supabase), 3D cards, Help & Account section,
  Bookings promoted to top of the tech dashboard.
- **Dev tools (localhost only):** DEV·Tech / DEV·Client login buttons, and a
  "DEV · New pricing" chip to preview the post-cutover 1-free experience.

---

## STILL TO BUILD (not blocked by the database)
- **Marketing site rebrand** (`marketing.html`) — still old look + old model
  claims ("unlimited photos," "What's Happening feed," "In full bloom"). Biggest
  remaining chunk. Rebrand to the mauve system + new pitch + new logo.
- **tech-guide.html** rebrand; **favicon + app-store icons** still rose-gold;
  **og-image.png** still old branding.
- **Waitlist capture on the live marketing site** — campaign posts send techs to
  the site to "get on the list" but there's no email capture there yet. Uses
  `launch_waitlist` table. (Campaign blocker.)
- **Two-path tech signup** — quick question routing "I need booking" vs "I book
  elsewhere, just give me the gallery."
- **Finish auth config** on new project: email templates (reset uses
  `/app/?token_hash=...&type=recovery`; signup confirm uses `type=email` NOT
  `type=signup`), leaked-password protection, min length 8+.
- Countdown campaign assets largely exist in `campaign-assets/` (day pages +
  social cards, mauve system); need waitlist wiring + og refresh.

---

## WHAT ANNE TESTS BEFORE LAUNCH (on the migrated new DB, DEV buttons make it 1 tap)
1. **A full booking both sides:** tech sets services + hours + booking on; client
   books; confirm; reminders fire; make it standing; block a day; block the client.
2. **Email flows:** password reset + new-signup confirmation (historically the
   finickiest part of MNC — see the memory on auth-email wiring).
3. **Push notifications** — the VAPID private key may not survive the move; if
   not, everyone re-subscribes silently on next login. Verify live.
4. **Photos + glow + pricing:** upload → lands in Gallery → flip available-now →
   glow; preview the 1-free pricing via the dev chip.
5. **On a real phone / PWA** — where the techs actually are.

---

## LAUNCH SEQUENCE (in order; see docs/MIGRATION-RUNBOOK.md for detail)
1. **Wake old DB → rescue → restore into new project** WITH the "do it right"
   cleanups (drop dead 2.0 tables, normalize email casing + add CHECK, add
   `auth_id` bridge columns to fix the ID-mismatch class of bug, drop bookings
   legacy columns, auth hardening).
2. **Finish auth + edge functions + secrets:** deploy edge functions
   (send-push, stripe-webhook v3 [pause-on-cancel already removed],
   broadcast-push, delete-account, revenuecat-webhook); set VAPID secrets;
   create NEW Stripe + RevenueCat webhook endpoints pointing at the new project
   and set their signing secrets.
3. **Point the app at the new DB:** swap URL + anon key in `index.html` (2 spots),
   `reset-password.html`, `marketing.html` + trackers. Then `deploy/sync.sh`.
4. **Rebrand marketing.html + tech-guide + icons + og-image.**
5. **Add waitlist capture** to the live site.
6. **Flip launch switches:** set `PHOTO_FREE_CUTOVER` to launch date; remove the
   dev-login block from index.html; run `restore-paused-photos.sql`; clean the
   ZZ TEST accounts.
7. **UptimeRobot monitors** (site + new Supabase REST) → alert Anne's email.
8. **Go live:** merge `v3`→`main`, `deploy/sync.sh`, push main. Web/PWA update
   in minutes.
9. **Submit new native app-store builds** — the old 2.0 native apps have the OLD
   DB URL baked in, so native users need the 3.0 store builds (web/PWA users get
   the new file automatically). Decide whether to keep the old project alive
   read-only until store approval.

---

## KEY RULES / PREFERENCES (carry into any chat)
- **No em-dashes** anywhere (copy, code, docs) — use commas.
- Be a **devil's advocate**: honest pushback, verify against real evidence, don't
  just agree.
- When given A/B/C architecture choices, **make the call** and explain briefly.
- Client-facing copy is **first-person singular** ("I/me", Anne is a solo operator),
  warm and understated, no hype.
- Messaging rule for 3.0: never imply 2.0 "failed"; frame is "we made it better."
- Reliability posture: finish the move to Pro + backups; watch Supabase over the
  next couple months; only reconsider the vendor (a big rewrite) if a PAID,
  backed-up instance still flakes.

## Current status one-liner
Everything is built. The only blocker is the old database being asleep. Anne
clicks Restart (or Pause→Resume) in Supabase; the rescue auto-fires; then it's
restore → finish config → swap keys → rebrand marketing → test → launch.
