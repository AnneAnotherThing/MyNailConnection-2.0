# MNC: Old Supabase -> New Pro Project Migration Runbook

Created 2026-07-06 during the old project's hard outage.

- OLD: `ktiztunuifzbzwzyqrrq` (free org "My Nail Connection", nano,
  status Unhealthy, NO backups). All tech/client data, auth accounts,
  and photos live ONLY here until Phase 1 completes.
- NEW: `nwqnakoongrorbwnrqzc` ("My Nail Connection 3", Hive-Rise Pro
  org, micro 1GB, us-east-1). Created 2026-07-06. DB password is in
  Anne's password manager (never in this repo).

## Phase 0, done
New project created in the Pro org. Micro compute (covered by Pro's
$10 credit). Data API enabled. Same region as old (us-east-1).

## Phase 1, THE RESCUE (the moment the old project answers)
Watcher alerts us. Then immediately, old project dashboard ->
Settings -> Database -> connection string (direct, port 5432):
1. `supabase db dump --db-url "<OLD_URL>" -f schema.sql`
2. `supabase db dump --db-url "<OLD_URL>" --data-only -f data.sql`
   (includes auth.users/auth.identities rows, password hashes move)
3. Storage inventory: list buckets + objects via storage API with the
   OLD service_role key (Settings -> API), download all objects to
   a local folder (script this; photos are the business).
Do NOT restart/resize/change the old project until these finish.

## Phase 2, restore into NEW
1. Run schema.sql against the new project (SQL editor or psql).
2. Run data.sql.
3. Run our sql/ files in order (idempotent, fills anything newer than
   the dump): rls-starter/rls-fix if needed, booking-system,
   booking-tier1, booking-standing, blocklist-pause.
4. Recreate storage buckets (same names/public settings), upload the
   downloaded objects. NOTE: photo URLs embedded in techs.photos JSONB
   contain the OLD project domain -> run a one-shot UPDATE rewriting
   `ktiztunuifzbzwzyqrrq.supabase.co` -> `nwqnakoongrorbwnrqzc.supabase.co`
   in techs.photos, paused_photos, user_inspo.photo_url, users.image_url,
   techs.image_url.

## Phase 3, edge functions + secrets
`supabase functions deploy` for: send-push, broadcast-push,
admin-reset-passwords, delete-account, revenuecat-webhook,
stripe-webhook (deploy the v3 version, pause-on-cancel already
removed).
Secrets to set on NEW:
- VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT. CRITICAL: the
  private key can NOT be read back from the old project. If Anne has
  it saved, reuse it and existing push subscriptions survive. If not:
  generate a new pair, update the public key in index.html
  (subscribeToPush), and all users re-subscribe on next login (the
  prompt re-fires; subscriptions table rows for old key are dead).
- STRIPE_WEBHOOK_SECRET: create a NEW webhook endpoint in Stripe
  pointing at the new project's stripe-webhook URL, copy its signing
  secret. Same for the RevenueCat webhook URL.

## Phase 4, auth configuration (see memory: mnc password reset quirks)
- Confirm email: ON (deliberate, anti-sybil)
- Site URL: https://mynailconnection.com/app/
- Redirect URLs: app URL + reset-password.html
- Email templates: links use /app/?token_hash=...&type=recovery (and
  type=email for signup confirm), NOT redirect_to. Copy templates
  from the old project if reachable, else rebuild from
  sql/../memory notes.

## Phase 5, app swap (v3 branch first, main at cutover)
New URL + anon key (Settings -> API on the new project) into:
- index.html (2 spots: main config + inline fallback ~line 18k)
- reset-password.html
- marketing.html + granular trackers (marketing_hits/store_clicks)
- admin-stats.html, stats.html, punch-list.html
Then deploy/sync.sh.
DECISION NEEDED: 2.0 native app builds have the OLD url baked in.
Swapping main before the 3.0 store builds ship means native users
break (web/PWA users are fine, they get the new file). Options:
(a) swap main immediately, accept native breakage until 3.0 builds,
(b) keep old project alive read-only until 3.0 store approval.

## Phase 6, verify + retire
- booking_e2e.py against the new project (swap URL/key in script)
- Real sign-in, photo upload, gallery, booking round-trip
- UptimeRobot monitors -> point at NEW project URL
- Old project: keep paused as fossil for 30 days, then delete.
