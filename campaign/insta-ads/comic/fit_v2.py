"""Finds every blank phone screen in source-v2.png.

The v2 comic was generated with plain white screens, so each one is a
flood fill from a seed point inside it. The fill's edge pixels on each
side are fitted with a straight line (RANSAC, so a fingertip over the
bezel is ignored) and the four lines intersect at the screen corners.
Writes screens-v2.json and debug-v2.png.
"""
import json, pathlib
import numpy as np
from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent
src = Image.open(HERE / 'source-v2.png').convert('RGB')
W, H = src.size

SEEDS = {            # a point inside each screen, 1254px space
    'menu':    (1130, 375),   # panel 3
    'profile': (525, 820),    # panel 5, left
    'thread':  (705, 820),    # panel 5, right
    'p2':      (640, 385),    # panel 2, small
    'p6':      (945, 920),    # panel 6, small
}
FILL = (0, 255, 0)

def fit(points, axis):
    p = np.array(points, float)
    t, v = (p[:, 1], p[:, 0]) if axis == 'x' else (p[:, 0], p[:, 1])
    best = None
    rng = np.random.default_rng(1)
    for _ in range(500):
        i, j = rng.choice(len(t), 2, replace=False)
        if t[i] == t[j]:
            continue
        a = (v[j] - v[i]) / (t[j] - t[i]); b = v[i] - a * t[i]
        inl = np.abs(v - (a * t + b)) < 1.2
        if best is None or inl.sum() > best.sum():
            best = inl
    a, b = np.polyfit(t[best], v[best], 1)
    return a, b, int(best.sum()), len(t)

def corner(xl, yl):
    a1, b1 = xl[:2]; a2, b2 = yl[:2]
    y = (a2 * b1 + b2) / (1 - a1 * a2)
    return (float(a1 * y + b1), float(y))

out = {}
dbg = src.copy(); dd = ImageDraw.Draw(dbg)
for name, seed in SEEDS.items():
    im = src.copy()
    ImageDraw.floodfill(im, seed, FILL, thresh=55)
    m = np.all(np.asarray(im) == FILL, axis=2)
    ys, xs = np.nonzero(m)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    h, w = y1 - y0, x1 - x0
    # edge points per side, skipping the rounded corners (inner 70%)
    rows = range(int(y0 + .15 * h), int(y1 - .15 * h))
    cols = range(int(x0 + .15 * w), int(x1 - .15 * w))
    left  = fit([(np.nonzero(m[y])[0].min(), y) for y in rows], 'x')
    right = fit([(np.nonzero(m[y])[0].max(), y) for y in rows], 'x')
    top   = fit([(x, np.nonzero(m[:, x])[0].min()) for x in cols], 'y')
    bot   = fit([(x, np.nonzero(m[:, x])[0].max()) for x in cols], 'y')
    q = [corner(left, top), corner(right, top), corner(right, bot), corner(left, bot)]
    out[name] = q
    print(f'{name:8s} {w}x{h}  inliers L{left[2]}/{left[3]} R{right[2]}/{right[3]} T{top[2]}/{top[3]} B{bot[2]}/{bot[3]}')
    dd.polygon([tuple(p) for p in q], outline=(255, 0, 0), width=2)

json.dump(out, open(HERE / 'screens-v2.json', 'w'), indent=1)
dbg.save(HERE / 'debug-v2.png')
# how tall is the blank strip under the panels?
L = np.asarray(src.convert('L'))
dark_rows = np.nonzero((L < 80).sum(axis=1) > 20)[0]
print('last inked row', dark_rows.max(), 'of', H)
