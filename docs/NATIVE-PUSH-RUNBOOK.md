# Native push (FCM + APNs) — bring-up runbook

_Updated 2026-08-15. Android is live. iOS is code-complete and waiting on one
Apple key. The web/PWA push path is unchanged and keeps working alongside both._

## Where each platform stands

| Platform | Path | State |
|---|---|---|
| Web / PWA | Web Push (VAPID) | Live |
| Android | FCM HTTP v1 | Live, proven on Anne's phone |
| iOS | APNs, direct | Code done, needs the .p8 key and a deploy |

## How a push is routed

`push_subscriptions` holds one row per device. `p256dh` is the discriminator:

- `p256dh` = a real key → web/PWA row, sent with VAPID.
- `p256dh` = `'native'` → `auth` holds the platform and `endpoint` holds the
  device token.
  - `auth` = `'android'` → FCM HTTP v1.
  - `auth` = `'ios'` → APNs directly.

## Why iOS does not go through FCM

The previous version of this runbook told you to add an iOS app in Firebase,
upload the .p8 there, and drop `GoogleService-Info.plist` into the repo. That
would not have worked, and it is worth writing down why so nobody tries again.

Routing iOS through FCM requires the Firebase SDK to be running inside the iOS
app, because FCM delivers to a *Firebase* registration token, which only exists
if `FirebaseMessaging` is in the build and has been handed the APNs token. This
app has none of that: no `GoogleService-Info.plist`, no `FirebaseMessaging` pod
in `ios/App/Podfile`, and an `AppDelegate.swift` that forwards the raw APNs
token straight to the Capacitor plugin. Capacitor's own documentation for the
`registration` event says the token is the APNs token on iOS and the FCM token
on Android.

So the iOS rows in `push_subscriptions` have always held raw APNs tokens, and
the edge function has always sent them to FCM, which cannot deliver to them.
Every iPhone push failed on the server, not on the phone.

Adding Firebase to the iOS build would mean a Podfile change, a new native
dependency, and AppDelegate surgery, all pushed through a Capawesome cloud
build. That is the same class of change that hard-crashed the Android app on
2026-04-30 and drew the Google review rejection. Talking to Apple directly
needs zero native changes: the app is already correct.

The iOS app side is already complete and needs no edits:

- `ios/App/App/App.entitlements` has `aps-environment` = `production`.
- `ios/App/App/Info.plist` has `UIBackgroundModes` = `remote-notification`.
- `ios/App/Podfile` has `CapacitorPushNotifications`.
- `AppDelegate.swift` forwards both the token and the failure to the plugin.
- `initCapacitorPush()` in `index.html` saves the token with `auth: 'ios'`.

## Anne's steps — iOS

Everything here is console and dashboard work. No build, no store submission,
no app change. The currently shipped iOS build will start receiving pushes the
moment the secrets are set and the functions are deployed.

1. **Get the key.** developer.apple.com → Certificates, Identifiers & Profiles
   → Keys → the **+** button. Name it something like "MNC Push". Tick
   **Apple Push Notifications service (APNs)**. Continue, then Register.
2. **Download the .p8.** It downloads exactly once and cannot be re-downloaded,
   so put it somewhere you keep things. On the same screen, note the
   **Key ID** (10 characters).
3. **Team ID: `YYS8GZPZ78`.** Already known, no lookup needed. It is the
   `DEVELOPMENT_TEAM` the app is signed with in
   `ios/App/App.xcodeproj/project.pbxproj`, and the portal shows the same
   value top right next to your name.

   **The key MUST come from this team.** Apple validates the key's team
   against the app's bundle ID, so a .p8 minted under any other team returns
   `InvalidProviderToken` for `com.mynailconnection.app` no matter what else
   is correct. If developer.apple.com shows "Join the Apple Developer Program"
   and no "Certificates, Identifiers & Profiles" section, you are signed in
   with an Apple ID that is not a member of this team. Do not enroll that
   account, that creates a second empty team. Find the Apple ID that gets into
   App Store Connect for MNC and use that one. Creating keys also requires the
   Account Holder or Admin role; a Developer-role member sees Keys read-only.
4. **Set five secrets.** Supabase dashboard (project `nwqnakoongrorbwnrqzc`) →
   Edge Functions → Secrets:

   | Secret | Value |
   |---|---|
   | `APNS_PRIVATE_KEY` | the entire contents of the .p8 file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
   | `APNS_KEY_ID` | the 10-character Key ID from step 2 |
   | `APNS_TEAM_ID` | the 10-character Team ID from step 3 |
   | `APNS_BUNDLE_ID` | `com.mynailconnection.app` (optional, this is the default) |
   | `APNS_ENV` | `production` (optional, this is the default) |

   Open the .p8 in Notepad to copy it. It is a short text file. If all three of
   the first three secrets are not set, iOS rows report `skipped` and nothing
   else changes, exactly the way Android rows did before FCM was configured.

5. **Deploy both functions.** Supabase dashboard → Edge Functions → replace the
   code with the repo copy and deploy, for **both**:
   - `send-push` ← `supabase/functions/send-push/index.ts`
   - `broadcast-push` ← `supabase/functions/broadcast-push/index.ts`

   `send-push` also picks up high-priority delivery and the error reporting in
   this deploy, so an overnight booking wakes a sleeping phone immediately
   instead of waiting for a battery window.

6. **Test.** On the iPhone: open the app, sign in, accept notifications, wait
   for the "Notifications are on 💅" toast. That toast means the token reached
   `push_subscriptions`. Then tell Claude and it fires a probe at that account.

## Reading the response

`send-push` returns counts, so a failed send says why instead of going quiet:

- `{ sent: 1 }` — delivered to Apple. If the phone shows nothing after this,
  the problem is on the device (Focus mode, notifications off for the app).
- `{ sent: 0, reason: 'no subscriptions found' }` — no row for that identity.
  The device never registered, or registered under a different identity.
  `push_subscriptions.user_id` is the lowercased email, or the E.164 phone for
  phone accounts.
- `{ skipped: 1, note: 'iOS rows skipped: ...' }` — the secrets are missing or
  incomplete. Step 4.
- `{ failed: 1, errors: ['APNs send failed: 403 ...InvalidProviderToken'] }` —
  the Key ID, Team ID, or .p8 do not match each other. Recheck step 4. A common
  cause is pasting the .p8 with the BEGIN/END lines stripped off.
- `{ failed: 1 }` with the row gone — Apple returned 410 Unregistered or 400
  BadDeviceToken, meaning that token is permanently dead, so the row was
  pruned. The device re-registers next time the app opens.

## The reinstall rule, worth knowing permanently

Reinstalling the app invalidates the old device token, and the server prunes it
on the next failed send. It re-registers automatically, but only when the app
is opened and signed in. So **after every store update, a device has to open
the app once before pushes resume**. An empty subscription row right after an
update is expected, not a bug.

## Notes

- Sandbox vs production: TestFlight and App Store builds use production APNs,
  which is what `aps-environment` is set to. A debug build run straight from
  Xcode uses sandbox. `sendApns` retries once on the other host when Apple
  answers `BadDeviceToken`, so a debug build still works without changing
  `APNS_ENV`, and a good token never gets pruned by mistake.
- The APNs block is duplicated byte-for-byte in `send-push` and
  `broadcast-push`. Both are paste-deployed from the dashboard, so a shared
  import would break the paste. Change one, change both.
- iPhone users who never install the app still get the PWA path, unchanged.
