#!/usr/bin/env bash
# Screenshots every slide source in src/ to a PNG in png/ with headless Chrome.
# Feed slides render at 1080x1350, story slides at 1080x1920.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
mkdir -p png
for f in src/*.html; do
  name=$(basename "$f" .html)
  case "$name" in story-*) h=1920 ;; *) h=1350 ;; esac
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --virtual-time-budget=6000 --window-size=1080,$h --force-device-scale-factor=1 \
    --screenshot="$(cygpath -w "$PWD/png/$name.png")" "file:///$(cygpath -m "$PWD/$f")" >/dev/null 2>&1
  echo "rendered png/$name.png"
done
