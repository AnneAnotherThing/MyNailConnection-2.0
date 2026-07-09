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

## Phase 2.5, DO IT RIGHT (cleanups applied during import, Anne-approved)

Leave behind (do NOT import; the local dump file is the archive):
- nail_techs, tech_photos, conversations, messages (2.0-legacy, locked
  admin-only, superseded years of features ago)
- board_posts (the posts/feed feature is deleted in 3.0)
- founders_feedback, launch_tracker, wipe/test leftovers
- analytics history (events, marketing_hits, store_clicks,
  app_downloads, tech_events): import structure + last 90 days only;
  full history stays in the archive dump. These tables were the bulk
  of row volume on an instance that died of resource starvation.
- auth orphans: run the auth-orphan-audit logic against the dump and
  skip auth.users rows with no profile (known 2.0 wart).

Fix permanently during import:
- EMAIL CASING: normalize every email column to lower(btrim()) once,
  then add CHECK (email = lower(email)) on techs.email and
  users.email. The casing bug family dies here.
- BOOKINGS LEGACY COLUMNS: drop booking_date, booking_time, notes
  after import; update create_booking to stop filling them (they were
  2.0 leftovers we were feeding for compatibility that no longer
  exists on a fresh project).
- IDENTITY BRIDGE: add users.auth_id uuid + techs.auth_id uuid,
  populated by joining auth.users on lower(email) during import. The
  app keeps its email keys for now (rekeying is app-rewrite scope),
  but every future feature can join on a real uuid, and the
  public.users.id-vs-auth.uid confusion that caused the bookings FK
  landmine can never bite again.
- AUTH HARDENING (dashboard): enable leaked-password protection,
  minimum password length 8+. Free wins on a fresh project.

Known warts deliberately NOT fixed now (rewrite-scope, list for 3.1):
- Email-as-identity throughout the app (hundreds of call sites)
- techs.photos as a JSONB array instead of a photos table (the
  autosave RPCs exist to paper over it)
- techs RLS "select using(true)" exposes phone/street address columns
  to anon API callers even when hide_address_public is on (the flag
  is UI-only). Needs a public view or column split; note for 3.1.

Born right on the new project (no action): Postgres 17, daily backups
(Pro), micro compute, Data API on, same region as old.

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
- DONE 2026-07-08 on new project: Site URL = https://mynailconnection.com/app/ ;
  Redirect URLs = https://mynailconnection.com/app/** and
  http://localhost:8123/** . (Mgmt API api.supabase.com was flaky during
  the incident; the redirect save needed one retry. Re-verify these stuck
  once the incident clears.)
- STILL TODO (do in one clean pass after incident clears):
  - Confirm email: verify ON (deliberate, anti-sybil)
  - Password hardening: leaked-password protection ON, min length 8+
  - Email templates: links use /app/?token_hash=...&type=recovery (and
    type=email for signup confirm), NOT redirect_to. Copy templates
    from the old project if reachable, else rebuild from memory notes.

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
