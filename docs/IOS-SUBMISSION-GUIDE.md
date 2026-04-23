# iOS submission guide — the Apple equivalent of your Android flow

You know the Android flow now: Android Studio builds an AAB, Play
Console hosts the listing, the whole thing runs off your Windows box.
iOS is the same shape but with every noun replaced and a harder
prerequisite list. This doc maps it term-for-term so you can see what
you already know.

## The big uncomfortable prerequisite

**You cannot ship to the App Store from Windows.** Apple requires Xcode,
which only runs on macOS. There are three realistic paths:

1. **Buy a Mac.** Cheapest viable: Mac mini M4 ~$600 refurb. This is
   what most indie shops do once they cross "we're shipping iOS" — it
   pays for itself in one ship cycle of not fighting cloud-Mac latency.
2. **Rent a Mac in the cloud.** MacStadium, MacinCloud, Scaleway
   Apple-Silicon-as-a-service — roughly $30–60/month for a VM you RDP
   into. Works, but laggy for the GUI-heavy parts of Xcode.
3. **GitHub Actions with `macos-latest`.** Free-ish for CI builds but
   you still need to do the Apple Developer setup, provisioning
   profiles, and first manual submission from a real Mac session.
   Usable for automation *after* you've done the human parts once.

Pick one before starting. If you're not sure, rent a MacinCloud session
for a day and try the flow end-to-end before committing to a Mac.

## Term-for-term mapping from what you know

Think of this as a translation table. Concepts are identical; names and
buttons differ.

| Android (what you know)                       | iOS equivalent                                     |
|-----------------------------------------------|----------------------------------------------------|
| Google Play Console                           | App Store Connect                                  |
| Play Console account — $25 one-time           | Apple Developer Program — **$99/year**             |
| Android Studio                                | Xcode (free on the Mac App Store)                  |
| `android/` folder (Capacitor output)          | `ios/` folder (Capacitor output)                   |
| `AndroidManifest.xml`                         | `Info.plist` (+ entitlements + capabilities)       |
| `build.gradle`                                | Xcode project settings + `Podfile`                 |
| `applicationId` `com.mynailconnection.app`    | Bundle ID — use the same: `com.mynailconnection.app` |
| `versionCode` / `versionName`                 | Build number (integer) / Marketing version         |
| Keystore (`.jks`) + Play App Signing          | Apple-issued signing certs + provisioning profiles |
| Upload key                                    | Distribution certificate                           |
| `google-services.json` (FCM)                  | `GoogleService-Info.plist` + APNs key (.p8) uploaded to Firebase |
| POST_NOTIFICATIONS permission                 | `Push Notifications` capability in Xcode           |
| App Links + `assetlinks.json`                 | Universal Links + `apple-app-site-association`     |
| `.aab` uploaded to Play Console               | `.ipa` uploaded via Xcode → Transporter → App Store Connect |
| Internal testing track                        | TestFlight (works the same way — invite by email)  |

That's the whole picture. If you hold both tabs open side by side, the
only genuinely new concept is signing: Apple is much more paranoid about
who is allowed to sign what, and you'll lose a couple of hours the first
time learning their vocabulary.

## The setup, end to end

### Phase 1 — One-time accounts and hardware

1. Enroll in the Apple Developer Program at developer.apple.com.
   $99/year, renews automatically. Individual enrollment (not
   Organization) is fine — Organization costs the same but requires a
   D-U-N-S number and takes 2–3 weeks. You can migrate later.
2. On the Mac: sign into Xcode with your Apple ID (Xcode → Settings →
   Accounts). Once the developer enrollment is active, Xcode will show
   your account as an "Apple Developer Program" team — that's the
   signing identity it'll use.

### Phase 2 — Add iOS to the Capacitor project

Run from the MNC repo root on your Mac:

```bash
npm install                    # installs existing deps
npm install @capacitor/ios     # add the iOS platform package
npx cap add ios                # scaffolds ios/App/App.xcworkspace etc.
npx cap sync ios               # copies www/ into ios bundle
npx cap open ios               # launches Xcode with the workspace
```

At this point `ios/` exists next to `android/` and you're in Xcode
looking at `App.xcworkspace`. **Always open `.xcworkspace`, never
`.xcodeproj`** — the workspace includes CocoaPods dependencies.

### Phase 3 — Configure the project in Xcode

Click the blue project icon at the top of the left sidebar → select the
"App" target. You'll see a tab bar: General, Signing & Capabilities,
Resource Tags, Info, Build Settings, Build Phases, Build Rules.

**General tab:**
- Display Name: `My Nail Connection`
- Bundle Identifier: `com.mynailconnection.app` (must match Android
  for brand consistency — not technically required but simplifies
  cross-platform analytics and App Links config)
- Version: `1.0` (this is marketing version, what users see)
- Build: `1` (this is the integer you bump every upload)
- Deployment Target (Minimum Deployments): iOS 13.0 is a safe floor.
  iOS 14 is stricter but still 95%+ of devices.

**Signing & Capabilities tab:**
- Check "Automatically manage signing"
- Team: select your Apple Developer Program team
- Xcode will auto-create a development provisioning profile. Good.
- Click **+ Capability** and add:
  - **Push Notifications** (your Android equivalent of POST_NOTIFICATIONS)
  - **Associated Domains** (your equivalent of App Links intent-filter)
    - Under Associated Domains, add: `applinks:mynailconnection.com`

**Info tab (the Info.plist entries):**
- Camera/photo picker: the app lets techs upload photos, so you'll need
  `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`.
  Apple rejects apps that access these without human-readable strings
  explaining why.
- Location (for the "techs near you" feature):
  `NSLocationWhenInUseUsageDescription`.
- Everything else defaults through Capacitor.

### Phase 4 — Universal Links (the iOS App Links twin)

Universal Links need two things — one in the app, one on your website:

1. **In the app:** `Associated Domains: applinks:mynailconnection.com`
   capability (done in Phase 3).
2. **On your website:** a JSON file at
   `https://mynailconnection.com/.well-known/apple-app-site-association`
   Note: **no file extension**, but the file IS JSON. iOS fetches it
   when the app is installed and caches the result.

The file lives next to your existing `assetlinks.json`. When you're
ready, I'll add a template. The shape you need:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.com.mynailconnection.app",
        "paths": ["/app/*"]
      }
    ]
  }
}
```

`TEAMID` is your Apple Developer team ID — a 10-character alphanumeric
like `1A2B3C4D5E`. Find it at developer.apple.com → Account → Membership.

Also: GH Pages serves extensionless files with `content-type: text/html`
by default, which iOS *will* reject. You may need a build-time rename
trick or a tiny `.htaccess`-style shim. If that bites, ping me and I'll
solve it before you need to test on device.

### Phase 5 — Icons and launch screen

Capacitor scaffolds these as placeholders. You'll need to drop real
assets into `ios/App/App/Assets.xcassets/AppIcon.appiconset/`. Apple
wants the full icon set (1024×1024 for App Store, plus 20, 29, 40, 60,
76, 83.5, 120, 152, 167, 180 pt variants in 1x/2x/3x). Easiest path:
use a generator like appicon.co or `@capacitor/assets`:

```bash
npm install -D @capacitor/assets
# Drop a 1024x1024 source icon at assets/icon.png
npx capacitor-assets generate --ios
```

That script generates every size and places them correctly. Same script
will regenerate Android icons too — worth running once for both.

### Phase 6 — Push notifications (APNs side)

Firebase is the same for iOS; the new piece is Apple's APNs key:

1. developer.apple.com → Certificates, Identifiers & Profiles → Keys → +
2. Name: "MNC APNs", check "Apple Push Notifications service (APNs)"
3. Download the `.p8` file (you get ONE download — save it)
4. Note the Key ID (10 chars) and your Team ID
5. Firebase Console → Project Settings → Cloud Messaging → Apple app
   configuration → upload the .p8 with Key ID and Team ID

FCM now bridges to APNs on iOS. Same `sendPushToUser` function on the
backend works for both platforms — no Edge Function changes needed.

### Phase 7 — First build to a physical device

1. Plug an iPhone into the Mac. Unlock it, tap "Trust this computer."
2. In Xcode, at the top next to the "Run" triangle, pick the device.
3. Hit the triangle. First launch: the device will say "Untrusted
   Developer" and refuse. Settings → General → VPN & Device Management
   → your team → Trust. Run again, app launches.
4. Test push: register a tech account, confirm the APNs token lands in
   Supabase `push_tokens`, send yourself a push from the admin UI.

### Phase 8 — Upload to App Store Connect (TestFlight)

1. **Product → Archive** (not Build). Xcode archives the build — this
   takes a couple minutes.
2. Organizer window opens. Select your archive → **Distribute App** →
   App Store Connect → Upload.
3. Xcode uploads the .ipa. Takes 10-30 minutes end to end. You get an
   email when it's processed.
4. appstoreconnect.apple.com → My Apps → (you'll need to create the app
   listing first — bundle ID, name, primary language, SKU) → TestFlight
   tab. Your build appears after processing.
5. TestFlight → Internal Testing → create group → add Leslie's email.
   She installs TestFlight on her phone, accepts the invite, gets the
   build. Same experience as Play internal testing.

### Phase 9 — Store listing + submit for review

App Store Connect requires screenshots and metadata *before* submission.
The exact screenshot specs for the current device sizes:

- 6.9" (iPhone 16 Pro Max): 1320 × 2868 px — **required**
- 6.5" (older Pro Max): 1284 × 2778 px — required if you target iOS 14
- 5.5" (legacy): 1242 × 2208 px — optional now, required only if you
  support really old devices

You need 2–10 screenshots per size. Easiest workflow: run the app in
the iOS Simulator at each size, take screenshots (Cmd+S), upload.

Listing metadata you'll need:
- Name (30 chars)
- Subtitle (30 chars)
- Promotional text (170 chars, editable without resubmission)
- Description (4000 chars)
- Keywords (100 chars, comma-separated, not visible to users)
- Support URL, Marketing URL (both can be mynailconnection.com)
- Privacy Policy URL (mynailconnection.com/privacy.html)
- App Privacy section — you'll declare what data the app collects
  (email, location, photos). Takes 10 mins to fill out.
- Age rating — run through the questionnaire. MNC is 4+ unless the
  photo board content counts as user-generated content, in which case
  it's 12+ (for the "infrequent/mild" UGC rating).
- Content rights — check "No" to "Does your app contain third-party
  content?" unless you're surfacing licensed material.

Once everything's filled in, hit **Submit for Review**. Apple's current
average review time is 24–48 hours. If they reject, they give you
specific reasons — usually something like "add a test account so we can
sign in" (solution: create a demo tech account, put its credentials in
App Review Information → Sign-In Required fields).

## Cost summary

- Apple Developer Program: $99/year
- Mac (if you don't have one): $600+ one-time, or ~$40/mo cloud
- Everything else: $0

Compare to Android's $25 one-time Play Console fee. The delta is real
but it's the cost of iOS distribution in general, not anything special
about MNC.

## Timeline expectation, ballpark

Realistic first-ship timeline from "bought Apple Developer account" to
"Leslie has TestFlight install":

- Day 1: Mac setup, Xcode install, Apple Developer enrollment
  (enrollment can take 24-48h to activate)
- Day 2: `npx cap add ios`, Xcode project config, first build on
  simulator, first build on real device
- Day 3: Icons + launch screen + push setup
- Day 4: Universal Links file on marketing site, Archive + upload,
  App Store Connect listing stub, TestFlight to Leslie

Budget a full week. Nothing's hard individually; each step has one
obscure Apple thing that costs you 30–60 minutes the first time.

## Things that will bite you (I'll flag these pre-emptively)

1. **"No signing certificate found"** on first build — solved by
   signing into Xcode with your Apple ID and waiting ~5 min after
   enrollment activates.
2. **Archive greyed out in Xcode** — you built for a simulator, not a
   real device or "Any iOS Device". Set the destination to "Any iOS
   Device (arm64)" at the top of Xcode, then Archive works.
3. **"Missing Push Notifications entitlement"** at upload — you added
   the capability but Xcode didn't regenerate the provisioning profile.
   Signing & Capabilities → toggle "Automatically manage signing" off
   and back on.
4. **Apple-App-Site-Association file returns 404 or wrong MIME type**
   — fix this on the marketing domain before wasting time debugging in
   the app. `curl -I https://mynailconnection.com/.well-known/apple-app-site-association`
   should return 200 and `content-type: application/json`.
5. **"App Tracking Transparency"** — if you ever add analytics SDKs
   that track across apps (Facebook, AppsFlyer, etc.), you'll need ATT
   prompts. MNC doesn't today, so skip. If you add Mixpanel or similar
   later, we'll revisit.

## What I'd do in your shoes

You don't have to ship iOS on day one of Android release. Realistic
framing: get the Android release stable, collect feedback from Leslie
and the first 10 techs, THEN decide if iOS is the next battle. The
$99/yr + Mac + week of setup is only worth it if you're seeing enough
demand from iPhone users to justify the time.

If Leslie and the first wave of techs are mostly Android users
anyway, ship Android alone for 4–8 weeks, gather real usage data,
then budget the iOS work into a focused sprint. I know you've already
been thinking this — just putting it in writing because "we should
also do iOS!" is how most indie apps burn a month on a platform their
users don't want yet.
