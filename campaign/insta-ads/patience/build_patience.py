"""The patience set: a single illustration and a six-panel comic about the
client side being early. Sources: source-single.png (1024, Copilot) and
source-comic.png (1254, ChatGPT), 2026-09-24.

What this makes, in campaign-assets/2026-09/patience/:
  single-1080.png, single-story.png, single-feed-4x5.png   (badge removed)
  comic-1080.png, comic-story.png                            (real app screens on
                                                              the two blank phones,
                                                              wordmark line in the
                                                              blank strip)
  panels/01..06.png + 07.png closing brand card              (1080 square each)
  panels.zip, everything.zip
Run from this folder:  python build_patience.py
"""
import json, os, pathlib, sys, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'comic'))
import screens as S                       # renderers and the warp helper from the first comic

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parents[2] / 'campaign-assets' / '2026-09' / 'patience'
(OUT / 'panels').mkdir(parents=True, exist_ok=True)
BLUSH = (247, 226, 227)

# ── the single ────────────────────────────────────────────────────────────
single = Image.open(HERE / 'source-single.png').convert('RGB')
# "Made with AI" badge, top right: cover it with plain paper from its left.
patch = single.crop((700, 8, 852, 54))
single.paste(patch, (862, 8))
single.resize((1080, 1080), Image.LANCZOS).save(OUT / 'single-1080.png')
story = Image.new('RGB', (1080, 1920), BLUSH); story.paste(single.resize((1000, 1000), Image.LANCZOS), (40, 410)); story.save(OUT / 'single-story.png')
feed = Image.new('RGB', (1080, 1350), BLUSH); feed.paste(single.resize((1080, 1080), Image.LANCZOS), (0, 135)); feed.save(OUT / 'single-feed-4x5.png')

# ── the comic: real 3.0 screens on the two blank phones ───────────────────
src = Image.open(HERE / 'source-comic.png').convert('RGB'); W, H = src.size
from PIL import ImageFont
FONT = r'C:\Windows\Fonts\comicbd.ttf'
INK = (20, 19, 23, 255)
# Every phone is drawn as its back: the characters look at their screens, so
# the reader sees the back (Anne, 2026-09-24: with screens facing out they all
# looked held backwards). PATIENCE_SCREENS=1 puts the real 3.0 app on the two
# blank screens instead.
BACKS = os.environ.get('PATIENCE_SCREENS') != '1'
# Phone screens, corners measured by hand on a 4x grid of the source
# (TL, TR, BR, BL). The screen bottoms sit under the hands, so the quads run
# to where the phone body ends and the hand is restored afterwards.
QUADS = {
    'p1':      [(171, 360), (232, 355), (214, 470), (145, 470)],   # panel 1, blank in the art
    'menu':    [(678, 352), (760, 350), (735, 478), (648, 478)],   # panel 2
    'profile': [(630, 967), (692, 965), (673, 1050), (608, 1050)], # panel 5
    'p6':      [(860, 892), (907, 891), (939, 1000), (876, 1000)], # panel 6, blank in the art
}
def hand_mask(quad, sat_min=22, lo_max=150):
    """Base pixels inside the quad that are not blank paper: skin, nails,
    outlines. Those come back on top of whatever was pasted. The dark backs
    need the strict thresholds or the paper's halftone dots come back too."""
    poly = Image.new('L', (W, H), 0); ImageDraw.Draw(poly).polygon(quad, fill=255)
    a = np.asarray(src).astype(int); sat = a.max(2) - a.min(2); lo = a.min(2)
    m = ((sat > sat_min) | (lo < lo_max)) & (np.asarray(poly) > 0)
    return Image.fromarray((m * 255).astype('uint8')).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
def phone_back(w=440, h=740):
    """A charcoal phone back with a camera block, drawn flat and warped later."""
    im = Image.new('RGB', (w, h), (44, 43, 48)); d = ImageDraw.Draw(im)
    g = np.linspace(0, 1, h)[:, None, None]
    im = Image.fromarray((np.asarray(im) * (1 - 0.18 * g)).astype('uint8')); d = ImageDraw.Draw(im)
    d.rounded_rectangle((3, 3, w - 4, h - 4), radius=36, outline=(70, 69, 76), width=4)
    d.rounded_rectangle((28, 28, 28 + 150, 28 + 150), radius=34, fill=(28, 27, 31), outline=(62, 61, 68), width=3)
    for cx, cy in ((68, 68), (138, 68), (68, 138)):
        d.ellipse((cx - 24, cy - 24, cx + 24, cy + 24), fill=(18, 17, 20), outline=(80, 79, 86), width=3)
        d.ellipse((cx - 11, cy - 11, cx + 11, cy + 11), fill=(40, 44, 60))
        d.ellipse((cx - 5, cy - 9, cx + 1, cy - 3), fill=(120, 130, 160))
    d.ellipse((138 - 9, 138 - 9, 138 + 9, 138 + 9), fill=(230, 220, 190))
    return im
def cover_text(bbox, angle, text, size, pad=4):
    """Paint over lettering with the paper tone between its letters, then
    letter the box again, condensed to fit when the new word is wider."""
    global out
    x0, y0, x1, y1 = bbox
    px = np.asarray(src.crop(bbox)).reshape(-1, 3); tone = tuple(int(v) for v in np.percentile(px, 88, axis=0))
    w, h = x1 - x0 + 2 * pad, y1 - y0 + 2 * pad
    lay = Image.new('RGBA', (w, h), tone + (255,))
    noise = np.random.default_rng(3).normal(0, 3, (h, w, 1)); arr = np.asarray(lay).astype(float); arr[..., :3] += noise
    lay = Image.fromarray(arr.clip(0, 255).astype('uint8'))
    if text:
        f = ImageFont.truetype(FONT, size); tb = ImageDraw.Draw(lay).textbbox((0, 0), text, font=f)
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
        t = Image.new('RGBA', (tw + 2, th + 2), (0, 0, 0, 0)); ImageDraw.Draw(t).text((1 - tb[0], 1 - tb[1]), text, font=f, fill=INK)
        avail = w - 2 * pad
        if t.width > avail: t = t.resize((avail, t.height), Image.LANCZOS)
        lay.paste(t, (pad, (h - t.height) // 2), t)
    lay = lay.rotate(angle, resample=Image.BICUBIC, expand=True)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    out.paste(lay, (int(cx - lay.width / 2), int(cy - lay.height / 2)), lay)
out = src.copy()
grain = np.asarray(src.convert('L')).astype(float) / 255.0
placed = Image.new('L', (W, H), 0); pd = ImageDraw.Draw(placed)
if BACKS:
    back = phone_back()
    for name in ('p1', 'menu', 'profile', 'p6'):
        q = QUADS[name]; S.paste_screen(out, back, q, radius=0.05)
        out = Image.composite(src, out, hand_mask(q, 32, 70)); pd.polygon(q, fill=255)
else:
    menu = S.render('menu', 440, 680, S.MENU_CSS, S.MENU)          # panel 2: "Wait, this is new"
    profile = S.render('profile', 440, 600, S.PROFILE_CSS, S.PROFILE)  # panel 5: checking back, a tech found
    for name, img in (('menu', menu), ('profile', profile)):
        q = QUADS[name]; S.paste_screen(out, img, q, radius=0.05)
        out = Image.composite(src, out, hand_mask(q)); pd.polygon(q, fill=255)
# Lettering that named the West Valley. The set is for anywhere in the US.
# Panel 1's search box said "Surprise, AZ"; panel 3's five tags named West
# Valley towns. Nothing here goes into `placed`: the grain pass would print
# the old letters back through.
cover_text((280, 291, 364, 315), 3.7, 'Your city', 19)
TAGS = [  # the tag's text area in the source, tilt, new city
    ((878, 228, 948, 258), 6.0, 'Atlanta'),
    ((1112, 313, 1192, 342), 2.0, 'Seattle'),
    ((868, 468, 928, 498), 3.0, 'Austin'),
    ((997, 500, 1068, 530), 2.0, 'Chicago'),
    ((1150, 500, 1224, 528), 1.0, 'Denver'),
]
for bbox, ang, city in TAGS:
    cover_text(bbox, ang, city, 22)
# the blank strip under the panels carries the wordmark
strip_css = """body{background:#fff}.s{width:100%;height:100%;display:flex;align-items:center;justify-content:center;gap:28px}
.w{font-family:'Playfair Display',serif;font-style:italic;font-weight:600;font-size:56px;color:#141317}
.u{font-family:'DM Sans',sans-serif;font-size:30px;font-weight:600;color:#A2636C;letter-spacing:.5px}"""
strip = S.render('pstrip', 2508, 132, strip_css, '<div class="s"><span class="w">My Nail Connection</span><span class="u">mynailconnection.com</span></div>').resize((W, 66), Image.LANCZOS)
out.paste(strip, (0, 1182)); pd.rectangle((0, 1182, W, 1248), fill=255)
# paper grain over what was pasted
a = np.asarray(out).astype(float); m = (np.asarray(placed).astype(float) / 255.0)[..., None]
a = a * (1 - m) + a * np.clip(grain, 0.86, 1.0)[..., None] * m
out = Image.fromarray(a.clip(0, 255).astype('uint8'))
out.resize((1080, 1080), Image.LANCZOS).save(OUT / 'comic-1080.png')
st = Image.new('RGB', (1080, 1920), BLUSH); st.paste(out.resize((1000, 1000), Image.LANCZOS), (40, 410)); st.save(OUT / 'comic-story.png')

# ── panel cards, from the frame lines measured on the source ──────────────
xs = [0, 431, 825, W]; ys = [0, 548, 1180]
n = 0
for r in range(2):
    for c in range(3):
        n += 1
        p = out.crop((xs[c], ys[r], xs[c + 1], ys[r + 1]))
        side = max(p.size) + 60
        card = Image.new('RGB', (side, side), (244, 238, 236)); card.paste(p, ((side - p.width) // 2, (side - p.height) // 2))
        card.resize((1080, 1080), Image.LANCZOS).save(OUT / 'panels' / f'{n:02d}.png')
closing = Image.new('RGB', (1080, 1080), (244, 238, 236))
band = S.render('pband', 2508, 564, S.BAND_CSS, S.BAND).resize((1080, 243), Image.LANCZOS)
closing.paste(band, (0, (1080 - 243) // 2)); closing.save(OUT / 'panels' / '07.png')

# ── zips ──────────────────────────────────────────────────────────────────
with zipfile.ZipFile(OUT / 'panels.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for f in sorted((OUT / 'panels').glob('*.png')): z.write(f, f.name)
with zipfile.ZipFile(OUT / 'everything.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for f in sorted(OUT.glob('*.png')): z.write(f, f.name)
    for f in sorted((OUT / 'panels').glob('*.png')): z.write(f, 'panels/' + f.name)
print('wrote', sorted(p.name for p in OUT.iterdir()))
