# State of the App · April 19, 2026

Take-a-break edition. Where MNC is right now.

---

## The honest headline

**The app core is launch-ready. The business scaffolding around it isn't.**

The tech and client experience — signing up, setting up, browsing, posting, staying signed in, getting support — works end-to-end. The admin console gives you and Leslie a workflow. Session persistence is solid. The invite flow hands migrated techs a clean one-tap onboarding.

**What's still open and launch-blocking** (per the punch-list, not my vibes):
- Stripe products + payment links (High)
- Decide + wire `/` routing — marketing vs app shell (High)
- Replace stub `privacy.html` + `terms.html` with counsel-reviewed versions (High)
- Liability acknowledgment checkboxes on tech + client signup (High)
- International / at-volume readiness memo (High)
- Plus: sending invite emails to the 17 techs (the actual launch action)

So: "core app ready to test, but you still need Stripe wired, legal docs reviewed, liability sign-off on signup, and a read on international / scale limits before you flip the sign." My earlier "one deploy + test pass" framing was wrong. Sorry — I was reporting off this session's wins, not the full punch-list.

---

## What got built in this session

### The big structural fix: Session persistence (Fix C)

Before: the app had no session persistence at all. Every reload, every closed tab, every back-and-forth — users had to sign in again. This was the original architecture, not a regression.

After: once a user signs in, they stay signed in across reloads and tab closures until they sign out or their refresh token dies (30 days by default in Supabase). A lightweight token-refresh timer runs in the background 5 minutes before each access token would expire.

Eight coordinated pieces:
1. `saveSession() / loadSession() / clearSession() / refreshSession()` helpers writing to `localStorage['mnc_session']`
2. Sign-in flow now calls `saveSession()` on success
3. Sign-out clears the persisted session
4. Page-load `restorePersistedSession()` hydrates the runtime state and routes to the correct home screen before the splash even renders
5. Proactive refresh timer fires ~5 min before expiry
6. `reset-password.html` writes the session for all three flows (signup-confirm, invite, recovery) — so there's no second sign-in step after any auth path
7. Service worker CACHE_NAME gets bumped on deploy so returning users actually pick up the new code
8. Full end-to-end tested on prod and localhost

### New: live home feed for clients

The client home screen's "Your Faves" section (which was just two shortcut cards) got replaced with a live-updating feed of recent tech posts:

- Shows the 100 most recent `board_posts`, newest first
- Filters to nearby techs via a chip selector (25mi / 50mi / 100mi / Anywhere)
- Radius preference persisted in localStorage
- Fixed-height 520px box that **auto-scrolls** at a readable pace
- Auto-scroll pauses when user touches the box, resumes after 4s idle
- Wraps back to top when it hits the bottom (infinite loop)
- Polls every 15s for newer posts — new ones prepend live, oldest drop off to keep the cache at 100
- Prompts for browser geolocation on first home entry so the radius chips are actually meaningful
- Lenient filter: if we can't compute distance (user/tech coords missing), show the post rather than silently hiding it

### Admin console rebuilt around real workflows

**Six tabs now:** Stats · Techs · Clients · Inbox · 📢 Push · Settings

**Stats tab** — consolidated. Dropped the duplicate header strip (which had broken element IDs). One panel now shows: 4 headline cards, Live Now + "Techs to invite" pulse strip, 14-day signups sparkline, waitlist count, refresh. Also fixed: the `created_at` vs `joined` column mismatch that was zeroing out the "This Week" card, the missing `tech_photos` table bug that left Photos at 0 (now sums `jsonb_array_length(photos)` across techs), the un-populated `waitlistRecent` reference, and a nasty dead-function hoisting bug where the Stats tab was silently running the wrong `loadAdminStats`.

**Inbox tab** — brand-new feature. Every "Nudge support" message from a tech or client persists to a new `contact_anne_messages` table (previously the push-only flow lost them if Anne's phone was offline). Each message shows: sender, phone, timestamp, body, with **Mark read** / **📱 Text back** / **Delete** buttons. A red unread badge on the tab floats across all admin contexts. Both you and Leslie can access — gated by `is_admin()` RLS.

**📢 Push tab** — brand-new. Form-based broadcast sender: pick audience (Everyone / Techs / Clients / Admins), title, body, optional deep-link URL. Confirms before sending. Backed by a new `broadcast-push` edge function that verifies the caller is an admin server-side, resolves target `auth.user` IDs for the chosen audience, and sends in parallel while pruning dead subscriptions.

**Settings tab** — trimmed. Removed the pre-launch-only Data Cleanup / Database / Geocode sections. Kept Admins, Search defaults, Help.

### Invite flow: end-to-end auto-sign-in

Previously: invited techs clicked the email link, saw "Link Expired" (a bug in `reset-password.html` that didn't handle `type=invite`), had to set a password, then sign in separately.

Now: click link → branded "Welcome to MNC" screen → set password → redirect to app → **already signed in** on their tech dashboard. The same pattern works for the signup-confirm flow (new client verifying email) and the password recovery flow.

### Landing pages got cleaner

- Removed the "how do you want to shop?" modal that was firing on first sign-in for clients and routing them away from home before they ever saw the feed
- Removed the 7 "Map" nav items (still accessible via "Browse by Location" card on home; the modal had already made it redundant)
- Shrank the two "Your Availability" sections (profile screen + tech home) with a "What do these mean?" expandable info panel instead of verbose descriptions under every toggle
- Availability labels shortened — "I could take a client right now!" → "Available now", "Accepting new clients" → "New clients welcome"
- "Contact Anne" support link repositioned as a subtle italic footer link: *"App acting up? Nudge support."*
- Modal title changed: "Need a hand?" → "What's glitchy?" — clearer purpose

### Authenticated-fetch audit in flight

Found a whole class of bugs where fetches to RLS-gated tables used the anon key instead of the user's JWT. RLS silently returned empty, features silently broke. Specifically fixed:

- `initProfileScreen()` (profile screen was saying "Client" for every tech because the role fetch was blocked)
- `saveSignupProfile()` role fetch right after sign-in
- `submitPost()` + `deletePost()` (board_posts RLS requires authenticated)
- `loadAdminStats()` — several fetches

Punch-list item still open: audit the remaining ~30 sites that use anon key and replace with `Bearer ${window._mncAccessToken || SUPABASE_ANON_KEY}` where the target table has authenticated-only RLS.

### Data hygiene fixes

- **Trailing-newline gremlin** — Laura Ortega's `public.techs` email had a `\n` appended (from a paste during your test setup) which broke every email-match query against her row, including the RLS policy. Hunted down with bucketing SQL. Fix applied: `update ... set email = btrim(email) where email <> btrim(email);` on both users + techs tables.
- **`is_admin()` allowlist was missing your actual email.** You sign in as `anne@mynailconnection.com` but the function only listed `annewilson1021@gmail.com`, so RLS treated you as a non-admin and blocked every admin-gated read. Updated the function to also accept your branded email AND to be case/whitespace-tolerant (`lower(btrim(...))`) so future admin adds don't hit the same trap.
- **`last_password_change` metric refined** — was counting all users with a NULL value (which included normal signed-up clients whose field was never stamped). Now counts only techs, giving the accurate "haven't accepted their invite yet" number.
- **`ALL_TECHS` const bug** — the home feed was using `window.ALL_TECHS` but `ALL_TECHS` is declared with `const` at module scope, which doesn't attach to `window`. Every feed lookup silently failed and the feed was always empty. Fixed by referencing `ALL_TECHS` directly.

### Posts / board

- `board_posts` INSERT rate-limit: **1 per hour per tech** (client-side guard with a clear "try again in X min" message)
- Post/delete operations now use authenticated tokens so RLS doesn't silently block
- "Posts" tab on profile actually shows your posts now
- Tagging UI: tap a tag chip → chip lights up, photo card stays open (previously the card slammed shut after every single tap)
- Portfolio tab on profile screen loads existing photos (was upload-only before)

### Other quality-of-life

- `closeModal()` fixed to handle both `.open` class AND inline `display:none` — was silently failing for modals opened via inline style, which is why the Cancel button in the Nudge modal was doing nothing
- `Edit Profile` button from the profile screen now works (modal was trapped inside an inactive parent screen; added `class="modal-overlay"` so DOMContentLoaded hoists it to `.device`)
- Browse-style mode switch no longer causes a scroll jump ("catch-up" regression on the punch-list)
- tech-detail page back button uses a smart fallback (was using a naive `_prevScreen` that could loop on itself)
- Inbox action row: color hierarchy makes Text-back obviously primary, Mark-read secondary, Delete subtle
- Status visibility polling: feed poll + various intervals skip when tab is backgrounded (cheaper battery on mobile)

### Punch-list additions

Ten items added to `/MNC/punch-list.html` covering:
- Contact Anne / push notification path fix
- "Open this week" → map filter hand-off
- Universal `Bearer SUPABASE_ANON_KEY` audit
- Email normalization DB trigger
- `contact_anne_messages` persistence (now done)
- `board_posts.expires_at` DB schema vs client drift
- Broadcast-push performance at scale (add `auth_user_id` FK to `public.users`)
- And others from testing

---

## Sharp edges you should know about

Nothing here blocks launch. All are logged on the punch-list and have clean paths forward.

1. **Push notifications only reach Anne's phone.** The "Nudge support" path writes to the Inbox reliably, but the accompanying push-notification goes only to `ANNE_USER_ID`. Leslie isn't pinged. Easy to fix — add her user_id to send-push targets — when she's ready to take pings.
2. **Supabase auth emails still say "noreply@supabase.co".** Branded SMTP + templates is a known follow-up.
3. **Realtime updates use polling (15s), not WebSockets.** The mini Supabase client the app uses doesn't fully implement postgres_changes subscriptions. Polling is cheap and works; upgrade path is either expanding the mini client or dropping in the official supabase-js.
4. **Geolocation for the feed's radius filter only kicks in if the user grants browser permission.** If denied, the feed becomes lenient (shows all posts) and the radius chips do nothing. That's fine — it's better than a confusing empty feed.
5. **The `is_admin()` function is a hard-coded email allowlist.** Adding a new admin requires editing SQL. Fine for 2-3 admins; gets annoying past 10.
6. **Messages from the Nudge flow have no archive path.** Delete is permanent. Not a bug, just a design choice — if you want a "resolved" state that keeps the message visible but greyed out, that's a change I can make.

---

## What to do before launch

### Must do — High-priority punch-list items still open:

1. **Stripe setup** — create products in Stripe Dashboard, paste payment links into `STRIPE_CONFIG` at `index.html:2600`, end-to-end test with a Stripe test card, confirm webhook grants credits. You've got Stripe open now — this is the right next thing.
2. **Decide `/` routing** — does `mynailconnection.com/` serve the marketing page (current CLAUDE.md assumption) or the app shell? Implications for Netlify config.
3. **Privacy + Terms** — send current `privacy.html` / `terms.html` to counsel. Current versions are labeled "stub" for a reason.
4. **Liability acknowledgment checkboxes** at tech + client signup (punch-list has the exact copy).
5. **International / at-volume readiness memo** — Supabase tier limits, Stripe international, email deliverability plan, legal (GDPR/CCPA).

### Must do — launch-time actions:

6. **Drag `deploy/app/` and `deploy/marketing/` to Netlify.** v86 bundle reflects the session work.
7. **Deploy the updated `broadcast-push` edge function** (one-time — required for the Push tab).
8. **Run the `btrim` email cleanup SQL** one more time to confirm all 17 techs have clean `public.techs.email` values.
9. **Invite the 17 techs** one at a time via Supabase Dashboard → Authentication → Users → Invite. Start with Leslie as the dry-run.

### Nice to do:
- Send yourself a heads-up text before each wave of invites so techs don't treat the Supabase email as spam
- Sign in as a real test client, tap "Nudge support", verify the message lands in your Inbox and the Text-back button opens SMS correctly
- Send a test broadcast push to "Admins only" to confirm the edge function is deployed

### Medium — can be done in parallel or right after launch:
- Google Search Console + Bing Webmaster + sitemap
- Turn on GA4 analytics
- Cookie/consent banner (only matters if you'll have EU/CA traffic at launch)
- "Open this week" filter bug — drops filter en route to map
- Bulk geocode run for techs without coordinates (map won't work for them without it)
- Android APK build + Play Store submission
- `Bearer SUPABASE_ANON_KEY` audit across the ~30 remaining fetch sites
- Email normalization DB trigger

### Can wait:
- Branded auth emails (Supabase default sender is fine for initial 17 techs with a heads-up text)
- `users` + `techs` schema consolidation
- Converting `is_admin()` to a `users.role` check instead of an email allowlist

---

## Final gut check

The app feels different now than it did at the start of this session. The admin side used to be a collection of cards and one-off tools; now it's a workflow. The client home used to be a static hub; now it has a live heartbeat. The invite experience used to be "here's a password, please set a new one, then sign in again" and was genuinely scary to roll out; now it's one tap.

The code got a little denser in some places (session persistence touches a lot of paths) but every addition came with either a test or a fallback or both. Nothing we added should be load-bearing without a graceful degradation path.

**But — the business layer around the app is still pre-launch work.** Payment, legal, liability, international compliance: none of those got touched this session, and all five are genuinely launch-blocking. The next focused session should be "Stripe + legal + liability checkboxes" — probably the last big push before you can start inviting real techs.

Enjoy the break. When you're back, open the punch-list and start at the top of the High section. You'll find it's meaningfully shorter than when we started — two items removed (Contact Anne modal fix + admin-stats migration both shipped), and the "dev contact" item has overlap with our new Inbox/Nudge flow — but the five named above are still real work.

---

*— Claude*
