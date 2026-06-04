# MNC granular analytics — setup & how it works

_Added 2026-06-04. Retires the in-app Stats tab; the web dashboard
(`admin-stats.html`) is now the single source of truth._

## ⚠️ One manual step before anything shows up

Run **`sql/granular-analytics-migration.sql`** once in Supabase → SQL Editor.
It adds `marketing_hits.entry_channel`, and creates `store_clicks` and
`app_downloads`. Until you run it, the three new dashboard panels will sit
empty (the rest of the dashboard keeps working).

## What changed

- **In-app Stats tab** (`index.html`, admin → 📊 Stats) is now a *mini
  summary*: the 4 headline cards (Clients / This week / Techs / Photos) +
  Live-now, plus a big **“Open the complete stats dashboard ↗”** button to
  `https://mynailconnection.com/admin-stats.html`. The deep panels were
  removed from the app so there’s only one place to maintain.

- **Web dashboard** (`admin-stats.html`) gained three panels:
  1. **How visitors arrive** — channel breakdown (QR / Social / Search /
     Referral / Campaign / Direct) over the last 30 days, plus a 📱 phone vs
     💻 desktop split.
  2. **Store taps · download intent** — Apple vs Android badge taps
     (today / 7d / all-time). A proxy for interest, **not** installs.
  3. **App downloads · true installs** — the real numbers, entered by hand.

## How each question gets answered

### “QR, phone, or web?”
- **Phone vs web** = `device_type` (mobile/desktop), captured automatically.
- **QR** = arrivals from a **tagged link**. QR codes point at
  `mynailconnection.com/?src=qr-…`; the tracker tags those as channel `qr`.
  Print-ready codes are in the **`qr/`** folder:
  - `qr-flyer.png`, `qr-card.png`, `qr-salon.png`, `qr-event.png`,
    `qr-social-bio.png` → the landing page, tagged per use.
  - `qr-techguide.png` → the Tech Guide (for recruiting techs).
  - `qr-plain.png` → untagged, general use.
  Make more anytime by linking to `?src=qr-<whatever>` — any `src` starting
  with `qr` classifies as QR.

### “How many downloads on Apple vs Android?”
True install counts **only** live in App Store Connect and Play Console —
they can’t be read from the web or Supabase. So:
- **Now:** the dashboard shows **store-tap intent** automatically, and an
  **“App downloads”** panel where you paste the real totals (~2 min):
  - Apple: App Store Connect → Analytics → Total Downloads.
  - Android: Play Console → Statistics → Acquisition (Users acquired).
  Hit **“+ Record a new number”**, pick platform, type the total + a period
  label (e.g. “All-time” or “Week of Jun 1”), Save. Latest per platform shows
  on the cards; history is listed underneath.
- **Later (optional phase 2):** wire the **App Store Connect API** + **Play
  Developer Reporting API** for fully automated true counts. Needs API keys
  from both consoles and a small Supabase edge function. Scoped, not built.

## Privacy / access
- `store_clicks`: anon can INSERT (marketing pages are public); only admins
  (`is_admin()`) can SELECT. No IPs, no precise geo — same model as
  `marketing_hits`.
- `app_downloads`: admin read/write only.

## Files touched
- `sql/granular-analytics-migration.sql` (new — **run it**)
- `marketing.html` — channel tagging + store-badge click tracker
- `tech-guide.html` — channel tagging
- `admin-stats.html` — three new panels + loaders + manual-entry form
- `index.html` — Stats tab slimmed to mini-summary + launcher
- `qr/` (new) — printable tagged QR codes

Deploy bundle re-synced via `deploy/sync.sh`; push `main` to ship.
