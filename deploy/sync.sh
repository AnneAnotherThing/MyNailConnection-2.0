#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# deploy/sync.sh
#
# Builds three deploy bundles from the MNC source:
#
#   deploy/app/        ← Netlify-style app bundle (legacy, safety net)
#   deploy/marketing/  ← Netlify-style marketing bundle (legacy, safety net)
#   deploy/ghpages/    ← GitHub Pages bundle — the real publish target.
#                         Marketing at root, app under /app/, CNAME pinned
#                         to mynailconnection.com. Push the contents of
#                         this folder to the anneanotherthing.github.io
#                         user-site repo to deploy.
#
# Migration note (2026-04-23): Anne is moving off Netlify to GitHub Pages
# because Netlify build credits were getting eaten. The two Netlify
# bundles stay around for now as a rollback option but the ghpages bundle
# is what ships. When the GH Pages setup has baked in for a week or two,
# the Netlify sections below can be deleted.
#
# Run this after any edit to MNC/*.html (or after touching the static
# assets like favicons, manifest.json, sw.js, sitemap.xml). It's safe to
# run repeatedly; cp -f overwrites destinations idempotently.
# ─────────────────────────────────────────────────────────────────────────

set -e
cd "$(dirname "$0")/.."  # cd to MNC repo root

APP=deploy/app
MKT=deploy/marketing
GH=deploy/ghpages

# Copy a file if it exists at the source; soft-skip if it doesn't.
copy_if_exists() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then cp -f "$src" "$dst"; fi
}

# ── Auto-bump service worker cache version ──────────────────────────────
# Problem this solves: on 2026-04-21 Anne pushed a fresh build to GitHub
# Pages and testers (including her) kept seeing the OLD code — the PWA
# service worker had index.html cached under mnc-vN and never re-fetched.
# Manual fix was "DevTools → Application → Unregister + Clear storage",
# which isn't something we can ask end-users to do.
#
# Fix: every time an HTML source file (index.html, marketing.html, etc.)
# is newer than sw.js, we bump the CACHE_NAME ('mnc-vN' → 'mnc-v(N+1)').
# The service worker's activate handler already deletes any cache whose
# name ≠ CACHE_NAME, so bumping is all that's required to force-refresh.
#
# We only bump when a source HTML is newer so repeated idempotent sync
# runs (no actual edit) don't churn version numbers. After bumping we
# `touch sw.js` so it's newer than the sources and subsequent syncs
# stay no-op until the user edits HTML again.
if [ -f sw.js ]; then
  needs_bump=0
  for f in index.html marketing.html reset-password.html tech-guide.html manifest.json; do
    if [ -f "$f" ] && [ "$f" -nt sw.js ]; then needs_bump=1; break; fi
  done
  if [ "$needs_bump" = "1" ]; then
    current=$(grep -oE "'mnc-v[0-9]+'" sw.js | head -1 | tr -d "'" | sed 's/mnc-v//')
    if [ -n "$current" ]; then
      next=$((current + 1))
      # Portable in-place edit: write to temp then mv. Avoids the macOS
      # vs GNU sed -i argument mismatch.
      sed "s/'mnc-v${current}'/'mnc-v${next}'/" sw.js > sw.js.tmp && mv sw.js.tmp sw.js
      touch sw.js
      echo "  bumped sw.js cache: mnc-v${current} → mnc-v${next}"
    fi
  fi
fi

# ── App bundle ──────────────────────────────────────────────────────────
copy_if_exists index.html              "$APP/index.html"
copy_if_exists reset-password.html     "$APP/reset-password.html"
copy_if_exists privacy.html            "$APP/privacy.html"
copy_if_exists terms.html              "$APP/terms.html"
copy_if_exists mncLogo-transparent.png "$APP/mncLogo-transparent.png"
copy_if_exists favicon.ico             "$APP/favicon.ico"
copy_if_exists favicon-32.png          "$APP/favicon-32.png"
copy_if_exists apple-touch-icon.png    "$APP/apple-touch-icon.png"
copy_if_exists manifest.json           "$APP/manifest.json"
copy_if_exists sw.js                   "$APP/sw.js"

# ── Marketing bundle ────────────────────────────────────────────────────
# NOTE: marketing.html is renamed to index.html in the marketing bundle
# so the domain root serves the marketing page with no extra config.
copy_if_exists marketing.html          "$MKT/index.html"
copy_if_exists 404.html                "$MKT/404.html"
copy_if_exists stats.html              "$MKT/stats.html"
copy_if_exists punch-list.html         "$MKT/punch-list.html"
copy_if_exists tech-guide.html         "$MKT/tech-guide.html"
copy_if_exists support.html            "$MKT/support.html"
copy_if_exists privacy.html            "$MKT/privacy.html"
copy_if_exists terms.html              "$MKT/terms.html"
copy_if_exists og-image.png            "$MKT/og-image.png"
copy_if_exists favicon.ico             "$MKT/favicon.ico"
copy_if_exists favicon-32.png          "$MKT/favicon-32.png"
copy_if_exists apple-touch-icon.png    "$MKT/apple-touch-icon.png"
copy_if_exists manifest.json           "$MKT/manifest.json"
copy_if_exists sw.js                   "$MKT/sw.js"
copy_if_exists sitemap.xml             "$MKT/sitemap.xml"
copy_if_exists robots.txt              "$MKT/robots.txt"

# ── Marketing assets (folders) ──────────────────────────────────────────
# Use rsync --delete so removed source files are removed from the bundle.
[ -d images ]      && rsync -a --delete images/      "$MKT/images/"
[ -d app-screens ] && rsync -a --delete app-screens/ "$MKT/app-screens/"

# ── GitHub Pages bundle (deploy/ghpages/) ───────────────────────────────
# Single-tree layout served by one repo:
#   /index.html            ← marketing.html renamed to root index
#   /app/index.html        ← the real app
#   /app/reset-password.html
#   /CNAME                 ← pins custom domain to mynailconnection.com
#   (favicons, manifest, sw.js, images/, app-screens/ at root — shared)
#   (privacy.html + terms.html duplicated to /app/ so the app's relative
#    links resolve whether or not the marketing ones are still there)
mkdir -p "$GH" "$GH/app"

# Marketing at root
copy_if_exists marketing.html          "$GH/index.html"
copy_if_exists 404.html                "$GH/404.html"
copy_if_exists stats.html              "$GH/stats.html"
copy_if_exists punch-list.html         "$GH/punch-list.html"
copy_if_exists tech-guide.html         "$GH/tech-guide.html"
copy_if_exists support.html            "$GH/support.html"
copy_if_exists privacy.html            "$GH/privacy.html"
copy_if_exists terms.html              "$GH/terms.html"
copy_if_exists og-image.png            "$GH/og-image.png"
copy_if_exists favicon.ico             "$GH/favicon.ico"
copy_if_exists favicon-32.png          "$GH/favicon-32.png"
copy_if_exists apple-touch-icon.png    "$GH/apple-touch-icon.png"
copy_if_exists manifest.json           "$GH/manifest.json"
copy_if_exists sw.js                   "$GH/sw.js"
copy_if_exists sitemap.xml             "$GH/sitemap.xml"
copy_if_exists robots.txt              "$GH/robots.txt"
[ -d images ]      && rsync -a --delete images/      "$GH/images/"
[ -d app-screens ] && rsync -a --delete app-screens/ "$GH/app-screens/"

# ── .well-known/ — Android App Links + iOS Universal Links ──────────────
# assetlinks.json is served from https://mynailconnection.com/.well-known/
# so Android can auto-verify this domain belongs to our app package. When
# iOS ships, apple-app-site-association will live alongside it (no file
# extension, served as application/json). Without this directory in the
# publish root, tapping a Supabase auth-email link opens a browser tab
# instead of deep-linking into the installed app. — 2026-04-23
[ -d .well-known ] && rsync -a --delete .well-known/ "$GH/.well-known/"

# App under /app/
copy_if_exists index.html              "$GH/app/index.html"
copy_if_exists reset-password.html     "$GH/app/reset-password.html"
copy_if_exists privacy.html            "$GH/app/privacy.html"
copy_if_exists terms.html              "$GH/app/terms.html"
copy_if_exists mncLogo-transparent.png "$GH/app/mncLogo-transparent.png"
copy_if_exists favicon.ico             "$GH/app/favicon.ico"
copy_if_exists favicon-32.png          "$GH/app/favicon-32.png"
copy_if_exists apple-touch-icon.png    "$GH/app/apple-touch-icon.png"
copy_if_exists manifest.json           "$GH/app/manifest.json"
copy_if_exists sw.js                   "$GH/app/sw.js"

# Custom domain pin for GitHub Pages. This file must sit at the publish
# root and contain exactly the apex domain — that's how GH Pages knows to
# serve mynailconnection.com instead of anneanotherthing.github.io.
echo "mynailconnection.com" > "$GH/CNAME"

echo "✓ deploy/ synced from MNC root at $(date '+%Y-%m-%d %H:%M:%S')"
