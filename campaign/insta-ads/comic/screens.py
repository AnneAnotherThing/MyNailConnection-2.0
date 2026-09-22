"""Rebrands the ChatGPT comic ad into the My Nail Connection 3.0 identity.

The six illustrated panels are kept. What changes:
  - the three phone screens (panel 3 home menu, panel 5 tech profile and
    text thread) are redrawn in 3.0 styling and perspective-warped onto
    the phones, replacing the invented heart logo, script wordmark,
    purple buttons and star rating;
  - the bottom brand band is rebuilt with the real mark, the typeset
    wordmark, FIND CONNECT GLOW and the live client tagline.

Run from this folder:  python screens.py
Needs Chrome (headless) and Pillow. Output: mnc-comic-1254.png, mnc-comic-1080.png
"""
import os, subprocess, pathlib
from PIL import Image, ImageDraw, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
FONTS = (HERE.parent / 'fonts' / 'fonts.css').as_uri()
G = lambda n: (REPO / 'images' / 'gallery' / f'g{n:02d}.webp').as_uri()
MARK = (REPO / 'images' / 'lady-card.webp').as_uri()
BUILD = HERE / 'build'
BUILD.mkdir(exist_ok=True)

BASE_CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:%dpx;height:%dpx;overflow:hidden;background:#fff}
body{font-family:'DM Sans',sans-serif;color:#141317;-webkit-font-smoothing:antialiased}
.pf{font-family:'Playfair Display',serif}
"""

def render(name, w, h, css, body):
    html = BUILD / f'{name}.html'
    html.write_text(f'<!DOCTYPE html><html><head><meta charset="utf-8"><link rel="stylesheet" href="{FONTS}">'
                    f'<style>{BASE_CSS % (w, h)}{css}</style></head><body>{body}</body></html>', encoding='utf-8')
    png = BUILD / f'{name}.png'
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                    '--allow-file-access-from-files', '--virtual-time-budget=5000',
                    f'--window-size={w},{h}', '--force-device-scale-factor=1',
                    f'--screenshot={png}', html.as_uri()],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return Image.open(png).convert('RGB').crop((0, 0, w, h))

# ── Screen 1: tech profile (panel 5, left phone) ───────────────────────
PROFILE_CSS = """
.bar{height:92px;background:#fff;border-bottom:3px solid rgba(125,100,102,.25);display:flex;align-items:center;justify-content:center;gap:14px}
.bar img{width:54px;height:54px;border-radius:14px}
.bar span{font-family:'Playfair Display',serif;font-style:italic;font-weight:700;font-size:34px}
.head{display:flex;gap:22px;align-items:center;padding:28px 28px 20px}
.av{width:124px;height:124px;border-radius:50%;background:url(%s) center/cover;box-shadow:0 0 0 4px #fff,0 0 0 7px #D0A3A5}
.nm{font-family:'Playfair Display',serif;font-weight:700;font-size:40px;line-height:1.05}
.mt{font-size:23px;color:#6D6068;margin-top:6px}
.open{display:inline-flex;align-items:center;gap:9px;margin-top:10px;font-size:21px;font-weight:700;color:#3F6B4D;background:#E7F0E8;padding:6px 15px;border-radius:100px}
.open i{width:12px;height:12px;border-radius:50%%;background:#5F9B72}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;padding:0 22px}
.grid div{aspect-ratio:1;border-radius:14px;background-size:cover;background-position:center}
.acts{padding:26px 22px 0;display:flex;flex-direction:column;gap:14px}
.b1{background:linear-gradient(140deg,#4A4A4F 0%,#2A2A2E 60%,#141317 100%);color:#fff;text-align:center;font-size:32px;font-weight:700;letter-spacing:1px;padding:24px;border-radius:18px}
.row{display:flex;gap:14px}
.b2{flex:1;background:#FAF7F2;color:#2A2A2E;text-align:center;font-size:30px;font-weight:700;padding:21px;border-radius:18px;border:2px solid rgba(162,99,108,.3)}
""".replace('%s', G(10)).replace('%%', '%')
PROFILE = f"""
<div class="bar"><img src="{MARK}"><span>My Nail Connection</span></div>
<div class="head"><div class="av"></div><div>
  <div class="nm">Sara's Nails</div><div class="mt">Gel-X · Nail art · 2.4 mi</div>
  <div class="open"><i></i>Open today</div></div></div>
<div class="grid">{''.join(f'<div style="background-image:url({G(n)})"></div>' for n in (13,4,16,12,22,8))}</div>
<div class="acts"><div class="b1">Book right here</div><div class="row"><div class="b2">Call</div><div class="b2">Text</div></div></div>
"""

# ── Screen 2: the text thread, then the booking lands (panel 5, right) ─
THREAD_CSS = """
.top{height:120px;display:flex;align-items:center;gap:18px;padding:0 26px;border-bottom:2px solid #eee}
.top .a{width:74px;height:74px;border-radius:50%;background:url(%s) center/cover}
.top b{font-size:32px}.top small{display:block;font-size:21px;color:#6D6068;font-weight:500}
.msgs{padding:26px 24px;display:flex;flex-direction:column;gap:16px}
.in{align-self:flex-start;max-width:82%%;background:#EFEAEA;border-radius:26px 26px 26px 8px;padding:20px 24px;font-size:29px;line-height:1.35}
.out{align-self:flex-end;max-width:78%%;background:#2A2A2E;color:#fff;border-radius:26px 26px 8px 26px;padding:20px 24px;font-size:29px;line-height:1.35}
.note{margin:22px 16px 0;padding:18px !important;gap:14px !important;background:#fff;border-radius:24px;box-shadow:0 10px 30px rgba(20,19,23,.16),0 0 0 2px rgba(125,100,102,.18);padding:22px;display:flex;gap:18px;align-items:center}
.note img{width:58px;height:58px;border-radius:14px;flex:none}
.note .k{font-size:15px;font-weight:700;letter-spacing:1.5px;white-space:nowrap;text-transform:uppercase;color:#A2636C}
.note .t{font-family:'Playfair Display',serif;font-weight:700;font-size:30px;margin-top:3px;white-space:nowrap}
.note .s{font-size:20px;color:#6D6068;margin-top:2px;white-space:nowrap}
.chk{margin-left:auto;flex:none;width:50px;height:50px;border-radius:50%%;background:#EAF3EC;display:flex;align-items:center;justify-content:center}
.chk svg{width:34px;height:34px;stroke:#4A7A5A;stroke-width:3.4;fill:none;stroke-linecap:round;stroke-linejoin:round}
""".replace('%s', G(10)).replace('%%', '%')
THREAD = f"""
<div class="top"><div class="a"></div><div><b>Sara's Nails</b><small>Text message</small></div></div>
<div class="msgs">
  <div class="in">Hey! I'd love to fit you in. I have 10am or 2pm if that works?</div>
  <div class="out">2pm sounds perfect! Thank you!</div>
</div>
<div class="note"><img src="{MARK}"><div><div class="k">My Nail Connection</div><div class="t">You're booked</div><div class="s">Sara's Nails · Thu 2:00 pm</div></div>
<div class="chk"><svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7"/></svg></div></div>
"""

# ── Screen 3: the client home menu (panel 3) ───────────────────────────
MENU_CSS = """
.bar{height:120px;display:flex;align-items:center;justify-content:center;gap:14px;border-bottom:3px solid rgba(125,100,102,.25)}
.bar img{width:62px;height:62px;border-radius:16px}
.bar span{font-family:'Playfair Display',serif;font-style:italic;font-weight:700;font-size:38px}
.it{display:flex;align-items:center;gap:22px;padding:0 34px;height:108px;font-size:36px;font-weight:600;border-bottom:2px solid #F0EAEC}
.it svg{width:40px;height:40px;stroke:#6E565D;fill:none;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round;flex:none}
.it.on{background:linear-gradient(160deg,#F7E2E3,#EFCFD2);color:#A2636C}
.it.on svg{stroke:#A2636C}
.dot{width:16px;height:16px;border-radius:50%;background:#5F9B72;margin-left:auto;box-shadow:0 0 0 6px rgba(95,155,114,.2)}
"""
IC = {
 'style': '<svg viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></svg>',
 'open':  '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
 'near':  '<svg viewBox="0 0 24 24"><path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg>',
 'fav':   '<svg viewBox="0 0 24 24"><path d="M12 20s-7.5-4.6-9.3-9A5.2 5.2 0 0 1 12 6.6a5.2 5.2 0 0 1 9.3 5.4C19.5 15.4 12 20 12 20z"/></svg>',
}
MENU = f"""
<div class="bar"><img src="{MARK}"><span>My Nail Connection</span></div>
<div class="it on">{IC['style']}Browse by style</div>
<div class="it">{IC['open']}Open today<span class="dot"></span></div>
<div class="it">{IC['near']}Techs near me</div>
<div class="it">{IC['fav']}My favorites</div>
"""

# ── Bottom brand band (replaces everything below the panels) ───────────
BAND_W, BAND_H = 2508, 564   # 2x of 1254 x 282
BAND_CSS = """
body{background:#fff}
.band{position:relative;width:100%;height:100%;display:flex;align-items:center;padding:0 90px;gap:54px;
  background:linear-gradient(180deg,#FFFFFF 0%,#FBF8F8 100%)}
.band::before{content:'';position:absolute;left:0;right:0;top:0;height:6px;background:linear-gradient(90deg,#4A4A4F,#141317)}
.mk{width:330px;height:330px;border-radius:70px;background:url(%s) center/cover;box-shadow:0 18px 44px rgba(20,19,23,.22),0 0 0 3px rgba(125,100,102,.25);flex:none}
.words{flex:1}
.wm{font-family:'Playfair Display',serif;font-style:italic;font-weight:700;font-size:128px;line-height:1;letter-spacing:-1px}
.fcg{font-size:40px;font-weight:700;letter-spacing:12px;text-transform:uppercase;color:#A2636C;margin-top:22px}
.tag{font-family:'Playfair Display',serif;font-size:62px;font-weight:600;margin-top:30px}
.tag em{font-style:italic;color:#A2636C}
.side{flex:none;width:640px;border-radius:44px;padding:52px 50px;background:linear-gradient(140deg,#4A4A4F 0%,#2A2A2E 60%,#141317 100%);color:#fff;
  box-shadow:inset 0 2px 2px rgba(255,255,255,.16),0 22px 50px rgba(20,19,23,.3)}
.side .k{font-size:34px;font-weight:700;letter-spacing:6px;text-transform:uppercase;color:#DEB3B5}
.side .h{font-family:'Playfair Display',serif;font-size:64px;font-weight:700;line-height:1.1;margin-top:14px}
.side .u{font-size:40px;font-weight:600;margin-top:26px;color:rgba(255,255,255,.82)}
""".replace('%s', MARK)
BAND = """
<div class="band">
  <div class="mk"></div>
  <div class="words">
    <div class="wm">My Nail Connection</div>
    <div class="fcg">Find · Connect · Glow</div>
    <div class="tag">Find the look. Find the tech. <em>Book them.</em></div>
  </div>
  <div class="side"><div class="k">For clients</div><div class="h">Free to browse.<br>Free to book.</div><div class="u">mynailconnection.com</div></div>
</div>
"""

STRIP_CSS = """
body{background:#141317}
.s{width:100%;height:100%;display:flex;align-items:center;justify-content:center;gap:26px;
  background:linear-gradient(140deg,#4A4A4F 0%,#2A2A2E 60%,#141317 100%);color:#fff;
  font-family:'Playfair Display',serif;font-style:italic;font-weight:600;font-size:62px;letter-spacing:.5px;white-space:nowrap}
.s em{color:#DEB3B5;font-style:italic}
"""
STRIP = '<div class="s">Real artists. Real work. <em>Real connections.</em></div>'

# ── Warp helpers ───────────────────────────────────────────────────────
def coeffs(dst, src):
    """Perspective coefficients mapping output (dst) quad back to src rect."""
    import numpy as np
    A, B = [], []
    for (x, y), (u, v) in zip(dst, src):
        A += [[x, y, 1, 0, 0, 0, -u * x, -u * y], [0, 0, 0, x, y, 1, -v * x, -v * y]]
        B += [u, v]
    return np.linalg.solve(np.array(A, float), np.array(B, float)).tolist()

def paste_screen(base, screen, quad, radius=0.07, keep=None):
    """quad: TL, TR, BR, BL in base coords. keep: polygons of base pixels to keep (fingers)."""
    W, H = base.size
    sw, sh = screen.size
    # rounded-corner alpha on the flat screen
    m = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=int(min(sw, sh) * radius), fill=255)
    rgba = screen.convert('RGBA'); rgba.putalpha(m)
    c = coeffs(quad, [(0, 0), (sw, 0), (sw, sh), (0, sh)])
    warped = rgba.transform((W, H), Image.PERSPECTIVE, c, Image.BICUBIC)
    alpha = warped.split()[3].filter(ImageFilter.GaussianBlur(0.6))
    if keep:
        k = Image.new('L', (W, H), 0)
        for poly in keep:
            ImageDraw.Draw(k).polygon(poly, fill=255)
        k = k.filter(ImageFilter.GaussianBlur(1.2))
        alpha = Image.composite(Image.new('L', (W, H), 0), alpha, k)
    warped.putalpha(alpha)
    base.paste(warped, (0, 0), warped)

if __name__ == '__main__':
    src = Image.open(HERE / 'source-chatgpt.png').convert('RGB')
    out = src.copy()

    profile = render('profile', 440, 880, PROFILE_CSS, PROFILE)
    thread = render('thread', 440, 800, THREAD_CSS, THREAD)
    menu = render('menu', 560, 720, MENU_CSS, MENU)

    # Panel 5, left phone: tech profile.
    paste_screen(out, profile, [(450, 570), (610, 563), (650, 917), (458, 920)], radius=0.08)
    # Panel 5, right phone: text thread + booking notification.
    paste_screen(out, thread, [(667, 568), (842, 580), (850, 912), (662, 910)], radius=0.08,
                 keep=[[(650, 740), (668, 735), (672, 900), (650, 905)]])
    # Panel 3: home menu. The phone runs off the bottom of the panel, so the
    # warp is clipped to the panel and the fingers on the right are kept.
    paste_screen(out, menu, [(1100, 240), (1236, 267), (1214, 470), (1068, 440)], radius=0.06,
                 keep=[[(1195, 345), (1240, 330), (1240, 440), (1190, 440)],
                       [(1060, 422), (1086, 424), (1086, 449), (1060, 449)],
                       [(1060, 449), (1254, 449), (1254, 480), (1060, 480)]])
    # restore the panel-3 frame edge below the phone (original pixels)
    out.paste(src.crop((1058, 448, 1254, 458)), (1058, 448))

    # Panel 6 caption: the hot-pink brush strip becomes an ink ribbon.
    strip = render('strip', 1480, 240, STRIP_CSS, STRIP)
    paste_screen(out, strip, [(884, 918), (1248, 886), (1250, 958), (884, 966)], radius=0.0)

    # Bottom band.
    band = render('band', BAND_W, BAND_H, BAND_CSS, BAND).resize((1254, 282), Image.LANCZOS)
    out.paste(band, (0, 972))

    out.save(HERE / 'mnc-comic-1254.png')
    out.resize((1080, 1080), Image.LANCZOS).save(HERE / 'mnc-comic-1080.png')
    print('wrote mnc-comic-1254.png and mnc-comic-1080.png')
