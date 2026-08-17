# Push bring-up, start to finish

Written 2026-08-15. Everything needed to take iPhone/iPad push from nothing to
proven, plus the four other fixes in the same batch. Follow it in order. Each
step says what to do, what you should see, and what it means if you see
something else.

Two browser tabs: the Supabase dashboard (project `nwqnakoongrorbwnrqzc`) and
developer.apple.com. Plus GitHub Desktop and Capawesome later.

---

## Step 1. SQL: photo counts

Supabase → SQL Editor → New query. Paste the whole of
`sql/photo-count-computed-columns.sql`, run it.

Then run the verify block at the bottom of that file. You want the computed
`photos_count` to match the real array length for every tech.

**What this does:** stops the app downloading a tech's entire photo array on
every single upload just to count it.

**If it errors** on `public.techs` not existing, you are on the wrong project.
Check the project selector says `nwqnakoongrorbwnrqzc`.

---

## Step 2. SQL: reminders and observability

Same place. Paste the whole of `sql/booking-reminders-observability.sql`, run it.

**Dependencies.** It needs `public.is_admin()` and `public.phone_digits()`. If
you get *"function public.is_admin() does not exist"*, run `sql/rls-fix.sql`
first, then come back. If you get *"function public.phone_digits() does not
exist"*, run `sql/phone-auth-stage-a-foundation.sql` first.

Then confirm the cron job exists:

```sql
select jobid, jobname, schedule, active from cron.job;
```

You want a row: `booking-reminders`, `*/15 * * * *`, active `true`.

**This is the step most likely to explain everything.** Reminders were
scheduled by a migration that predates the move off the old `ktiz` project.
Whether that job was ever recreated here has been an open question since
2026-08-03 and nobody ever checked. If reminders have never fired, this is
almost certainly why: nothing was calling them. Step 2 schedules it.

---

## Step 3. Diagnostic: what is actually in push_subscriptions

```sql
select user_id,
       auth as platform,
       left(endpoint, 25) as token_start,
       updated_at
  from push_subscriptions
 order by updated_at desc
 limit 20;
```

Send Claude the output. What it tells us:

- **Any row with platform `ios`** means an Apple device has registered at some
  point, so the shipped build does call `register()`.
- **No `ios` row ever** confirms the iOS side has never registered at all,
  which is expected if the installed build predates 2026-08-03.
- The `user_id` format matters: it is the lowercased email, or `+1XXXXXXXXXX`
  for phone accounts. That is the string a push has to be addressed to.

---

## Step 4. Apple: create the APNs key

Sign in to developer.apple.com with the Apple ID that shows **Program
resources** (App Store Connect, Certificates IDs & Profiles, Services). Not
the one that shows "Join the Apple Developer Program".

1. **Certificates, IDs & Profiles** → **Keys** in the left sidebar
2. The **+** button
3. Key Name: `MNC Push`
4. Tick **Apple Push Notifications service (APNs)**
5. Continue → Register
6. **Download** the `.p8`. One time only, Apple will never offer it again.
   Save it somewhere permanent, not just the Downloads folder.
7. Copy the **Key ID** from that page, 10 characters.

**Team ID is `YYS8GZPZ78`.** Already known, taken from the `DEVELOPMENT_TEAM`
the app is signed with. No need to look it up.

**Gotchas:**

- A team is capped at **two** APNs keys. If Keys already lists two, you cannot
  create a third. Existing keys can never be re-downloaded, so revoke one and
  make a new one. Nothing currently depends on them, because iOS push has
  never worked, so revoking is safe.
- Creating keys needs **Account Holder or Admin** role. A Developer-role
  member sees Keys read-only.
- The key must come from team `YYS8GZPZ78`. A key from any other team returns
  `InvalidProviderToken` for this bundle ID forever, no matter what else is
  right.

---

## Step 5. Supabase secrets

Supabase → Edge Functions → Secrets. Add three:

| Secret | Value |
|---|---|
| `APNS_PRIVATE_KEY` | the contents of the `.p8` file |
| `APNS_KEY_ID` | the 10-character Key ID from step 4 |
| `APNS_TEAM_ID` | `YYS8GZPZ78` |

Open the `.p8` in Notepad and copy everything.

**Formatting is tolerant.** The code strips the `-----BEGIN PRIVATE KEY-----`
and `-----END PRIVATE KEY-----` lines and every whitespace character before
decoding, so it does not matter whether those lines survive the paste or
whether the line breaks get flattened. Paste the whole file and do not fuss
over it.

**Do not set `APNS_ENV`.** It defaults to production, which is correct for
TestFlight and App Store builds. The code also retries the other environment
automatically if Apple says the token belongs to the other one, so a debug
build would still work.

**Do not send the `.p8` to Claude.** It is a private key that can send push
notifications as your app. It never needs to leave your machine and the
Supabase secrets box.

---

## Step 6. Deploy the edge functions

Supabase → Edge Functions → click the function → replace the code with the
repo copy → Deploy.

**Deploy these two now:**

1. `send-push` ← `supabase/functions/send-push/index.ts`
2. `broadcast-push` ← `supabase/functions/broadcast-push/index.ts`

`send-push` also carries the high-priority delivery and error reporting from
the earlier batch, so this covers that outstanding paste-deploy too.

**Hold `revenuecat-webhook` until paid plans are actually going live.** The
phone-only fix is in the repo and ready, but redeploying it today buys nothing
(paid plans are off) and carries one real risk worth avoiding for now:

> `revenuecat-webhook` must be deployed with **Verify JWT turned OFF**.
> RevenueCat does not send a JWT, it sends a static `Authorization` header.
> If the dashboard re-enables JWT verification on deploy, every webhook 401s
> and payments silently stop being recorded. Check that toggle before
> deploying it, whenever you do.

---

## Step 7. Commit and push

GitHub Desktop → review the changes → commit → push `main`.

This ships the **website and the PWA**. It does **not** update installed
native apps, but it does put the assets where Capawesome will pick them up.

**Push before triggering any build.** Capawesome builds from the git repo, and
the native app bundles `deploy/ghpages/app/`. Building before pushing bundles
stale assets and the client-notification fix will not be in it.

---

## Step 8. Capawesome builds

Trigger **both**.

**iOS.** No `MARKETING_VERSION` bump needed. 3.0.0 has never been built for
iOS, so the pre-release train is open, which is the documented exception in
CLAUDE.md. The build number is already at 347 from the sync.

**Android.** The client-notification fix matters there identically, and
Android is the one push path known to work, so it is the fastest way to
confirm the client registration change is good independent of anything Apple.

**This is a low-risk iOS build.** Zero native code changed: no Podfile edit,
no new dependency, no AppDelegate change. That was the point of going direct
to APNs instead of adding Firebase. It is web assets plus a build number.

---

## Step 9. TestFlight onto the iPad

The build appears in App Store Connect after processing, usually 5 to 15
minutes.

**Common stall:** the build shows **"Missing Compliance"** and will not
distribute. App Store Connect → TestFlight → click the build → provide the
export compliance answer. Until that is answered the build cannot be
installed, and nothing tells you why on the device.

Then: add yourself as an internal tester, install the TestFlight app on the
iPad, install the build.

**The iPad is fine as a test device.** The app is iPhone-only
(`TARGETED_DEVICE_FAMILY = "1"`) so it runs letterboxed in compatibility mode,
which looks odd but works. Capacitor reports platform `ios` on iPad, so the
subscription saves with `auth: 'ios'` and routes to APNs exactly like a phone.

---

## Step 10. Sign in on the iPad, as a CLIENT

Use the client account, not the tech account. Reason in step 13.

**The iPad cannot receive SMS.** Sign in with a phone number whose texts you
can read on the Android, then type the code into the iPad.

After landing on the home screen, **wait about four seconds**. The permission
prompt is deliberately delayed so the app does not ambush a new user. Tap
**Allow**.

You want the toast: **"Notifications are on 💅"**. That toast is the proof the
device token reached the database. Anything else is a failure worth reading.

**Critical gotcha:** if you tap "Don't Allow" by accident, iOS will never ask
again. The app cannot re-prompt. You have to either delete and reinstall, or
go Settings → Notifications → My Nail Connection → Allow Notifications. The
code notes that on iOS the OS-level toggle does not always clear the denied
state, so reinstalling is the reliable fix.

Also turn **Focus / Do Not Disturb off** on the iPad before testing, or a
perfectly delivered push will look like a failure.

---

## Step 11. Confirm the row landed

```sql
select user_id, auth as platform, left(endpoint, 25) as token_start, updated_at
  from push_subscriptions
 where auth = 'ios'
 order by updated_at desc;
```

A row with platform `ios` and a recent timestamp is what you want. Note the
`user_id` exactly and send it to Claude.

No row means the token never saved, and the toast would have told you why.
That is a client-side problem, not an APNs one, and we debug from there.

---

## Step 12. The probe

Tell Claude the `user_id` from step 11 and it fires `send-push` directly.

Reading the response:

| Response | Meaning |
|---|---|
| `{"sent":1}` | **Apple accepted it.** If the iPad shows nothing, the problem is on the device: Focus mode, or notifications off for the app. |
| `{"sent":0,"reason":"no subscriptions found"}` | The `user_id` we fired at matches no row. Compare against step 11 exactly, including the `+1`. |
| `{"skipped":1,"note":"iOS rows skipped..."}` | Secrets missing or incomplete. Back to step 5. |
| `403 InvalidProviderToken` in `errors` | Key ID, Team ID and `.p8` do not match each other, or the key is from the wrong team. |
| `failed:1` and the row vanished | Apple said the token is permanently dead. It re-registers when the app is next opened. |

---

## Step 13. The booking round trip

This is the test that closes the whole list, and it is why the client account
goes on the iPad rather than the tech account.

- **Android phone = your tech account.** Push already proven working there.
- **iPad = a client account.** The path that has never been proven.

Then:

1. Book an appointment **from the iPad**, as the client
2. The **Android buzzes** as the tech. This part already works, so it confirms
   the round-trip is alive.
3. **Confirm the booking on the Android**
4. **The iPad should buzz.**

Step 4 is the thing that has never once been observed. It exercises client
notifications and iOS APNs in a single action.

**Do not test both accounts on the iPad.** A device token belongs to one
account at a time and signing in as a different user *rebinds* it. That is
deliberate, but it means testing tech then client on the same iPad leaves only
the client working.

---

## Step 14. Prove the reminders

With a confirmed booking roughly two hours out:

```sql
select public.process_booking_reminders();
select * from public.push_log_recent limit 10;
```

`status_code` 200 with `{"sent":1}` is a delivered reminder.

`{"sent":0,"reason":"no subscriptions found"}` means the `recipient` string in
the log matched no subscription. Compare `recipient` against
`push_subscriptions.user_id` directly. That mismatch is exactly the bug fixed
in step 2 for the tech side.

To re-run against the same booking, clear the stamps:

```sql
update bookings set reminded_day_at = null, reminded_soon_at = null
 where id = '<booking-uuid>';
```

After this, `push_log` keeps a durable record of every push the database
sends, for 60 days. "Did the reminder fire" now has an answer the next
morning, which it never did before.

---

## Step 15. Broadcast

Admin → send a broadcast. Native devices should receive it now, not just web.
This path is code-complete but has never been observed working.

---

## Standing gotcha, worth remembering forever

Reinstalling the app invalidates the device token, and the server prunes it on
the next failed send. It re-registers automatically, but **only when the app
is opened and signed in**. So after every store update, a device has to open
the app once before pushes resume. An empty subscription row right after an
update is expected, not a bug.
