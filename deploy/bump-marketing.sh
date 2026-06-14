#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# deploy/bump-marketing.sh
#
# Bumps MARKETING_VERSION across iOS pbxproj + Android build.gradle +
# index.html APP_BUILD.name in lockstep, then runs deploy/sync.sh which
# propagates to the deploy/ bundles and auto-bumps build numbers.
#
# WHEN TO RUN THIS:
# After Apple approves any build at MARKETING_VERSION X.Y.Z, that pre-release
# train is CLOSED. The next Capawesome iOS deploy at the same X.Y.Z fails
# with the altool error:
#
#     Invalid Pre-Release Train. The train version 'X.Y.Z' is closed
#     This bundle is invalid. CFBundleShortVersionString must contain a
#     higher version than the previously approved version
#
# Hit this 3+ times during the OG launch (2.0.1 → 2.0.2 → 2.0.3 → 2.0.4),
# every time eating ~5 minutes to manually edit four spots. This script
# does the four edits + sync in one command.
#
# Usage:
#   bash deploy/bump-marketing.sh           # patch  (2.0.3 → 2.0.4)
#   bash deploy/bump-marketing.sh patch     # patch  (same as default)
#   bash deploy/bump-marketing.sh minor     # minor  (2.0.x → 2.1.0)
#   bash deploy/bump-marketing.sh major     # major  (2.x.y → 3.0.0)
#
# After a successful run, push main and retrigger the Capawesome iOS build.
# In App Store Connect, create the new version row (the prior X.Y.Z listing
# is locked once approved) and attach the new build once it processes.
# ─────────────────────────────────────────────────────────────────────────

set -e
cd "$(dirname "$0")/.."  # cd to MNC repo root

mode="${1:-patch}"
case "$mode" in
  patch|--patch) mode=patch ;;
  minor|--minor) mode=minor ;;
  major|--major) mode=major ;;
  *) echo "Usage: $0 [patch|minor|major]   (default: patch)"; exit 1 ;;
esac

# Read current MARKETING_VERSION from the iOS project, single source of truth.
current=$(grep -m1 -oE "MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+" \
            ios/App/App.xcodeproj/project.pbxproj 2>/dev/null \
            | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
if [ -z "$current" ]; then
  echo "✗ ABORT: could not read current MARKETING_VERSION from project.pbxproj" >&2
  exit 2
fi

IFS='.' read -r maj min pat <<< "$current"
case "$mode" in
  patch) pat=$((pat + 1)) ;;
  minor) min=$((min + 1)); pat=0 ;;
  major) maj=$((maj + 1)); min=0; pat=0 ;;
esac
next="${maj}.${min}.${pat}"

# Sanity: refuse to clobber if any of the three sources don't currently
# show $current, means they're already out of sync and the bump might
# silently no-op somewhere.
ios_count=$(grep -c "MARKETING_VERSION = ${current};" ios/App/App.xcodeproj/project.pbxproj || true)
android_match=$(grep -c "versionName \"${current}\"" android/app/build.gradle || true)
indexhtml_match=$(grep -c "name:    '${current}'" index.html || true)
if [ "$ios_count" -lt 1 ] || [ "$android_match" -lt 1 ] || [ "$indexhtml_match" -lt 1 ]; then
  echo "✗ ABORT: marketing version sources are out of sync."           >&2
  echo "  Expected '${current}' in:"                                    >&2
  echo "    ios/App/App.xcodeproj/project.pbxproj   (found ${ios_count} matches; expected ≥1)"   >&2
  echo "    android/app/build.gradle               (found ${android_match} matches; expected 1)" >&2
  echo "    index.html APP_BUILD.name              (found ${indexhtml_match} matches; expected 1)" >&2
  echo "  Inspect manually and fix drift before bumping."               >&2
  exit 3
fi

echo "Bumping MARKETING_VERSION: ${current} → ${next}"

# 1. iOS pbxproj, Debug + Release configs (appears twice)
sed "s/MARKETING_VERSION = ${current};/MARKETING_VERSION = ${next};/g" \
  ios/App/App.xcodeproj/project.pbxproj > ios/App/App.xcodeproj/project.pbxproj.tmp \
  && mv ios/App/App.xcodeproj/project.pbxproj.tmp ios/App/App.xcodeproj/project.pbxproj
echo "  ✓ iOS pbxproj"

# 2. Android build.gradle versionName, parity with iOS
sed "s/versionName \"${current}\"/versionName \"${next}\"/" \
  android/app/build.gradle > android/app/build.gradle.tmp \
  && mv android/app/build.gradle.tmp android/app/build.gradle
echo "  ✓ Android build.gradle"

# 3. index.html APP_BUILD.name, drives the in-app build tag on sign-in
esc_current=$(printf '%s' "$current" | sed 's/\./\\./g')
sed -E "s|name:    '${esc_current}',([[:space:]]*/\* __APP_BUILD_NAME__)|name:    '${next}',\1|" \
  index.html > index.html.tmp \
  && mv index.html.tmp index.html
echo "  ✓ index.html APP_BUILD.name"

# 4. sync.sh propagates to deploy/ bundles + auto-bumps CFBundleVersion +
#    versionCode + sw.js cache. Idempotent; safe to run after this script.
echo ""
echo "Running deploy/sync.sh..."
bash deploy/sync.sh

echo ""
echo "✓ Marketing version bumped: ${current} → ${next}"
echo "  Next: push main from GitHub Desktop, retrigger Capawesome builds."
echo "  In App Store Connect, create the ${next} version row and attach"
echo "  the new build once it processes."
