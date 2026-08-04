# Native push (FCM/APNs) — bring-up runbook

_2026-08-03. Store apps are the priority; native push is the missing piece.
The code is ready on both ends — what remains is Firebase/Apple console work
(Anne) and one build. Android first: it needs no Apple paperwork and can be
tested by sideloading the APK the same day._

## Already done (code, shipped on v3)

- Client: `initCapacitorPush()` in index.html registers, grabs the device
  token, and saves it to `push_subscriptions` (p256dh='native',
  auth='android'|'ios', endpoint=token) using the signed-in user's bearer.
  Success/failure toasts on-device.
- Server: `supabase/functions/send-push/index.ts` now sends web rows via
  VAPID and native rows via FCM HTTP v1 (needs the `FCM_SERVICE_ACCOUNT`
  secret; until it's set, native rows report `skipped`, web keeps working).
- Android gradle: already wired — the google-services plugin applies
  automatically the moment `android/app/google-services.json` exists.
- `NATIVE_PUSH_REGISTER_ENABLED` is still **false**. Do NOT flip it until
  google-services.json is confirmed in the build — register() without it
  hard-crashes the Android app (the 2026-04-30 Google-review rejection).

## Anne's steps — Android (do first)

1. **Firebase project**: console.firebase.google.com → Add project (name:
   "My Nail Connection", Analytics optional/off).
2. **Add Android app**: package name exactly `com.mynailconnection.app`.
   Download **google-services.json** and drop it at
   `android/app/google-services.json` in the 3.0 repo (tell Claude — it gets
   committed; it contains no secrets).
3. **Service account key**: Firebase console → ⚙ Project settings →
   Service accounts → **Generate new private key** (downloads a JSON).
4. **Supabase secret**: dashboard (nwqnakoongrorbwnrqzc) → Edge Functions →
   Secrets → add `FCM_SERVICE_ACCOUNT` = the ENTIRE contents of that JSON,
   pasted as one value.
5. **Deploy send-push**: dashboard → Edge Functions → send-push → replace
   code with the repo's `supabase/functions/send-push/index.ts` → deploy.

## Then (Claude + Anne together)

6. Flip `NATIVE_PUSH_REGISTER_ENABLED = true`, sync, commit, snapshot, push.
7. Build the Android app (Capawesome, versionCode already bumping each sync).
   Confirm the build log shows `google-services` plugin applied.
8. **Sideload test** (no store review needed): install the APK on Anne's
   Android phone → sign in → tap "Say yes to notifications" → OS prompt →
   Allow → expect "Notifications are on 💅" toast → Claude fires
   `scripts/refire-test-push.sh` → phone buzzes.
9. Then submit to Play (internal testing → production at will).

## Anne's steps — iOS (after Android proves out)

1. Apple Developer → Certificates, IDs & Profiles → Keys → add key with
   **Apple Push Notifications service (APNs)** enabled → download the .p8
   (note Key ID + Team ID).
2. Firebase console → Project settings → Cloud Messaging → Apple app
   configuration: **add iOS app** (bundle id `com.mynailconnection.app`),
   upload the .p8 with Key ID + Team ID.
3. Download **GoogleService-Info.plist** → `ios/App/App/` in the repo.
4. Xcode capability "Push Notifications" must be on the App target
   (check `ios/App/App/App.entitlements` — aps-environment).
5. `bash deploy/bump-marketing.sh` BEFORE the iOS build (train-closed trap).
6. Build via Capawesome → TestFlight → same test as Android step 8.

## Notes

- FCM v1 delivers to BOTH platforms once the APNs key is uploaded — the
  edge function needs no iOS-specific changes.
- broadcast-push still speaks web-push only; separate follow-up task exists.
- The PWA/web push path stays as-is and keeps working alongside native.
