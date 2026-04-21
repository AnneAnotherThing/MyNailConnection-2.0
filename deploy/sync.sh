#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# deploy/sync.sh
#
# Mirror MNC source files into deploy/app/ and deploy/marketing/ so the
# drag-ready bundles always match the latest source. Anne drags those
# folders into Netlify to publish — she does NOT publish from here. This
# script just keeps the bundles current.
#
# Run this after any edit to MNC/*.html (or after touching the static
# assets like favicons, manifest.json, sw.js, sitemap.xml). It's safe to
# run repeatedly; cp -f overwrites destinations idempotently.
#
# Layout this script knows about (from CLAUDE.md):
#   /marketing/  ← serves the root domain. marketing.html is RENAMED to
#                  index.html so it serves at the domain root with no
#                  rename step at deploy time.
#   /app/        ← serves the app subdomain/subpath. Hosts the real
#                  index.html plus reset-password.html.
#   privacy.html, terms.html, favicons, manifest.json, sw.js — duplicated
#   into BOTH bundles so each is self-contained for Netlify drag-and-drop.
# ─────────────────────────────────────────────────────────────────────────

set -e
cd "$(dirname "$0")/.."  # cd to MNC repo root

APP=deploy/app
MKT=deploy/marketing

# Copy a file if it exists at the source; soft-skip if it doesn't.
copy_if_exists() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then cp -f "$src" "$dst"; fi
}

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

echo "✓ deploy/ synced from MNC root at $(date '+%Y-%m-%d %H:%M:%S')"
