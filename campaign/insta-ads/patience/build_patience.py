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
# The two blank phones, corners measured by hand on a 4x grid of the source
# (TL, TR, BR, BL). The screen bottoms sit under the hands, so the quads run
# to where the phone body ends and the hand is restored afterwards.
QUADS = {
    'menu':    [(678, 352), (760, 350), (735, 478), (648, 478)],   # panel 2
    'profile': [(630, 967), (692, 965), (673, 1050), (608, 1050)], # panel 5
}
def hand_mask(quad):
    """Base pixels inside the quad that are not blank paper: skin, nails,
    outlines. Those come back on top of the pasted screen."""
    poly = Image.new('L', (W, H), 0); ImageDraw.Draw(poly).polygon(quad, fill=255)
    a = np.asarray(src).astype(int); sat = a.max(2) - a.min(2); lo = a.min(2)
    m = ((sat > 22) | (lo < 150)) & (np.asarray(poly) > 0)
    k = Image.fromarray((m * 255).astype('uint8')).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    return k
out = src.copy()
grain = np.asarray(src.convert('L')).astype(float) / 255.0
placed = Image.new('L', (W, H), 0); pd = ImageDraw.Draw(placed)
menu = S.render('menu', 440, 680, S.MENU_CSS, S.MENU)          # panel 2: "Wait, this is new"
profile = S.render('profile', 440, 600, S.PROFILE_CSS, S.PROFILE)  # panel 5: checking back, a tech found
for name, img in (('menu', menu), ('profile', profile)):
    q = QUADS[name]
    S.paste_screen(out, img, q, radius=0.05)
    out = Image.composite(src, out, hand_mask(q))
    pd.polygon(q, fill=255)
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
