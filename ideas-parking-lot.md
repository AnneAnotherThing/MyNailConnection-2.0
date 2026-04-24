# MNC Ideas — Parking Lot

Non-committed product ideas for future MNC work. Add here rather than to memory so things don't get lost. Organized by theme.

## Push notification reminders

**Context (2026-04-23):** Push infrastructure is already live (per-device FCM/APNs tokens in `push_subscriptions`, `sendPushToUser()` working). Missing piece is a scheduled runner (pg_cron or scheduled Edge Function) to decide who to nudge.

Three reminder types Anne wants:

- **Flip-availability nudge:** tech has had `is_available=false` for a while. Needs a column tracking when it last went off, then a daily cron query against a 7-ish-day threshold.
- **Inactivity nudge:** tech hasn't signed in or uploaded in N days. Cheapest source: `auth.users.last_sign_in_at`. Copy: "we miss you."
- **Credits unlocked:** monthly `period_reset_at` just passed for a paid tech — "your 40 credits refilled!"

**Must build in from day one (push fatigue):**

- Frequency cap: max 1 reminder per tech per 24h
- Quiet hours: nothing 9pm–9am (tech local time if tracked, else reasonable UTC window)
- Dedupe window: don't repeat the same reminder type within N days
- Opt-out: notification settings screen, per type

Without these, push becomes "that app that nags me" and people mute notifications globally — which also breaks the purchase confirmations + booking pings that actually need to land.

**Estimate:** ~3-4 hours bundled (schema + one Edge Function + cron + fatigue guards + testing).
