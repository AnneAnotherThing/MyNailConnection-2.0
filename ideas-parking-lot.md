# MNC Ideas, Parking Lot

Non-committed product ideas for future MNC work. Add here rather than to memory so things don't get lost. Organized by theme.

## Push notification reminders

**Context (2026-04-23):** Push infrastructure is already live (per-device FCM/APNs tokens in `push_subscriptions`, `sendPushToUser()` working). Missing piece is a scheduled runner (pg_cron or scheduled Edge Function) to decide who to nudge.

Three reminder types Anne wants:

- **Flip-availability nudge:** tech has had `is_available=false` for a while. Needs a column tracking when it last went off, then a daily cron query against a 7-ish-day threshold.
- **Inactivity nudge:** tech hasn't signed in or uploaded in N days. Cheapest source: `auth.users.last_sign_in_at`. Copy: "we miss you."
- **Credits unlocked:** monthly `period_reset_at` just passed for a paid tech, "your 40 credits refilled!"

**Must build in from day one (push fatigue):**

- Frequency cap: max 1 reminder per tech per 24h
- Quiet hours: nothing 9pm–9am (tech local time if tracked, else reasonable UTC window)
- Dedupe window: don't repeat the same reminder type within N days
- Opt-out: notification settings screen, per type

Without these, push becomes "that app that nags me" and people mute notifications globally, which also breaks the purchase confirmations + booking pings that actually need to land.

**Estimate:** ~3-4 hours bundled (schema + one Edge Function + cron + fatigue guards + testing).

## Recovery-link deep-link into the app (post-launch)

**Context (2026-05-05):** At OG launch, tapping a recovery link from email opens the phone browser, NOT the app. Reason: Supabase's `generateLink({ type: 'recovery' })` returns an action_link starting with `https://<project>.supabase.co/auth/v1/verify?...&redirect_to=...`. The first hop is supabase.co, which isn't in our AASA / assetlinks. iOS Universal Links + Android App Links only fire on direct user taps to `mynailconnection.com`, not on 302 redirects from another domain. So the user lands in the browser, sets the password there (reset-password.html handles it fine), and then has to manually open the MNC app to sign in.

We mitigated for launch by adding "Set your password, then open the MNC app to sign in." to the OG letter copy. Functional but clunky, the app icon ought to launch directly.

**The fix (when there's appetite):**

1. Edit `generate-og-recovery-links.mjs`, instead of using `properties.action_link` (which is the supabase.co URL), construct a URL on our domain: `https://mynailconnection.com/app/reset-password.html?token_hash=${properties.hashed_token}&type=recovery`.
2. Edit `reset-password.html` (and `index.html` if it shares this code path) to read `token_hash` + `type` from the URL query string, then call `supabase.auth.verifyOtp({ token_hash, type: 'recovery' })` to exchange the token for a session. Existing logic only handles the `#access_token=...` hash fragment from the post-redirect path, needs an additional branch.
3. Rebuild iOS + Android via Capawesome Cloud Build. App Store resubmit is the slow part, 1-3 day review window.
4. Test end-to-end: tap a recovery email link on phone, app opens directly to `/app/reset-password.html`, sets session, signs them in.

**Why we didn't ship this with launch:** Capacitor bundles web assets into the native binary at build time (`webDir: deploy/ghpages/app`), so we can't OTA the JS change, it requires a fresh build + store resubmit. Apple just flipped on 2026-05-05 and we didn't want to delay launch by another review cycle for a "nice-to-have" UX polish.

**Estimate:** ~1-2 hours of code + however long Apple review takes. Worth bundling with the next iOS update that's already going out for some other reason.
