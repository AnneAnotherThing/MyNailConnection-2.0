# Rebuild og-image.png (1200x630) for MNC 3.0.
# The old card was fully 2.0: rose-gold hand+flower mark and "Find Your Tech.
# Love Your Nails." (client-first). The customer is now the TECH, so the card
# leads with the locked pivot line and the hat-lady identity.
from PIL import Image, ImageDraw, ImageFont
import pathlib

W, H = 1200, 630
IVORY = (237, 234, 229)
BLACK = (20, 19, 23)
DEEP  = (125, 100, 120)
MAUVE = (191, 166, 187)
MUTED = (110, 100, 110)

PLAYFAIR = "marketing-slides/PlayfairDisplay.ttf"
PLAYFAIR_I = "marketing-slides/PlayfairDisplay-Italic.ttf"
DMSANS = "marketing-slides/DMSans.ttf"

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

# soft mauve wash behind the ART side (right), mirroring the hero
wash = Image.new("RGB", (W, H), IVORY)
wd = ImageDraw.Draw(wash)
wd.ellipse([620, -220, 1520, 720], fill=(228, 219, 227))
card = Image.blend(card, wash, 0.5)
d = ImageDraw.Draw(card)

# ---- the lady: anchored RIGHT and bleeding off it, exactly like the hero ----
lady = Image.open("marketing/brand/mnc-3.0-logo-hat-lady.png").convert("RGB")
lady = lady.crop((35, 25, 675, 600))
target_h = 660
scale = target_h / lady.size[1]
lady = lady.resize((int(lady.size[0] * scale), target_h), Image.LANCZOS)
lw, lh = lady.size
lx, ly = W - lw + 118, (H - lh) // 2

# fade her LEFT edge so she melts into the ivory and never touches the copy
mask = Image.new("L", lady.size, 255)
mk = ImageDraw.Draw(mask)
fade = 110
for i in range(fade):
    mk.line([(i, 0), (i, lh)], fill=int(255 * (i / fade)))
card.paste(lady, (lx, ly), mask)
d = ImageDraw.Draw(card)

# ---- text column, LEFT (hero-consistent) ----
x = 76
d.text((x, 128), "MY NAIL CONNECTION", font=dm(20, 700), fill=DEEP)

d.text((x, 178), "Still booking", font=pf(70, 700), fill=BLACK)
d.text((x, 256), "in your DMs?", font=pf(70, 700, italic=True), fill=DEEP)

sub = ["Free booking for nail techs, forever.", "Your work is your booking page."]
yy = 362
for line in sub:
    d.text((x, yy), line, font=dm(25, 400), fill=MUTED)
    yy += 38

chips = ["No commission", "No per-booking fee", "Nails only"]
cx = x
for c in chips:
    f = dm(19, 500)
    tw = d.textbbox((0, 0), c, font=f)[2]
    d.rounded_rectangle([cx, 456, cx + tw + 28, 494], radius=19, fill=(233, 224, 232), outline=DEEP, width=1)
    d.text((cx + 14, 466), c, font=f, fill=(70, 55, 70))
    cx += tw + 42

d.text((x, 528), "mynailconnection.com", font=dm(23, 700), fill=DEEP)

card.save("og-image.png", optimize=True)
p = pathlib.Path("og-image.png")
print(f"og-image.png  {card.size}  {p.stat().st_size/1024:.0f}KB")
