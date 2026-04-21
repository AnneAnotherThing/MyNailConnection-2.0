# MNC — Notes for Claude (and future-Anne)

This folder contains **two separate web properties** that share a domain
and some assets but are not the same thing. Do not mix them up.

## The two sites

### 1. Marketing site — `marketing.html`
- Public-facing landing page for **https://mynailconnection.com/**.
- Static, SEO-oriented, for visitors who've never heard of MNC.
- Links out to `tech-guide.html`, `privacy.html`, `terms.html`.
- Uses assets in `images/` (various `mncLogo-*.webp` sizes) and
  `app-screens/` (phone screenshots).
- Has its own `manifest.json` and sitemap/robots for SEO.

### 2. The app — `index.html`
- The signed-in product: splash → sign in → client browse / tech
  dashboard / admin. One huge single-page app (~9,200 lines).
- Talks to Supabase (project `ktiztunuifzbzwzyqrrq`) for auth, data, push.
- Companion static page: `reset-password.html` (Supabase password-reset
  landing; references `/mncLogo-transparent.png`, `/privacy.html`,
  `/terms.html` by root-relative paths).

## Deploy target (current assumption — verify with Anne before assuming)

- **Marketing** deploys to `https://mynailconnection.com/`
  (rename `marketing.html` → `index.html` on upload).
- **App** deploys somewhere else — either `app.mynailconnection.com/`
  or `mynailconnection.com/app/`. Keep `index.html` as the root file
  of whichever location you pick, with `reset-password.html` and its
  assets alongside it.

## When producing a deploy bundle

**Always** split into `/marketing/` and `/app/` subfolders. Duplicate the
shared files (`favicon.ico`, `favicon-32.png`, `apple-touch-icon.png`,
`privacy.html`, `terms.html`) into **both** folders so each is a
self-contained deploy. The prior incident where I (Claude) bundled the
app's `index.html` in a single zip labeled generically caused Anne to
think the marketing page was being overwritten. Don't repeat that.

## Keep `deploy/` synced with source — run `deploy/sync.sh`

**RULE:** after any edit to `index.html`, `marketing.html`, `tech-guide.html`,
or any of the shared source files (`privacy.html`, `terms.html`, favicons,
`manifest.json`, `sw.js`, `sitemap.xml`, `robots.txt`, `images/`, `app-screens/`),
run `deploy/sync.sh` so the drag-ready bundles always match the latest
source. Anne asked for this on 2026-04-20 after the deploy folders had
drifted 2+ days behind the active source.

The script copies `marketing.html` → `deploy/marketing/index.html` with the
rename baked in, duplicates shared files into both bundles, and rsyncs
the `images/` and `app-screens/` folders into `deploy/marketing/`. It's
idempotent — safe to run repeatedly.

Anne does **not** need to run the script herself. As long as Claude edits
source files via tools, Claude should run `deploy/sync.sh` at the end of
each edit batch (or after any single meaningful edit) so the bundles stay
current. Anne then drags the `deploy/marketing/` and `deploy/app/` folders
into Netlify when she's ready to ship.

If Anne edits a source file directly (in her own editor), `deploy/` will
drift until someone runs the script — that's a known limitation of the
copy-based approach. For now, Claude treats sync as a post-edit habit.

### sync.sh auto-bumps the service worker cache

When any HTML source (`index.html`, `marketing.html`, `reset-password.html`,
`tech-guide.html`) or `manifest.json` is newer than `sw.js`, the sync
script increments `CACHE_NAME` in `sw.js` (`mnc-vN` → `mnc-v(N+1)`) and
then copies the updated `sw.js` into both deploy bundles.

This exists because on 2026-04-21 Anne pushed a build to GitHub Pages
and returning visitors kept seeing old code — the PWA service worker
had `index.html` cached under the old name and never re-fetched. Manual
"unregister + clear site data" from DevTools is the only client-side
workaround, which we can't reasonably ask end-users to do. Bumping
`CACHE_NAME` triggers the SW's `activate` handler to delete old caches.

The bump only fires when a source HTML actually changed, so repeated
idempotent syncs (no edits) don't churn the version number.

## When editing

- "Forgot password?" link, splash, sign-in, tech dashboard, Contact
  Anne modal, profile screens → **`index.html` (app)**.
- "For Clients / For Techs" marketing sections, hero screenshots, SEO
  schema → **`marketing.html`**.
- Legal pages (`privacy.html`, `terms.html`) are shared — edit once,
  re-ship to both bundles.

## What goes in each deploy folder

Most files need to ship to BOTH deploys — the folders are not mutually
exclusive, they just represent the two URLs each deploy target serves.

**`/marketing/`** (serves the root domain, `mynailconnection.com/`)
- `index.html` ← renamed from `marketing.html` at bundle time
- `404.html`, `stats.html`, `punch-list.html`, `tech-guide.html`
- `privacy.html`, `terms.html`
- `og-image.png` ← social share card for marketing
- `favicon.ico`, `favicon-32.png`, `apple-touch-icon.png`
- `manifest.json`, `sw.js` ← PWA (manifest) + service worker at root
- `sitemap.xml`, `robots.txt`
- `images/` (logo sizes), `app-screens/` (phone screenshots)

**`/app/`** (serves wherever the app is deployed — subdomain or subpath)
- `index.html` ← the app (DO NOT overwrite marketing's index.html)
- `reset-password.html` ← lives ONLY here. Supabase Site URL should
  point at `<app-deploy-url>/reset-password.html`. Do not duplicate
  to marketing — reset is part of the app auth flow, not the public site.
- `privacy.html`, `terms.html`
- `mncLogo-transparent.png` ← used by reset-password.html
- `favicon.ico`, `favicon-32.png`, `apple-touch-icon.png`
- `manifest.json`, `sw.js`

**Files with no deploy home** (source-only, safe at MNC root but don't ship)
- `mncLogo.jpeg` ← not referenced anywhere; historical, skip

## Shared Supabase config
- Project URL: `https://ktiztunuifzbzwzyqrrq.supabase.co`
- Anon key is inlined in both `index.html` and `reset-password.html`.
- Edge functions live under `supabase/functions/` (send-push,
  admin-reset-passwords, stripe-webhook).
- `ANNE_USER_ID` placeholder sits at the top of the script block in
  both `index.html` (for the Contact Anne modal push) and historically
  in `reset-password.html` (removed when the help flow was removed).
  Paste Anne's auth.users UUID before deploying anything that pushes.

## Quick sanity checklist before shipping a bundle
- [ ] Two folders: `/marketing/`, `/app/`.
- [ ] README or notes at top of bundle pointing out which is which.
- [ ] `ANNE_USER_ID` pasted (if the change involves push).
- [ ] Supabase URL Configuration reviewed (Site URL + Redirect URLs)
      before any `auth/v1/recover` test.
- [ ] Dry-run password reset on Anne's own account before batch sends.

## Folder layout (as of 2026-04-18 — after organizing)

```
MNC/
├── (web-served files at root)
│   index.html          marketing.html     reset-password.html
│   privacy.html        terms.html         tech-guide.html
│   404.html            stats.html         punch-list.html
│   favicon.ico         favicon-32.png     apple-touch-icon.png
│   mncLogo-transparent.png  mncLogo.jpeg  og-image.png
│   manifest.json       sitemap.xml        robots.txt         sw.js
│   package.json        package-lock.json  capacitor.config.json
│   CLAUDE.md
│
├── sql/           ← Supabase migrations + RLS scripts (hand-run in SQL editor)
├── docs/          ← internal docs — ANDROID-BUILD-RUNBOOK.html, SEO-AUDIT.md
├── archive/       ← old deploy zips + temp junk; safe to ignore or delete
├── deploy/        ← drag-ready output: /marketing/ and /app/ folders plus
│                    a README. Rebuild these when shipping changes rather
│                    than making zips — Anne drags folders to Netlify.
│
├── images/        ← marketing logos in various sizes (.webp)
├── app-screens/   ← phone screenshots used by marketing.html
├── screenshots/   ← misc screenshots
├── supabase/      ← edge functions (send-push, admin-reset-passwords,
│                    stripe-webhook) and Supabase project config
├── android/       ← Capacitor Android build project
├── www/           ← Capacitor's sync-target copy of the web assets
└── node_modules/  ← npm deps
```

When adding new files, prefer the existing folders over dropping things at
the root. New SQL snippets → `sql/`; new internal docs/runbooks → `docs/`;
old/superseded builds → `archive/`.
