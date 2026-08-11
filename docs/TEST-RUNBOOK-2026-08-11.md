# MNC 3.0 Test Runbook — 2026-08-11 build (Android 521 / iOS 326, cache v540)

Follow top to bottom. Report failures by step number.

## 0 · Fresh install
1. Install, open, sign in as tech.
2. Build stamp must read **521** (Android) / **326** (iOS). If not, stop — old build.

## 1 · Tech Portal
3. Zones in order: Your Bookings → Your Gallery → Your Profile → Help & Account; dark "Bookings & Appointments" calendar card on top.
4. Gallery card shows your six latest looks + count; grid/header/"Manage & Tag" all open My Gallery. Zero photos → pitch copy instead.
5. "Up next" alert under greeting appears only when a future confirmed appt exists.

## 2 · Nav + sign-out
6. Sign Out item on the right of EVERY bottom nav (portal, gallery, My Appts, settings, client Home). Icons/labels darker than the old build. Tap it once from a deep screen; sign back in.

## 3 · Contact preferences
7. Edit Profile → uncheck both Call Me and Text Me → Save → toast "Call and Text hidden…". Reopen modal: still unchecked. "See What Clients See": no Call/Text buttons. Re-enable after.

## 4 · Take a booking
8. My Appts → + Add appointment → name/service/today/time+2h/private note → Add to calendar → "On your calendar ✨", shows under Upcoming with the note.
9. Second appt at the same time → overlap warning ("Book it anyway?") → decline.
10. Tech Portal now shows the "Today" alert card + calendar dot.

## 5 · Notes, Block
11. + Add a private note on any card; edit; clear (empty save removes). Toast each time.
12. Block button on pending, upcoming, AND past cards (hidden only when the card has no phone/email — e.g. a walk-in without a phone).

## 6 · Uploads
13. Batch of 5+: immediate "Preparing…" text, filenames during upload, moving counter, faster finish. "✓ Done! N photos added."

## 7 · Client side
14. Sign in as client: Sign Out on every nav; browse to the tech; book a slot.
15. As tech: pulsing rose "booking request waiting" alert on portal + push. Confirm → client notified, alert becomes "Up next."

## 8 · Cleanup
16. Delete test bookings; restore Call/Text prefs.

## If something fails
- Old build symptoms: re-check step 2 first (close app fully, reopen twice).
- Notes / take-a-booking errors mentioning migrations: both migrations were run 2026-08-11; if the toast appears anyway, capture the exact message.
