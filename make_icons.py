# Generate the MNC 3.0 icon set from the hat-lady artwork.
# Two crops on purpose: the full lady has room to breathe at app-icon sizes,
# but turns to noise by 32px, so the favicon uses a tighter, bolder crop
# (hat brim + eyes + lips) that survives.
from PIL import Image, ImageDraw, ImageFont
import pathlib

SRC = Image.open("marketing/brand/mnc-3.0-logo-hat-lady.png").convert("RGB")
IVORY = (237, 234, 229)          # #EDEAE5, matches the artwork background
BLUSH = (247, 235, 238)          # #F7EBEE, the wordmark colour on the black brim

FULL  = (35, 25, 675, 600)       # hat + face + lips + nails
TIGHT = (130, 95, 470, 415)      # hat brim + eyes + lips, balanced to read at 32px

# The favicon carries "MNC" on the hat brim (Anne, 2026-07-15). The brim is a
# solid full-width black band at y~40-115 of the TIGHT crop, and it is the one
# shape that survives at 16-32px, so a wordmark there is what makes the favicon
# legible at all. Playfair Display is a VARIABLE font (weight 400-900); 400 is
# the brand wordmark weight but its thin serifs disintegrate small, so the
# favicon uses 700.
FONT_PATH  = "marketing-slides/PlayfairDisplay.ttf"
BRIM_TEXT  = "MNC"
BRIM_WEIGHT, BRIM_SIZE, BRIM_Y, BRIM_TRACK = 700, 64, 75, 10

def brim_wordmark(crop):
    """Draw MNC centred on the hat brim of a TIGHT-crop image (in place copy)."""
    c = crop.copy()
    w, h = c.size
    d = ImageDraw.Draw(c)
    f = ImageFont.truetype(FONT_PATH, BRIM_SIZE)
    f.set_variation_by_axes([BRIM_WEIGHT])
    widths = [d.textbbox((0, 0), ch, font=f)[2] - d.textbbox((0, 0), ch, font=f)[0] for ch in BRIM_TEXT]
    total = sum(widths) + BRIM_TRACK * (len(BRIM_TEXT) - 1)
    x = (w - total) / 2
    for ch, cw in zip(BRIM_TEXT, widths):
        bb = d.textbbox((0, 0), ch, font=f)
        d.text((x - bb[0], BRIM_Y - (bb[3] - bb[1]) / 2 - bb[1]), ch, font=f, fill=BLUSH)
        x += cw + BRIM_TRACK
    return c

def square(box, pad_frac=0.0, wordmark=False):
    c = SRC.crop(box)
    if wordmark:
        c = brim_wordmark(c)
    side = int(max(c.size) * (1 + pad_frac * 2))
    o = Image.new("RGB", (side, side), IVORY)
    o.paste(c, ((side - c.size[0]) // 2, (side - c.size[1]) // 2))
    return o

full_sq  = square(FULL)
tight_sq = square(TIGHT, wordmark=True)
# maskable: content must sit inside the central ~80% safe zone or launchers clip it
mask_sq  = square(FULL, pad_frac=0.16)

def out(img, path, size, fmt=None, **kw):
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    im = img.resize((size, size), Image.LANCZOS)
    im.save(p, format=fmt, **kw)
    return f"  {path:<36} {size:>4}px  {p.stat().st_size/1024:>6.1f}KB"

lines = []
# --- favicons: TIGHT crop ---
lines.append(out(tight_sq, "favicon-32.png", 32, optimize=True))
# save the .ico from the FULL-RES crop: PIL downsamples to each listed size.
# passing an already-16px image writes only a 16x16 entry (and any larger entry
# would be an upscaled blob).
tight_sq.resize((256, 256), Image.LANCZOS).save(
    "favicon.ico", format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
lines.append(f"  {'favicon.ico':<36} 16/32/48  {pathlib.Path('favicon.ico').stat().st_size/1024:>5.1f}KB")
lines.append(out(tight_sq, "images/mncLogo-32.webp", 32, quality=92, method=6))
lines.append(out(tight_sq, "images/mncLogo-64.webp", 64, quality=92, method=6))

# --- app icons: FULL lady ---
lines.append(out(full_sq, "apple-touch-icon.png", 180, optimize=True))
for size in (180, 192, 512, 1024):
    lines.append(out(full_sq, f"images/mncLogo-{size}.webp", size, quality=90, method=6))
lines.append(out(full_sq, "images/mncLogo-round-256.webp", 256, quality=90, method=6))
lines.append(out(full_sq, "images/mncLogo-round-512.webp", 512, quality=90, method=6))
lines.append(out(full_sq, "images/mncLogo-1024.png", 1024, optimize=True))
# Google Play store icon, 512x512. Emitted here so it cannot drift from the
# launcher again: the previous one was dated 2026-07-04, BEFORE the 3.0
# hat-lady art landed (07-16), so the Play listing showed 2.0 branding while
# phones showed 3.0.
#
# WARNING (2026-08-23): running this script no longer reproduces the icons that
# are committed. Regenerating everything showed a max channel difference of
# 230-246 against apple-touch-icon.png, favicon-32.png and mncLogo-1024.png --
# i.e. a real visual change, not compression. Either the source art moved after
# the icons were cut, or they were touched by hand. Until that is resolved, do
# NOT run this before a release expecting a no-op; the 512 shipped for Play was
# downscaled from the committed images/mncLogo-1024.png instead, which matches
# the launcher pixel for pixel.
lines.append(out(full_sq, "docs/play-store-assets/mnc-play-icon-512.png", 512, optimize=True))

# --- maskable: padded safe zone ---
lines.append(out(mask_sq, "images/mncLogo-maskable.webp", 512, quality=90, method=6))

print("\n".join(lines))
