# Rebuild the Google Play feature graphic (1024x500) for MNC 3.0.
#
# The old one (docs/play-store-assets/, Jul 4) predates the 3.0 rebrand and the
# pivot to techs. This mirrors og-image.png: ivory ground, mauve wash and the
# hat-lady bleeding off the right, type on the left.
#
# Play-specific constraints this design respects:
#   * 1024x500 exactly, RGB, no alpha (Play rejects transparency)
#   * It is displayed SMALL and often cropped on the sides, so every word sits
#     well inside the middle and nothing important is near an edge
#   * No store badges, no device frames, no "Download now" - all against
#     Google's metadata policy and a common rejection reason
#   * No price. It renders tiny and it is the field most likely to go stale;
#     the full description carries the number.
#
# Run: py -3 make_play_feature.py
from PIL import Image, ImageDraw, ImageFont

W, H = 1024, 500
IVORY = (237, 234, 229)
BLACK = (20, 19, 23)
DEEP  = (125, 100, 120)
MUTED = (110, 100, 110)

PLAYFAIR   = "marketing-slides/PlayfairDisplay.ttf"
PLAYFAIR_I = "marketing-slides/PlayfairDisplay-Italic.ttf"
DMSANS     = "marketing-slides/DMSans.ttf"

def pf(size, weight=400, italic=False):
    f = ImageFont.truetype(PLAYFAIR_I if italic else PLAYFAIR, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f

def dm(size, weight=400):
    f = ImageFont.truetype(DMSANS, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f

card = Image.new("RGB", (W, H), IVORY)

# Soft mauve wash behind the art side, same motif as the OG card and the hero.
wash = Image.new("RGB", (W, H), IVORY)
wd = ImageDraw.Draw(wash)
wd.ellipse([560, -200, 1320, 620], fill=(228, 219, 227))
card = Image.blend(card, wash, 0.5)
d = ImageDraw.Draw(card)

# ---- the lady: anchored RIGHT, bleeding off the edge ----
lady = Image.open("marketing/brand/mnc-3.0-logo-hat-lady.png").convert("RGB")
lh = 500                                  # full bleed, top to bottom
lw = int(lady.width * (lh / lady.height))
lady = lady.resize((lw, lh), Image.LANCZOS)

# Feather the left edge so the art dissolves into the ivory instead of
# ending on a hard vertical line.
band = 190
mask = Image.new("L", (lw, lh), 255)
md = ImageDraw.Draw(mask)
for i in range(band):
    md.line([(i, 0), (i, lh)], fill=int(255 * (i / band)))
card.paste(lady, (W - lw + 40, 0), mask)

# ---- type, left side, inside the safe area ----
x = 64

d.text((x, 96), "MY NAIL CONNECTION", font=dm(19, 700), fill=DEEP)

d.text((x, 146), "Booking built",  font=pf(62, 700), fill=BLACK)
d.text((x, 216), "for nail techs.", font=pf(62, 700, italic=True), fill=DEEP)

d.text((x, 312), "No commission. No per-booking fee.",
       font=dm(23, 500), fill=MUTED)
d.text((x, 348), "Your work is your booking page.",
       font=dm(23, 500), fill=MUTED)

# Three category chips, echoing the Gallery's shape / type / style filters.
chips = ["Shape", "Type", "Style"]
cx = x
for c in chips:
    f = dm(19, 700)
    tw = d.textbbox((0, 0), c, font=f)[2]
    d.rounded_rectangle([cx, 404, cx + tw + 30, 444], radius=20,
                        fill=(228, 219, 227))
    d.text((cx + 15, 413), c, font=f, fill=(70, 55, 70))
    cx += tw + 44

card.save("docs/play-store-assets/mnc-play-feature-graphic-1024x500.png",
          optimize=True)
print("wrote docs/play-store-assets/mnc-play-feature-graphic-1024x500.png",
      card.size)
