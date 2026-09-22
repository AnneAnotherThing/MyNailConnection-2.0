"""Finishes the v2 (Ben-Day pop art) comic from source-v2.png.

  - the three big phones get the real 3.0 screens (corners from fit_v2.py)
  - the screens and the band are multiplied by the source's paper grain,
    so they print like the rest of the page instead of floating on it
  - the brand band fills the blank strip ChatGPT left under the panels
  - exports: mnc-comic-v2-1254.png, mnc-comic-v2-1080.png (square),
    mnc-comic-v2-story.png (1080x1920), and panels/01..07.png for a
    swipe post (six panels plus the band as a closing card)

Run:  python fit_v2.py && python build_v2.py
"""
import json, pathlib
import numpy as np
from PIL import Image, ImageDraw
import screens as S     # the screen renderers and the warp helper

HERE = pathlib.Path(__file__).resolve().parent
src = Image.open(HERE / 'source-v2.png').convert('RGB')
W, H = src.size
Q = json.load(open(HERE / 'screens-v2.json'))
grain = np.asarray(src.convert('L')).astype(float) / 255.0   # paper texture

def apply_grain(img, mask):
    """Multiply img by the source paper grain where mask (L) is set."""
    a = np.asarray(img).astype(float)
    m = (np.asarray(mask).astype(float) / 255.0)[..., None]
    g = np.clip(grain, 0.86, 1.0)[..., None]      # keep the grain, not the ink
    a = a * (1 - m) + a * g * m
    return Image.fromarray(a.clip(0, 255).astype('uint8'))

out = src.copy()
placed = Image.new('L', (W, H), 0)
pd = ImageDraw.Draw(placed)

profile = S.render('profile', 440, 760, S.PROFILE_CSS, S.PROFILE)
thread = S.render('thread', 440, 730, S.THREAD_CSS, S.THREAD)
menu = S.render('menu', 440, 740, S.MENU_CSS, S.MENU)
for name, img in (('profile', profile), ('thread', thread), ('menu', menu)):
    quad = [tuple(p) for p in Q[name]]
    S.paste_screen(out, img, quad, radius=0.05)
    pd.polygon(quad, fill=255)

# Band in the blank strip. Last inked row is ~1020; leave a gutter.
BAND_TOP = 1034
bh = H - BAND_TOP                         # 220
band_css = S.BAND_CSS.replace('.wm{', '.wm{font-size:112px !important;') \
                     .replace('.tag{', '.tag{font-size:54px !important;margin-top:22px !important;') \
                     .replace('.fcg{', '.fcg{font-size:36px !important;margin-top:16px !important;') \
                     .replace('.mk{width:330px;height:330px;border-radius:70px;', '.mk{width:300px;height:300px;border-radius:64px;') \
                     .replace('.side{flex:none;width:640px;border-radius:44px;padding:52px 50px;', '.side{flex:none;width:600px;border-radius:40px;padding:40px 46px;') \
                     .replace('.side .h{font-family:\'Playfair Display\',serif;font-size:64px;', '.side .h{font-family:\'Playfair Display\',serif;font-size:56px;') \
                     .replace('background:linear-gradient(180deg,#FFFFFF 0%,#FBF8F8 100%)', 'background:#fff') \
                     .replace(".band::before{content:'';position:absolute;left:0;right:0;top:0;height:6px;background:linear-gradient(90deg,#4A4A4F,#141317)}", "")
band = S.render('band-v2', 2508, bh * 2, band_css, S.BAND).resize((W, bh), Image.LANCZOS)
out.paste(band, (0, BAND_TOP))
pd.rectangle((0, BAND_TOP, W, H), fill=255)

out = apply_grain(out, placed)
out.save(HERE / 'mnc-comic-v2-1254.png')
out.resize((1080, 1080), Image.LANCZOS).save(HERE / 'mnc-comic-v2-1080.png')

# Story: the square on a blush ground, mark-free since the band carries it.
story = Image.new('RGB', (1080, 1920), '#F7E2E3')
story.paste(out.resize((1000, 1000), Image.LANCZOS), (40, 400))
story.save(HERE / 'mnc-comic-v2-story.png')

# Panels for a swipe post: find the gutters from the frame lines.
L = np.asarray(src.convert('L'))
ink = L[:1020] < 90
colp = ink.mean(axis=0); rowp = ink[:, :].mean(axis=1)
def spans(profile, thresh, minlen):
    on = profile > thresh; res = []; start = None
    for i, v in enumerate(on):
        if v and start is None: start = i
        if not v and start is not None:
            if i - start >= minlen: res.append((start, i))
            start = None
    if start is not None and len(on) - start >= minlen: res.append((start, len(on)))
    return res
vlines = spans(colp, 0.55, 3)     # thick vertical frame lines
hlines = spans(rowp, 0.55, 3)
print('frame columns', vlines, 'frame rows', hlines)
# gutters are the double frame lines: (411,424), (830,842) across; (513,527) down
xs = [0, 417, 836, W]
ys = [0, 520, 1022]
PAN = HERE / 'panels'; PAN.mkdir(exist_ok=True)
n = 0
for r in range(len(ys) - 1):
    for c in range(len(xs) - 1):
        n += 1
        box = (xs[c], ys[r], xs[c + 1], ys[r + 1])
        p = out.crop(box)
        # square card on the paper colour so every panel is the same size
        side = max(p.size) + 60
        card = Image.new('RGB', (side, side), (244, 238, 236))
        card.paste(p, ((side - p.width) // 2, (side - p.height) // 2))
        card.resize((1080, 1080), Image.LANCZOS).save(PAN / f'{n:02d}.png')
closing = Image.new('RGB', (1080, 1080), (244, 238, 236))
closing.paste(out.crop((0, BAND_TOP - 10, W, H)).resize((1080, int(1080 * (H - BAND_TOP + 10) / W)), Image.LANCZOS),
              (0, (1080 - int(1080 * (H - BAND_TOP + 10) / W)) // 2))
closing.save(PAN / f'{n + 1:02d}.png')
print('wrote comic, story and', n + 1, 'panel cards')
