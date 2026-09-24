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
from PIL import Image, ImageDraw
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
def screen_quad(seed):
    im = src.copy(); ImageDraw.floodfill(im, seed, (0, 255, 0), thresh=55)
    m = np.all(np.asarray(im) == (0, 255, 0), axis=2); ys, xs = np.nonzero(m)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max(); h, w = y1 - y0, x1 - x0
    rows = range(int(y0 + .15 * h), int(y1 - .15 * h)); cols = range(int(x0 + .15 * w), int(x1 - .15 * w))
    def fit(pts, axis):
        p = np.array(pts, float); t, v = (p[:, 1], p[:, 0]) if axis == 'x' else (p[:, 0], p[:, 1])
        a, b = np.polyfit(t, v, 1); return a, b
    L = fit([(np.nonzero(m[y])[0].min(), y) for y in rows], 'x'); R = fit([(np.nonzero(m[y])[0].max(), y) for y in rows], 'x')
    T = fit([(x, np.nonzero(m[:, x])[0].min()) for x in cols], 'y'); B = fit([(x, np.nonzero(m[:, x])[0].max()) for x in cols], 'y')
    def c(xl, yl):
        y = (yl[0] * xl[1] + yl[1]) / (1 - xl[0] * yl[0]); return (float(xl[0] * y + xl[1]), float(y))
    return [c(L, T), c(R, T), c(R, B), c(L, B)], (w, h)
out = src.copy()
grain = np.asarray(src.convert('L')).astype(float) / 255.0
placed = Image.new('L', (W, H), 0); pd = ImageDraw.Draw(placed)
menu = S.render('menu', 440, 740, S.MENU_CSS, S.MENU)          # panel 2: "Wait, this is new"
profile = S.render('profile', 440, 760, S.PROFILE_CSS, S.PROFILE)  # panel 5: checking back, a tech found
for seed, img in (((700, 400), menu), ((660, 1010), profile)):
    q, size = screen_quad(seed); print('screen at', seed, 'is', size)
    S.paste_screen(out, img, [tuple(p) for p in q], radius=0.05); pd.polygon([tuple(p) for p in q], fill=255)
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
