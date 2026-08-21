#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# deploy/sync.sh
#
# Builds three deploy bundles from the MNC source:
#
#   deploy/app/        ← Netlify-style app bundle (legacy, safety net)
#   deploy/marketing/  ← Netlify-style marketing bundle (legacy, safety net)
#   deploy/ghpages/    ← GitHub Pages bundle, the real publish target.
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

# ── HTML truncation guard ───────────────────────────────────────────────
# After the Edit/Write tool silently truncated marketing.html on 2026-05-05
# during a launch-fanfare edit (and the same thing has bitten index.html
# repeatedly, see CLAUDE.md), we never want a truncated source to reach
# the deploy bundle. This guard aborts sync if any critical HTML source:
#   (a) doesn't end with </body>, or
#   (b) has dropped more than 10% in line count vs its committed git HEAD.
#
# Either symptom usually means the file lost its closing scripts + tags
# during an Edit tool call. Catching it BEFORE the copy means the bundle
# never gets a broken file, so a stale `git push` can't ship a dead site.
#
# Escape hatch: set MNC_SKIP_HTML_GUARD=1 if you're intentionally making
# a huge deletion and want sync to skip the line-count check this once.
validate_html() {
  local f="$1"
  if [ ! -f "$f" ]; then return 0; fi

  # Closing-tag check, </body> must be in the last few hundred bytes
  if ! tail -c 400 "$f" | grep -q "</body>"; then
    echo "✗ ABORT: $f is missing </body> at end of file. Looks truncated." >&2
    echo "  Recover with: git checkout $f  (or merge the missing tail back manually)" >&2
    exit 1
  fi

  # Line-count drop check vs the committed git HEAD version
  if [ "${MNC_SKIP_HTML_GUARD:-0}" != "1" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    local current committed floor
    current=$(wc -l < "$f")
    committed=$(git show "HEAD:$f" 2>/dev/null | wc -l)
    if [ -n "$committed" ] && [ "$committed" -gt 0 ]; then
      floor=$(( committed * 90 / 100 ))
      if [ "$current" -lt "$floor" ]; then
        echo "✗ ABORT: $f shrank from $committed → $current lines (>10% drop vs git HEAD)." >&2
        echo "  This usually means Edit/Write silently truncated the file." >&2
        echo "  Inspect with: git diff $f   |   restore with: git checkout $f" >&2
        echo "  If the deletion is intentional: MNC_SKIP_HTML_GUARD=1 bash deploy/sync.sh" >&2
        exit 1
      fi
    fi
  fi
}

# ── JS syntax guard ────────────────────────────────────────────────────────
# validate_html above only checks for </body> and a >10% line-count drop. A
# JavaScript syntax error sails straight through both, and this project has
# been bitten by that blind spot twice:
#
#   - sw.js shipped TRUNCATED mid-statement for 251 commits (2026-04-22 to
#     2026-08-17). The service worker never evaluated, so web push could not
#     register at all, the PWA was not installable, and every CACHE_NAME bump
#     was a no-op. Nobody noticed because nothing errors loudly.
#   - 2026-08-19: an unterminated string literal in index.html was copied
#     into deploy/ghpages/ by this script and only caught by chance.
#
# So: parse the inline <script> blocks of every HTML source, and node --check
# every standalone .js, BEFORE anything is bumped or copied.
#
# If node is unavailable the check is skipped with a warning rather than
# blocking the sync — a missing toolchain should not stop a deploy, but it
# should be said out loud.
validate_js() {
  local f="$1"
  if [ ! -f "$f" ]; then return 0; fi
  if ! command -v node >/dev/null 2>&1; then return 0; fi

  case "$f" in
    *.js)
      if ! node --check "$f" >/dev/null 2>&1; then
        echo "✗ ABORT: $f is not valid JavaScript." >&2
        node --check "$f" 2>&1 | head -5 >&2
        echo "  This is how sw.js shipped truncated for 251 commits. Fix before syncing." >&2
        exit 1
      fi
      ;;
    *.html)
      # Extract inline scripts (skipping src= includes and JSON-LD) and parse
      # them as one unit, which is how the browser sees them.
      if ! node -e '
        const fs=require("fs"), vm=require("vm");
        const src=fs.readFileSync(process.argv[1],"utf8");
        const re=/<script(?![^>]*\ssrc=)(?![^>]*type="application\/ld\+json")(?![^>]*type="module")[^>]*>([\s\S]*?)<\/script>/g;
        let m,parts=[];
        while((m=re.exec(src))) parts.push(m[1]);
        new vm.Script(parts.join("\n;\n"));
      ' "$f" 2>/dev/null; then
        echo "✗ ABORT: inline JavaScript in $f does not parse." >&2
        node -e '
          const fs=require("fs"), vm=require("vm");
          const src=fs.readFileSync(process.argv[1],"utf8");
          const re=/<script(?![^>]*\ssrc=)(?![^>]*type="application\/ld\+json")(?![^>]*type="module")[^>]*>([\s\S]*?)<\/script>/g;
          let m,parts=[];
          while((m=re.exec(src))) parts.push(m[1]);
          try { new vm.Script(parts.join("\n;\n")); } catch(e) { console.error("  " + e.message); }
        ' "$f" 2>&1 | head -3 >&2
        echo "  Nothing is copied. Fix the source, then re-run." >&2
        exit 1
      fi
      ;;
  esac
}

# Validate every critical HTML source before any cache bump or copy
for f in index.html marketing-v3.html reset-password.html tech-guide-v3.html \
         privacy.html terms.html 404.html founders.html; do
  validate_html "$f"
  validate_js "$f"
done

# Standalone JS. sw.js is the one with history.
for f in sw.js; do
  validate_js "$f"
done

if ! command -v node >/dev/null 2>&1; then
  echo "⚠  node not found — JS syntax guard SKIPPED. Truncation will not be caught." >&2
fi


APP=deploy/app
MKT=deploy/marketing
GH=deploy/ghpages

# Copy a file if it exists at the source; soft-skip if it doesn't.
copy_if_exists() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then cp -f "$src" "$dst"; fi
}

# Mirror a directory's contents into a destination. Prefers rsync (with
# --delete so files removed from source also vanish from the bundle), but
# falls back to cp -rf when rsync is missing. Windows / Git-Bash has no
# rsync, and set -e was aborting the whole sync at the first rsync line,
# so the app bundle never got rebuilt. The cp fallback loses --delete
# semantics (stale files linger), acceptable for the asset folders this
# handles since they rarely drop files. Pass source WITHOUT a trailing
# slash; we add the contents-glob ourselves. 2026-06-13.
sync_dir() {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src/" "$dst/"
  else
    cp -rf "$src/." "$dst/"
  fi
}

# ── Auto-bump service worker cache version ──────────────────────────────
# Problem this solves: on 2026-04-21 Anne pushed a fresh build to GitHub
# Pages and testers (including her) kept seeing the OLD code, the PWA
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
  for f in index.html marketing-v3.html reset-password.html tech-guide-v3.html founders.html admin-feedback.html admin-stats.html manifest.json; do
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

# ── Auto-bump native build numbers (iOS CFBundleVersion + Android versionCode)
# Problem this solves: every Capawesome upload to App Store Connect / Play
# Console requires a strictly higher build number than anything previously
# uploaded. Forgetting to bump = upload fails with
# "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE / The bundle version must be
# higher than the previously uploaded version" (iOS) or "Version code N has
# already been used" (Android). Anne kept hitting this, 2026-04-28.
#
# Fix: same trigger pattern as the sw.js cache bump above. When any source
# HTML (or capacitor.config.json / AndroidManifest.xml) is newer than the
# .last-build-bump marker, we bump iOS CURRENT_PROJECT_VERSION (Debug+Release
# configs in project.pbxproj) and Android versionCode (build.gradle), each
# by +1, and touch the marker. Repeated syncs without HTML edits stay no-op.
#
# .last-build-bump is gitignored, per-machine sentinel, never shared.
# First-ever run (no marker on disk) initializes the marker without bumping
# so wiring this up doesn't fire a stray bump on the next sync.
if [ ! -f .last-build-bump ]; then
  touch .last-build-bump
  echo "  build-bump: marker initialized (no bump on first run)"
else
  needs_build_bump=0
  for f in index.html marketing-v3.html reset-password.html tech-guide-v3.html \
           capacitor.config.json android/app/src/main/AndroidManifest.xml; do
    if [ -f "$f" ] && [ "$f" -nt .last-build-bump ]; then
      needs_build_bump=1
      break
    fi
  done
  if [ "$needs_build_bump" = "1" ]; then
    # iOS, CURRENT_PROJECT_VERSION appears twice in project.pbxproj (Debug
    # + Release configs). Same number in both is the standard Capacitor
    # default and what App Store Connect treats as a single build.
    #
    # First strip any trailing NUL bytes from prior cross-platform writes,
    # build #12 (2026-04-28) failed at pod install because 4 trailing NULs
    # at end-of-file made CocoaPods' Nanaimo plist parser reject the file.
    # tr is binary-safe and self-heals on every run regardless of how the
    # NULs got there.
    PBX=ios/App/App.xcodeproj/project.pbxproj
    if [ -f "$PBX" ]; then
      tr -d '\000' < "$PBX" > "$PBX.clean" && mv "$PBX.clean" "$PBX"
      ios_current=$(grep -am1 "CURRENT_PROJECT_VERSION = " "$PBX" | grep -oE "[0-9]+")
      if [ -n "$ios_current" ]; then
        ios_next=$((ios_current + 1))
        sed "s/CURRENT_PROJECT_VERSION = ${ios_current};/CURRENT_PROJECT_VERSION = ${ios_next};/g" \
          "$PBX" > "$PBX.tmp" && mv "$PBX.tmp" "$PBX"
        # Mirror into index.html APP_BUILD.ios so the in-app build tag
        # rendered on the sign-in screen stays accurate. Sentinel comment
        # __APP_BUILD_IOS__ is unique enough to grep without false hits.
        if [ -f index.html ]; then
          sed -E "s|ios:[[:space:]]+[0-9]+,([[:space:]]*/\* __APP_BUILD_IOS__)|ios:     ${ios_next},\1|" \
            index.html > index.html.tmp && mv index.html.tmp index.html
        fi
        echo "  bumped iOS CFBundleVersion: ${ios_current} → ${ios_next}"
      fi
    fi
    # Android, versionCode is a single integer line in build.gradle.
    # versionName ("2.0.0") is the user-facing version and stays untouched.
    if [ -f android/app/build.gradle ]; then
      android_current=$(grep -E "^[[:space:]]*versionCode[[:space:]]+[0-9]+" android/app/build.gradle \
                        | head -1 | grep -oE "[0-9]+")
      if [ -n "$android_current" ]; then
        android_next=$((android_current + 1))
        sed "s/versionCode ${android_current}$/versionCode ${android_next}/" \
          android/app/build.gradle > android/app/build.gradle.tmp \
          && mv android/app/build.gradle.tmp android/app/build.gradle
        # Mirror into index.html APP_BUILD.android (see iOS comment above).
        if [ -f index.html ]; then
          sed -E "s|android:[[:space:]]+[0-9]+,([[:space:]]*/\* __APP_BUILD_ANDROID__)|android: ${android_next},\1|" \
            index.html > index.html.tmp && mv index.html.tmp index.html
        fi
        echo "  bumped Android versionCode: ${android_current} → ${android_next}"
      fi
    fi
    touch .last-build-bump
  fi
fi

# ── RETIRED: legacy Netlify bundles (deploy/app + deploy/marketing) ─────
# Removed 2026-07-21. GitHub Pages publishes deploy/ghpages/ ONLY; these two
# were the pre-2026-04-23 Netlify drop folders kept as a rollback and were
# ~108MB of duplicate build output. Recoverable from git history if ever
# needed. Their copy lines below are commented out, not deleted, so the
# original bundle layout stays readable.
# ── App bundle ──────────────────────────────────────────────────────────
# [retired 2026-07-21] copy_if_exists index.html              "$APP/index.html"
# [retired 2026-07-21] copy_if_exists reset-password.html     "$APP/reset-password.html"
# [retired 2026-07-21] copy_if_exists privacy.html            "$APP/privacy.html"
# [retired 2026-07-21] copy_if_exists terms.html              "$APP/terms.html"
# [retired 2026-07-21] copy_if_exists mncLogo-transparent.png "$APP/mncLogo-transparent.png"
# [retired 2026-07-21] copy_if_exists favicon.ico             "$APP/favicon.ico"
# [retired 2026-07-21] copy_if_exists favicon-32.png          "$APP/favicon-32.png"
# [retired 2026-07-21] copy_if_exists apple-touch-icon.png    "$APP/apple-touch-icon.png"
# [retired 2026-07-21] copy_if_exists manifest.json           "$APP/manifest.json"
# [retired 2026-07-21] copy_if_exists sw.js                   "$APP/sw.js"

# ── Marketing bundle ────────────────────────────────────────────────────
# NOTE: marketing.html is renamed to index.html in the marketing bundle
# so the domain root serves the marketing page with no extra config.
# [retired 2026-07-21] copy_if_exists marketing.html          "$MKT/index.html"
# [retired 2026-07-21] copy_if_exists 404.html                "$MKT/404.html"
# [retired 2026-07-21] copy_if_exists stats.html              "$MKT/stats.html"
# [retired 2026-07-21] copy_if_exists punch-list.html         "$MKT/punch-list.html"
# [retired 2026-07-21] copy_if_exists tech-guide.html         "$MKT/tech-guide.html"
# [retired 2026-07-21] copy_if_exists founders.html           "$MKT/founders.html"
# [retired 2026-07-21] copy_if_exists admin-feedback.html     "$MKT/admin-feedback.html"
# [retired 2026-07-21] copy_if_exists admin-stats.html        "$MKT/admin-stats.html"
# [retired 2026-07-21] copy_if_exists support.html            "$MKT/support.html"
# [retired 2026-07-21] copy_if_exists privacy.html            "$MKT/privacy.html"
# [retired 2026-07-21] copy_if_exists terms.html              "$MKT/terms.html"
# [retired 2026-07-21] copy_if_exists og-image.png            "$MKT/og-image.png"
# [retired 2026-07-21] copy_if_exists favicon.ico             "$MKT/favicon.ico"
# [retired 2026-07-21] copy_if_exists favicon-32.png          "$MKT/favicon-32.png"
# [retired 2026-07-21] copy_if_exists apple-touch-icon.png    "$MKT/apple-touch-icon.png"
# [retired 2026-07-21] copy_if_exists manifest.json           "$MKT/manifest.json"
# [retired 2026-07-21] copy_if_exists sw.js                   "$MKT/sw.js"
# [retired 2026-07-21] copy_if_exists sitemap.xml             "$MKT/sitemap.xml"
# [retired 2026-07-21] copy_if_exists robots.txt              "$MKT/robots.txt"

# ── Marketing assets (folders) ──────────────────────────────────────────
# Mirror asset folders (rsync when available, cp fallback otherwise).
# [retired 2026-07-21] sync_dir images      "$MKT/images"
# [retired 2026-07-21] sync_dir app-screens "$MKT/app-screens"

# ── Leslie campaign page + downloadable campaign assets ──────────────────
# [retired 2026-07-21] copy_if_exists no-Download-Campaign.html "$MKT/no-Download-Campaign.html"
# [retired 2026-07-21] sync_dir campaign-assets "$MKT/campaign-assets"

# ── GitHub Pages bundle (deploy/ghpages/) ───────────────────────────────
# Single-tree layout served by one repo:
#   /index.html            ← marketing.html renamed to root index
#   /app/index.html        ← the real app
#   /app/reset-password.html
#   /CNAME                 ← pins custom domain to mynailconnection.com
#   (favicons, manifest, sw.js, images/, app-screens/ at root, shared)
#   (privacy.html + terms.html duplicated to /app/ so the app's relative
#    links resolve whether or not the marketing ones are still there)
mkdir -p "$GH" "$GH/app"

# Marketing at root
# 3.0 LAUNCH (2026-08-03): the hat-lady redesign (marketing-v3.html)
# ships as the root index.
# 2026-08-14: the 2.0 marketing.html and its /marketing-2.html rollback
# copy were DELETED, along with the legacy tech-guide.html. Keeping them
# around is what put four dead /marketing.html links on the live tech
# guide and a non-existent URL in sitemap.xml. One version now.
copy_if_exists marketing-v3.html       "$GH/index.html"
copy_if_exists 404.html                "$GH/404.html"
copy_if_exists stats.html              "$GH/stats.html"
copy_if_exists punch-list.html         "$GH/punch-list.html"
copy_if_exists tech-guide-v3.html      "$GH/tech-guide-v3.html"
copy_if_exists founders.html           "$GH/founders.html"
copy_if_exists admin-feedback.html     "$GH/admin-feedback.html"
copy_if_exists admin-stats.html        "$GH/admin-stats.html"
copy_if_exists support.html            "$GH/support.html"
copy_if_exists privacy.html            "$GH/privacy.html"
copy_if_exists terms.html              "$GH/terms.html"
copy_if_exists account-deletion.html   "$GH/account-deletion.html"
copy_if_exists og-image.png            "$GH/og-image.png"
copy_if_exists favicon.ico             "$GH/favicon.ico"
copy_if_exists favicon-32.png          "$GH/favicon-32.png"
copy_if_exists apple-touch-icon.png    "$GH/apple-touch-icon.png"
copy_if_exists manifest.json           "$GH/manifest.json"
copy_if_exists sw.js                   "$GH/sw.js"
copy_if_exists sitemap.xml             "$GH/sitemap.xml"
copy_if_exists robots.txt              "$GH/robots.txt"
sync_dir images      "$GH/images"
sync_dir app-screens "$GH/app-screens"

# The app is served from /app/, and its image refs are RELATIVE
# (images/foo.webp), so they resolve to /app/images/foo.webp. Without this
# mirror the whole home screen's imagery 404s in production even though the
# same files exist at the site root. Mirrored (not moved), the marketing site
# at the root still needs its copy. 2026-07-20.
sync_dir images      "$GH/app/images"

# ── Leslie campaign page + downloadable campaign assets ──────────────────
copy_if_exists leslie.html "$GH/leslie.html"
sync_dir campaign-assets "$GH/campaign-assets"

# ── Google Search Console verification ──────────────────────────────────
# google3d630386db4a7faa.html is an ownership-verification token Google
# generates for the mynailconnection.com property. Must be served at
# https://www.mynailconnection.com/google3d630386db4a7faa.html, i.e. the
# root of the marketing bundle. Per Google's docs ("To stay verified,
# don't remove the file"), this stays in the bundle indefinitely. Added
# 2026-05-25 so Search Console can verify the property and start
# returning indexing data.
copy_if_exists google3d630386db4a7faa.html "$GH/google3d630386db4a7faa.html"

# ── .well-known/, Android App Links + iOS Universal Links ──────────────
# assetlinks.json is served from https://mynailconnection.com/.well-known/
# so Android can auto-verify this domain belongs to our app package. When
# iOS ships, apple-app-site-association will live alongside it (no file
# extension, served as application/json). Without this directory in the
# publish root, tapping a Supabase auth-email link opens a browser tab
# instead of deep-linking into the installed app. 2026-04-23
sync_dir .well-known "$GH/.well-known"

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
# root so Pages serves the site under mynailconnection.com instead of the
# anneanotherthing.github.io subpath. Restored 2026-06-13 after the script
# was found truncated mid-line here (no CNAME copy was running).
copy_if_exists CNAME "$GH/CNAME"