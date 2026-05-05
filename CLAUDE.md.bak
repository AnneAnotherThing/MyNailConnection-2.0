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

## Deploy target (as of 2026-04-23)

- Both sites ship from a **single GitHub Pages deploy** on this repo
  (`MyNailConnection-2.0`). Marketing serves at `https://mynailconnection.com/`,
  app at `https://mynailconnection.com/app/`, reset-password at
  `https://mynailconnection.com/app/reset-password.html`.
- Deploy is driven by `.github/workflows/deploy.yml`, which publishes
  the contents of `deploy/ghpages/` to Pages on every push to `main`.
- **Pages source MUST be set to "GitHub Actions"** (not "Deploy from a
  branch") in the repo Settings → Pages. If someone sets it back to
  "branch / main", Pages will serve the raw repo root — which is the
  app's `index.html` plus everything else — and marketing breaks.
- Migration rationale: Anne moved off Netlify on 2026-04-23 to stop
  burning build credits. The two Netlify bundles under `deploy/app/`
  and `deploy/marketing/` are retained as a rollback option and will
  be deleted once the GH Pages setup has baked in for a couple of weeks.

## When producing a deploy bundle

The Action publishes whatever is in `deploy/ghpages/`, so that folder
IS the published site. Its structure (built by `deploy/sync.sh`):

- Marketing lives at the root of the bundle (`marketing.html` → renamed
  to `index.html` at bundle time).
- App lives under `deploy/ghpages/app/`, along with `reset-password.html`.
- Shared files (`favicon.ico`, `favicon-32.png`, `apple-touch-icon.png`,
  `privacy.html`, `terms.html`, `manifest.json`, `sw.js`) are duplicated
  into both root and `/app/` so relative links resolve in both contexts.
- `CNAME` at the bundle root pins the custom domain to
  `mynailconnection.com` (required by GH Pages to serve the site under
  the custom domain instead of `anneanotherthing.github.io/...`).

## Keep `deploy/` synced with source — run `deploy/sync.sh`

**RULE:** after any edit to `index.html`, `marketing.html`, `tech-guide.html`,
or any of the shared source files (`privacy.html`, `terms.html`, favicons,
`manifest.json`, `sw.js`, `sitemap.xml`, `robots.txt`, `images/`, `app-screens/`),
run `deploy/sync.sh` so `deploy/ghpages/` always matches the latest source.
Without this, a commit + push won't actually ship any changes because the
Action publishes `deploy/ghpages/` — whatever state that folder is in.

The script copies `marketing.html` → `deploy/ghpages/index.html` with the
rename baked in, copies the real `index.html` (app) to `deploy/ghpages/app/`,
duplicates shared files into both root and `/app/`, rsyncs `images/` and
`app-screens/` into the bundle root, and writes the `CNAME` file. It's
idempotent — safe to run repeatedly.

Anne does **not** need to run the script herself. As long as Claude edits
source files via tools, Claude should run `deploy/sync.sh` at the end of
each edit batch (or after any single meaningful edit) so the bundle stays
current. Then Anne pushes `main` via GitHub Desktop and the Action ships it.

If Anne edits a source file directly (in her own editor), `deploy/ghpages/`
will drift until someone runs the script — and the next deploy will ship
stale content. For now, Claude treats sync as a post-edit habit.

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
- [ ] **Before App Store production submission only:** grep `index.html`
      for `IAP_DIAGNOSTIC_FAILURE_MODE = true` and `IAP_DIAGNOSTIC_SUCCESS_MODE = true`
      and flip both to `false`, then re-run `deploy/sync.sh`. These flags
      swap the generic "Purchase failed" toast / silent success path for
      verbose native `alert()`s naming the IAP failure branch or showing
      the customerInfo breakdown. Useful for TestFlight debugging, NOT
      for end-users. Originally a single `IAP_DIAGNOSTIC_MODE` flag added
      2026-04-30; split 2026-05-01 because the success-path diagnostic
      gave false positives that wasted hours of triage time, while the
      failure-path one is genuinely useful and safe to leave on during
      active App Review iteration.

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
