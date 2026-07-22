#!/usr/bin/env python3
"""
One-time backfill: write a 500px _thumb.jpg next to every photo already in
the tech-photos bucket.

WHY THIS EXISTS
    The app used to size images through Supabase's image-transform endpoint.
    Transforms bill per unique ORIGIN IMAGE PER MONTH (100/mo included on
    Pro, $5 per 1,000 after), so the cost tracked the size of the photo
    library and recurred forever for photos that never change. 183 real
    photos blew the quota in two days of testing, 2026-07-21.

    index.html now reads <name>_thumb.jpg for every small slot (grids,
    avatars, detail tiles) and writes one at upload time (uploadThumb).
    This script fills in the photos that predate that change.

    Photos with no thumb still display: mncThumb's data-fb attribute falls
    back to the original. They are just heavier. So this is a performance
    backfill, not a repair, and it is safe to run at any time.

SAFETY
    Only ever ADDS files. Never overwrites an original, never deletes.
    Idempotent: an existing thumb is skipped, so re-running is free.
    Run with --dry-run first to see exactly what it would do.

USAGE
    Get the service_role key:
        Supabase dashboard -> Project Settings -> API -> service_role
        (This is a secret. Do not paste it into chat or commit it.)

    PowerShell:
        $env:SUPABASE_SERVICE_KEY = "paste-the-key-here"
        python deploy/backfill-thumbs.py --dry-run
        python deploy/backfill-thumbs.py

    Clear it afterwards:
        Remove-Item Env:\\SUPABASE_SERVICE_KEY
"""

import io
import json
import os
import sys
import urllib.error
import urllib.request

from PIL import Image, ImageOps

SB = "https://nwqnakoongrorbwnrqzc.supabase.co"
BUCKET = "tech-photos"
MAX_DIM = 500       # longest side; covers every small slot we paint, even at 3x
QUALITY = 72
PUBLIC_PREFIX = "/storage/v1/object/public/" + BUCKET + "/"

DRY = "--dry-run" in sys.argv

KEY = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
if not KEY:
    sys.exit(
        "SUPABASE_SERVICE_KEY is not set.\n"
        "  Supabase dashboard -> Project Settings -> API -> service_role\n"
        '  PowerShell:  $env:SUPABASE_SERVICE_KEY = "..."'
    )


def api(path):
    req = urllib.request.Request(
        SB + path, headers={"apikey": KEY, "Authorization": "Bearer " + KEY}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def collect_urls():
    """Every distinct image URL referenced by a tech row."""
    urls = []
    for t in api("/rest/v1/techs?select=image_url,photos&limit=2000"):
        photos = t.get("photos") or []
        if isinstance(photos, str):
            try:
                photos = json.loads(photos)
            except Exception:
                photos = []
        for u in [t.get("image_url")] + list(photos):
            if isinstance(u, dict):
                u = u.get("url")
            if isinstance(u, str) and PUBLIC_PREFIX in u:
                urls.append(u.split("?")[0])
    # dict.fromkeys keeps first-seen order, which makes the log readable
    return list(dict.fromkeys(urls))


def thumb_path(url):
    """profile/abc.png -> profile/abc_thumb.jpg   (path within the bucket)"""
    rel = url.split(PUBLIC_PREFIX, 1)[1]
    base = rel.rsplit(".", 1)[0] if "." in rel.rsplit("/", 1)[-1] else rel
    return base + "_thumb.jpg"


def exists(path):
    req = urllib.request.Request(SB + PUBLIC_PREFIX + path, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=20):
            return True
    except urllib.error.HTTPError:
        return False
    except Exception:
        return False


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def make_thumb(raw):
    im = Image.open(io.BytesIO(raw))
    im = ImageOps.exif_transpose(im)          # honour phone orientation
    im = im.convert("RGB")                    # flatten alpha, JPEG has none
    im.thumbnail((MAX_DIM, MAX_DIM), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "JPEG", quality=QUALITY, optimize=True, progressive=True)
    return out.getvalue()


def upload(path, blob):
    req = urllib.request.Request(
        SB + "/storage/v1/object/" + BUCKET + "/" + path,
        data=blob,
        method="POST",
        headers={
            "apikey": KEY,
            "Authorization": "Bearer " + KEY,
            "Content-Type": "image/jpeg",
            "x-upsert": "true",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status


def main():
    urls = collect_urls()
    print("%d unique images referenced by techs%s\n"
          % (len(urls), "   [DRY RUN, nothing will be written]" if DRY else ""))

    made = skipped = failed = 0
    src_bytes = thumb_bytes = 0

    for i, url in enumerate(urls, 1):
        tp = thumb_path(url)
        name = tp.rsplit("/", 1)[-1]
        try:
            if exists(tp):
                skipped += 1
                print("  %3d/%d  skip     %s" % (i, len(urls), name))
                continue
            raw = fetch(url)
            blob = make_thumb(raw)
            src_bytes += len(raw)
            thumb_bytes += len(blob)
            if DRY:
                print("  %3d/%d  would    %-46s %6.0fKB -> %5.0fKB"
                      % (i, len(urls), name, len(raw) / 1024, len(blob) / 1024))
            else:
                upload(tp, blob)
                print("  %3d/%d  wrote    %-46s %6.0fKB -> %5.0fKB"
                      % (i, len(urls), name, len(raw) / 1024, len(blob) / 1024))
            made += 1
        except Exception as e:
            failed += 1
            print("  %3d/%d  FAILED   %-46s %s" % (i, len(urls), name, e))

    print("\n  created %d   skipped %d   failed %d" % (made, skipped, failed))
    if made:
        print("  %.1fMB of originals -> %.1fMB of thumbs  (%.0f%% smaller)"
              % (src_bytes / 1e6, thumb_bytes / 1e6,
                 100 * (1 - thumb_bytes / max(src_bytes, 1))))
    if failed:
        print("\n  Failures are safe to ignore or re-run: those photos simply")
        print("  fall back to their original via data-fb. Re-running skips")
        print("  everything that already succeeded.")


if __name__ == "__main__":
    main()
