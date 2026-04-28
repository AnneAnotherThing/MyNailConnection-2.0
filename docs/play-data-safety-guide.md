# Google Play Data Safety Form — MNC

Drafted 2026-04-28 from a code audit of the MNC repo. Each section maps to the
exact wording in Play Console → Policy → App Content → Data Safety.

There are three big sections in Play's questionnaire: **Data collection &
sharing** (what data, why), **Security practices** (encryption + deletion),
and **Data types** (the long checklist). I'll walk through them in order.

---

## SECTION 1 — Does your app collect or share any of the required user data types?

Answer: **Yes**

(Selecting "No" requires the app to truly send nothing off-device. MNC sends
auth, photos, location queries, and push subscriptions to Supabase / Stripe /
Google / OSM — so it's "Yes".)

---

## SECTION 2 — Is all of the user data collected by your app encrypted in transit?

Answer: **Yes**

All external endpoints are HTTPS — Supabase, Stripe, Google Maps, OpenStreetMap
Nominatim, Cloudflare. The codebase has zero plain-`http://` API calls (audit
confirmed 24+ HTTPS calls, no HTTP ones). Capacitor's `androidScheme` is also
configured to `https`.

---

## SECTION 3 — Do you provide a way for users to request that their data be deleted?

Answer: **Yes**

Method: **Outside-the-app request.** Users can email support or use the
"Contact Anne" form inside the app to request account + data deletion.

> **CONFIRM before submitting:** open `privacy.html` and make sure it
> documents this exactly. Play will check your privacy policy URL and
> reject the form if it doesn't say something like:
>
> > "To request deletion of your account and associated data, contact us
> > at [your email] or use the Contact Anne form within the app. We'll
> > delete your account, profile data, photos, and messages within 30 days."
>
> If `privacy.html` doesn't already say this, add the paragraph before
> pushing. (See "Privacy policy patch" at the bottom of this doc.)

---

## SECTION 4 — Data types collected or shared

For each row below, the form asks four questions per type:

1. **Is this data collected or shared?** → Collected / Shared / Both / Neither
2. **Is collection optional or required?** → Optional means user can use the app without providing it
3. **What's it used for?** → choose all purposes that apply
4. **Is the data processed ephemerally?** → Yes only if literally never stored

Play's definition reminder:
- **Collected** = sent off the device (even just to your own backend).
- **Shared** = sent to a *third party for their use* (NOT for service providers acting on your behalf). Supabase storing your data for you ≠ shared. Stripe processing a payment ≠ shared. Google ad targeting *would* be shared.

### Personal info → Email address
- **Collected:** Yes
- **Shared:** No
- **Required:** Yes (used for signup/login)
- **Purposes:** Account management, App functionality
- **Ephemeral:** No

### Personal info → Name
- **Collected:** Yes
- **Shared:** No
- **Required:** Yes (display name shown on profile + posts)
- **Purposes:** Account management, App functionality
- **Ephemeral:** No

### Personal info → User IDs
- **Collected:** Yes
- **Shared:** No
- **Required:** Yes (Supabase auth user UUID)
- **Purposes:** Account management, App functionality
- **Ephemeral:** No

### Personal info → Address, Phone number, Race/ethnicity, Sexual orientation, Gender identity, Religious beliefs, Political views, Other info
- **Collected:** No

### Financial → Purchase history
- **Collected:** Yes
- **Shared:** No
- **Required:** No (only collected if user subscribes / buys photo bundles via Stripe)
- **Purposes:** App functionality, Account management
- **Ephemeral:** No
- *(MNC stores subscription state and purchase records in Supabase. The card itself never touches MNC's servers — Stripe Payment Links handle that.)*

### Financial → User payment info, Credit score, Other financial info
- **Collected:** No
- *(Stripe receives card details directly from the user's browser via Stripe-hosted Payment Links. MNC never sees them.)*

### Location → Approximate location
- **Collected:** Yes
- **Shared:** No
- **Required:** No (user-typed city is optional)
- **Purposes:** App functionality (showing local techs)
- **Ephemeral:** No
- *(City/state derived from user-typed search via OpenStreetMap reverse geocode. Stored as a string. No GPS coordinates collected.)*

### Location → Precise location
- **Collected:** No
- *(No `navigator.geolocation` calls, no Capacitor Geolocation plugin. User types their city; lat/lng is not stored.)*

### Messages → Emails, SMS or MMS, Other in-app messages
- **Collected:** No
- *(MNC has admin-broadcast notifications and the "Contact Anne" form — neither is peer-to-peer messaging. The form text gets sent via push/email to Anne but isn't stored as a "message" between users.)*

### Photos and videos → Photos
- **Collected:** Yes
- **Shared:** No
- **Required:** No (user can browse without uploading)
- **Purposes:** App functionality, Personalization
- **Ephemeral:** No
- *(User-uploaded nail art photos stored in Supabase Storage.)*

### Photos and videos → Videos
- **Collected:** No

### Audio files → Voice/sound recordings, Music files, Other audio files
- **Collected:** No

### Files and docs
- **Collected:** No

### Calendar → Calendar events
- **Collected:** No

### Contacts → Contacts
- **Collected:** No

### App activity → App interactions, In-app search history, Installed apps, Other user-generated content, Other actions
- **Collected:** No
- *(No analytics SDK — no Google Analytics, Firebase Analytics, Sentry, PostHog, Mixpanel. Audit found zero telemetry hooks.)*

### Web browsing → Web browsing history
- **Collected:** No

### App info and performance → Crash logs, Diagnostics, Other app performance data
- **Collected:** No
- *(No Crashlytics, no Sentry. If you ever add one, this row flips to Yes.)*

### Device or other IDs → Device or other IDs
- **Collected:** Yes
- **Shared:** No
- **Required:** No (only collected if user grants notification permission)
- **Purposes:** App functionality (push notifications)
- **Ephemeral:** No
- *(Web Push subscription endpoint + keys stored per-user in Supabase `push_subscriptions` table. Used to deliver push notifications. NOT used for advertising or cross-app tracking. No advertising ID, no Android ID, no IDFA.)*

### Health and fitness → Health info, Fitness info
- **Collected:** No

---

## Privacy policy URL

Enter: **`https://mynailconnection.com/privacy.html`**

Play will fetch this URL and check it's reachable. If it returns a 404 or
points to something Play can't read (PDF, login wall), the form is rejected.
You can verify with `curl -I https://mynailconnection.com/privacy.html` after
your push lands.

---

## Privacy policy patch — required additions

Before you submit the Data Safety form, your `privacy.html` should contain
clear sections covering:

1. **What data we collect** (matches the rows above: email, name, photos, approximate location, push subscription, purchase history)
2. **Why we collect it** (account, app functionality, push notifications, billing)
3. **Who we share it with** (Supabase as our database provider, Stripe for billing, Google/OpenStreetMap for location lookup — all as service providers, not third-party data sharing)
4. **How long we keep it** (until account deletion)
5. **How users can request deletion** ← Play specifically checks for this
6. **Contact info** (your email, the Contact Anne form)
7. **Children's privacy** (the app is not directed to children under 13 / 16 EU)
8. **Last updated date**

If `privacy.html` is missing any of these, Play may reject the form even
when the answers above are accurate. Tell me if you want me to read your
current `privacy.html` and patch in whatever's missing.

---

## Quick sanity checklist before clicking "Submit" in Play Console

- [ ] All "Yes/No" rows above match the questionnaire
- [ ] Privacy policy URL is reachable (HTTP 200)
- [ ] Privacy policy mentions data deletion path (in-app Contact Anne or email)
- [ ] No "Yes" rows for data the app doesn't actually collect (false-positive declarations are also a violation)
- [ ] If you ever add analytics/Crashlytics/Sentry: come back and update this form

---

## Items that will need updating later (not blocking ship)

- **If you add iOS in-app purchases via Apple IAP** for Glow Up subscription on iOS: that becomes a "Financial info / Purchase history" entry in App Store Connect's similar privacy form, with "Apple" as the third-party processor.
- **If you add a real DM feature** ("Direct messages between users" was in your earlier Play listing copy — currently MNC doesn't actually have peer-to-peer DMs, only an admin inbox): you'll need to flip the "Messages → Other in-app messages" row to Yes.
- **If you add any analytics SDK**: App activity flips to Yes, plus a new third-party recipient.
