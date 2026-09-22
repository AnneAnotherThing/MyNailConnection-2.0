"""Measures each phone's screen in source-chatgpt.png instead of guessing.

For every side of a screen it scans outward from a point inside the screen
until it hits the phone's black bezel, collects those edge points along the
side, fits a straight line through them (robustly, so fingers crossing the
bezel are ignored), and intersects the four lines to get the screen corners.
Writes screens.json (read by screens.py) and debug-fit.png to check by eye.
"""
import json, pathlib
import numpy as np
from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent
src = Image.open(HERE / 'source-chatgpt.png').convert('RGB')
L = np.asarray(src.convert('L')).astype(int)
H, W = L.shape
DARK = 60

def run_dark(vals, i, step, need=3):
    """Walk from index i by step; return first index starting a dark run of `need`."""
    n = len(vals)
    while 0 <= i < n:
        if all(0 <= i + k * step < n and vals[i + k * step] < DARK for k in range(need)):
            return i
        i += step
    return None

def run_light(vals, i, step, need=3):
    n = len(vals)
    while 0 <= i < n:
        if all(0 <= i + k * step < n and vals[i + k * step] >= DARK for k in range(need)):
            return i
        i += step
    return None

def fit(points, axis):
    """Robust line fit. axis='x': x = a*y + b (left/right sides); 'y': y = a*x + b."""
    p = np.array(points, float)
    t, v = (p[:, 1], p[:, 0]) if axis == 'x' else (p[:, 0], p[:, 1])
    best = None
    rng = np.random.default_rng(1)
    for _ in range(400):                      # RANSAC
        i, j = rng.choice(len(t), 2, replace=False)
        if t[i] == t[j]:
            continue
        a = (v[j] - v[i]) / (t[j] - t[i]); b = v[i] - a * t[i]
        inl = np.abs(v - (a * t + b)) < 1.5
        if best is None or inl.sum() > best.sum():
            best = inl
    a, b = np.polyfit(t[best], v[best], 1)
    return a, b, int(best.sum()), len(t)

def corner(xline, yline):
    """x = a1*y + b1 and y = a2*x + b2."""
    a1, b1 = xline[:2]; a2, b2 = yline[:2]
    y = (a2 * b1 + b2) / (1 - a1 * a2)
    return (a1 * y + b1, y)

def side_points(cx, cy, rows=None, cols=None, dirn=None, through_dark=False):
    pts = []
    if dirn in ('left', 'right'):
        step = -1 if dirn == 'left' else 1
        for y in rows:
            row = L[y]
            x = run_dark(row, cx, step)
            if x is None:
                continue
            if through_dark:                     # dark UI hugging the edge: take the bezel's far side
                x = run_light(row, x, step)
                if x is None:
                    continue
                x -= step
            pts.append((x - step, y))            # last screen pixel
    else:
        step = -1 if dirn == 'up' else 1
        for x in cols:
            col = L[:, x]
            y = run_dark(col, cy, step)
            if y is None:
                continue
            if through_dark:
                y = run_light(col, y, step)
                if y is None:
                    continue
                y -= step
            pts.append((x, y - step))
    return pts

def measure(name, cx, cy, rows, cols, top_through_dark=False, bezel=None):
    left = fit(side_points(cx, cy, rows=rows, dirn='left'), 'x')
    right = fit(side_points(cx, cy, rows=rows, dirn='right'), 'x')
    bottom = fit(side_points(cx, cy, cols=cols, dirn='down'), 'y')
    if top_through_dark:
        # The screen's own header bar is black and touches the bezel, so the
        # top scan runs through header + bezel to the phone's outer edge,
        # then steps back in by the bezel thickness measured on the sides.
        outer = fit(side_points(cx, cy, cols=cols, dirn='up', through_dark=True), 'y')
        top = (outer[0], outer[1] + bezel, outer[2], outer[3])
    else:
        top = fit(side_points(cx, cy, cols=cols, dirn='up'), 'y')
    quad = [corner(left, top), corner(right, top), corner(right, bottom), corner(left, bottom)]
    print(f'{name:8s} inliers  L {left[2]}/{left[3]}  R {right[2]}/{right[3]}  T {top[2]}/{top[3]}  B {bottom[2]}/{bottom[3]}')
    print('         quad', [(round(x, 1), round(y, 1)) for x, y in quad])
    return quad

def bezel_thickness(cx, cy, rows):
    th = []
    for y in rows:
        row = L[y]
        a = run_dark(row, cx, 1)
        if a is None:
            continue
        b = run_light(row, a, 1)
        if b is not None and 3 < b - a < 30:
            th.append(b - a)
    return float(np.median(th))

out = {}
# Panel 5, left phone: white body from ~640 down; black header at the top.
bz = bezel_thickness(555, 760, range(640, 900, 3))
print('left phone bezel', bz)
out['profile'] = measure('profile', 555, 760, range(640, 900, 2), range(480, 620, 2),
                         top_through_dark=True, bezel=bz)
# Panel 5, right phone: white screen all the way up.
out['thread'] = measure('thread', 755, 760, range(600, 900, 2), range(690, 820, 2))

json.dump(out, open(HERE / 'screens.json', 'w'), indent=1)
dbg = src.copy(); d = ImageDraw.Draw(dbg)
for q in out.values():
    d.polygon([tuple(p) for p in q], outline=(0, 255, 0))
dbg.crop((420, 530, 900, 960)).resize((960, 860)).save(HERE / 'debug-fit.png')
print('wrote screens.json, debug-fit.png')
