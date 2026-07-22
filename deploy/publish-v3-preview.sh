#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Publish the 3.0 PREVIEW onto the live domain, alongside production:
#     https://mynailconnection.com/v3       ← v3 marketing page
#     https://mynailconnection.com/v3/app/  ← the 3.0 app (installable PWA)
#
# Production (/ and /app/) is NOT touched.
#
# WHY THIS SCRIPT EXISTS: GitHub Pages publishes `deploy/ghpages/` from the
# **main** branch, but all 3.0 work lives on the **v3** branch. So this builds
# the preview here and writes it into the MAIN worktree's bundle. After running
# it, commit + push MAIN and the Action ships it.
#
# Three things are rewritten for the subpath, none of which are optional:
#   1. noindex on both pages, this is unreleased work sitting on the live
#      domain and must never be indexed or outrank the real pages.
#   2. The marketing page's app links point at the PRODUCTION app; they're
#      repointed to the preview app so you're actually testing 3.0.
#   3. sw.js is patched, see the block below. Skipping it would let the
#      preview delete production's cache.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

V3="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN="C:/Users/amwhi/repos/My Nail Connection"
OUT="$MAIN/deploy/ghpages/v3"

[ -d "$MAIN/deploy/ghpages" ] || { echo "ERROR: main worktree bundle not found at $MAIN"; exit 1; }
[ -f "$V3/marketing-v3.html" ] || { echo "ERROR: marketing-v3.html not found"; exit 1; }

echo "Building 3.0 preview -> $OUT"
rm -rf "$OUT"; mkdir -p "$OUT/app"

# ── App bundle (already assembled by sync.sh) ────────────────────────────
cp -r "$V3/deploy/ghpages/app/." "$OUT/app/"

# ── Marketing page ──────────────────────────────────────────────────────
cp "$V3/marketing-v3.html" "$OUT/index.html"
cp -r "$V3/images" "$OUT/images"
cp "$V3/og-image.png" "$OUT/og-image.png"
cp "$V3/og-image.png" "$OUT/app/og-image.png"
[ -d "$V3/app-screens" ] && cp -r "$V3/app-screens" "$OUT/app-screens"

python - "$OUT" <<'PYEOF'
import sys, re, os, json
out = sys.argv[1]

NOINDEX = '<meta name="robots" content="noindex, nofollow"/>'

# ── 1. Marketing page ───────────────────────────────────────────────────
p = os.path.join(out, 'index.html')
s = open(p, encoding='utf-8').read()

# noindex (replace the SEO robots tag rather than adding a second one)
s2, n = re.subn(r'<meta name="robots" content="[^"]*"\s*/?>', NOINDEX, s, count=1)
s = s2 if n else s.replace('</title>', '</title>\n' + NOINDEX, 1)

# Repoint every production app link at the preview app
appdir = s.count('https://mynailconnection.com/app/')
s = s.replace('https://mynailconnection.com/app/', 'app/')

# og: tags must stay ABSOLUTE (scrapers ignore relative), but must point at the
# PREVIEW, or texting a /v3 link shows the production card. Undo the blanket
# rewrite above for og:url, then move both url and image onto /v3.
s = s.replace('content="app/"', 'content="https://mynailconnection.com/v3/app/"')
s = s.replace('property="og:url" content="https://mynailconnection.com/"',
              'property="og:url" content="https://mynailconnection.com/v3/"')
s = s.replace('https://mynailconnection.com/og-image.png',
              'https://mynailconnection.com/v3/og-image.png')

# Obvious preview banner + a big button through to the app
banner = (
 '<style>#v3bar{position:sticky;top:0;z-index:9999;background:linear-gradient(135deg,#4A4A4F,#141317);'
 'color:#fff;font-family:"DM Sans",system-ui,sans-serif;padding:6px 12px;display:flex;gap:10px;'
 'align-items:center;justify-content:center;font-size:12.5px;line-height:1;}'
 '#v3bar b{letter-spacing:1.1px;text-transform:uppercase;font-size:10px;font-weight:700;}'
 '#v3bar a{background:rgba(255,255,255,0.16);border:1px solid rgba(255,255,255,0.32);color:#fff;'
 'text-decoration:none;font-weight:700;padding:5px 12px;border-radius:100px;white-space:nowrap;font-size:12px;}'
 '@media(max-width:520px){#v3bar span{display:none}}</style>'
 '<div id="v3bar"><b>3.0 Preview</b><span style="opacity:0.85;">Not the live site.</span>'
 '<a href="app/">Open the app &rarr;</a></div>'
)
s = re.sub(r'(<body[^>]*>)', r'\1\n' + banner, s, count=1)
open(p, 'w', encoding='utf-8').write(s)
print(f'  marketing: noindex set, {appdir} app link(s) repointed, banner+button added')

# ── 2. App page ─────────────────────────────────────────────────────────
p = os.path.join(out, 'app', 'index.html')
s = open(p, encoding='utf-8').read()
# Same og: fix as the marketing page: keep them absolute, point them at /v3.
s = s.replace('property="og:url" content="https://mynailconnection.com/app/"',
              'property="og:url" content="https://mynailconnection.com/v3/app/"')
s = s.replace('https://mynailconnection.com/og-image.png',
              'https://mynailconnection.com/v3/app/og-image.png')
if 'name="robots"' in s:
    s = re.sub(r'<meta name="robots" content="[^"]*"\s*/?>', NOINDEX, s, count=1)
else:
    s = s.replace('</title>', '</title>\n' + NOINDEX, 1)
open(p, 'w', encoding='utf-8').write(s)
print('  app: noindex set')

# ── 3. Service worker, isolate from production ──────────────────────────
# Two bugs bite at a subpath:
#   a) STATIC_ASSETS are root-absolute ('/', '/index.html'), so the preview SW
#      would precache the PRODUCTION homepage instead of its own.
#   b) activate deletes every cache whose name != CACHE_NAME, so the preview
#      would wipe production's cache (and prod would wipe the preview's).
p = os.path.join(out, 'app', 'sw.js')
s = open(p, encoding='utf-8').read()
m = re.search(r"const CACHE_NAME = '([^']+)'", s)
orig = m.group(1) if m else 'mnc'
s = s.replace(f"const CACHE_NAME = '{orig}'", f"const CACHE_NAME = 'mnc-v3preview-{orig}'")
s = s.replace("const STATIC_ASSETS = ['/', '/index.html', '/manifest.json'];",
              "const STATIC_ASSETS = ['./', './index.html', './manifest.json'];")
s = s.replace("keys.filter(k => k !== CACHE_NAME)",
              "keys.filter(k => k.startsWith('mnc-v3preview-') && k !== CACHE_NAME)")
open(p, 'w', encoding='utf-8').write(s)
print(f"  sw.js: cache -> mnc-v3preview-{orig}, assets relative, deletion scoped to preview caches only")

# ── 4. Manifest, label it so the install is unmistakable ────────────────
p = os.path.join(out, 'app', 'manifest.json')
d = json.load(open(p))
d['name'] = 'MNC 3.0 PREVIEW'; d['short_name'] = 'MNC 3.0'
json.dump(d, open(p, 'w'), indent=2)
print('  manifest: MNC 3.0 PREVIEW')
PYEOF

# ── robots.txt, keep the whole preview out of search ────────────────────
R="$MAIN/deploy/ghpages/robots.txt"
if [ -f "$R" ] && ! grep -q "Disallow: /v3" "$R"; then
  printf '\n# 3.0 preview, unreleased. Never index.\nDisallow: /v3/\n' >> "$R"
  echo "  robots.txt: Disallow /v3/ added"
fi

echo
echo "Done. Files: $(find "$OUT" -type f | wc -l)   Size: $(du -sh "$OUT" | cut -f1)"
echo "Next: commit + push MAIN, then visit https://mynailconnection.com/v3"
