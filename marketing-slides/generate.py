# -*- coding: utf-8 -*-
# Generates My Nail Connection slides in two formats:
#   python generate.py story   -> slide-1..6.html   (1080x1920 Instagram Stories)
#   python generate.py feed    -> carousel-1..6.html (1080x1350 IG feed carousel)
# "Quiet Bloom" philosophy: soft sunrise palette, serif+sans voices, generous space.
import io, sys

FMT = (sys.argv[1] if len(sys.argv) > 1 else "story").lower()
if FMT == "feed":
    H, PREFIX = 1350, "carousel"
    EB_TOP, PAD, DOTS_BOT = 92, "230px 120px 210px", 92
else:
    H, PREFIX = 1920, "slide"
    EB_TOP, PAD, DOTS_BOT = 250, "380px 120px 360px", 285

SPARK = '<svg class="spark" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.4 6.6L21 11l-6.6 2.4L12 20l-2.4-6.6L3 11l6.6-2.4z"/></svg>'

BASE_CSS = f"""
@font-face{{font-family:'Playfair';src:url('PlayfairDisplay.ttf');font-weight:400 900;font-style:normal;font-display:block;}}
@font-face{{font-family:'Playfair';src:url('PlayfairDisplay-Italic.ttf');font-weight:400 900;font-style:italic;font-display:block;}}
@font-face{{font-family:'DMSans';src:url('DMSans.ttf');font-weight:100 1000;font-style:normal;font-display:block;}}
*{{margin:0;padding:0;box-sizing:border-box;}}
:root{{
  --rose:#C4786A;--rose-dark:#8B4A40;--rose-light:#FDF0EE;--rose-mid:#E0A898;
  --gold:#A07840;--gold-light:#F5EDE0;--cream:#FAF7F4;--charcoal:#2C2420;--muted:#8A7A74;
}}
html,body{{width:1080px;height:{H}px;}}
.slide{{
  position:relative;width:1080px;height:{H}px;overflow:hidden;
  font-family:'DMSans',sans-serif;color:var(--charcoal);
  background:
    radial-gradient(ellipse 72% 46% at 20% 13%, rgba(224,168,152,0.42), transparent 60%),
    radial-gradient(ellipse 66% 46% at 88% 90%, rgba(201,169,110,0.26), transparent 60%),
    radial-gradient(ellipse 120% 70% at 50% 48%, rgba(253,240,238,0.55), transparent 72%),
    linear-gradient(168deg,#FBEBE7 0%,#FAF7F4 48%,#F4EADD 100%);
}}
.watermark{{position:absolute;top:-120px;right:-140px;width:540px;height:540px;color:var(--rose-mid);opacity:0.10;}}
.watermark svg{{width:100%;height:100%;}}
.watermark.bl{{top:auto;right:auto;bottom:-150px;left:-160px;width:460px;height:460px;opacity:0.08;color:var(--gold);}}
.eyebrow{{position:absolute;top:{EB_TOP}px;left:0;right:0;display:flex;align-items:center;justify-content:center;gap:16px;}}
.eyebrow img{{width:46px;height:46px;object-fit:contain;filter:drop-shadow(0 2px 6px rgba(139,74,64,0.25));}}
.eyebrow span{{font-size:23px;font-weight:600;letter-spacing:5px;text-transform:uppercase;color:var(--gold);}}
.content{{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
  text-align:center;padding:{PAD};}}
.spark{{width:56px;height:56px;color:var(--rose-mid);margin-bottom:38px;filter:drop-shadow(0 3px 8px rgba(196,120,106,0.25));}}
h1{{font-family:'Playfair',serif;font-weight:600;font-size:94px;line-height:1.12;letter-spacing:-1.5px;color:var(--rose-dark);}}
h1 em{{font-style:italic;color:var(--rose);}}
.sub{{font-size:37px;line-height:1.55;color:#6E5F58;margin-top:38px;max-width:780px;font-weight:400;}}
.dots{{position:absolute;left:0;right:0;bottom:{DOTS_BOT}px;display:flex;align-items:center;justify-content:center;gap:18px;}}
.dots i{{width:15px;height:15px;border-radius:50%;background:rgba(139,74,64,0.20);display:block;}}
.dots i.on{{width:44px;border-radius:99px;background:linear-gradient(90deg,var(--rose),var(--rose-dark));}}
.cards{{display:flex;flex-direction:column;gap:28px;margin-top:50px;width:100%;max-width:800px;}}
.card{{background:rgba(255,255,255,0.82);border:1px solid rgba(196,120,106,0.18);border-radius:30px;
  padding:38px 46px;text-align:left;box-shadow:0 12px 40px rgba(139,74,64,0.08);}}
.card .plat{{font-size:27px;font-weight:700;letter-spacing:0.5px;color:var(--rose-dark);margin-bottom:10px;}}
.card .step{{font-size:31px;line-height:1.5;color:#6E5F58;}}
.biglogo{{width:168px;height:168px;object-fit:contain;margin-bottom:44px;filter:drop-shadow(0 6px 18px rgba(139,74,64,0.28));}}
.url{{display:inline-block;margin-top:46px;background:linear-gradient(135deg,var(--rose) 0%,var(--rose-dark) 100%);
  color:#fff;font-size:36px;font-weight:600;letter-spacing:0.3px;padding:26px 52px;border-radius:100px;
  box-shadow:0 10px 30px rgba(196,120,106,0.38);}}
.tiny{{margin-top:28px;font-size:27px;color:var(--muted);letter-spacing:0.5px;}}
"""

def dots(active):
    return '<div class="dots">' + ''.join(
        '<i class="on"></i>' if i == active else '<i></i>' for i in range(6)
    ) + '</div>'

def page(active, body):
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>{BASE_CSS}</style></head>
<body><div class="slide">
<div class="watermark">{SPARK}</div><div class="watermark bl">{SPARK}</div>
<div class="eyebrow"><img src="logo.png" alt=""><span>My Nail Connection</span></div>
<div class="content">{body}</div>
{dots(active)}
</div></body></html>"""

def standard(active, headline, sub):
    return page(active, f'{SPARK}<h1>{headline}</h1><p class="sub">{sub}</p>')

slides = {}
slides[1] = standard(0, 'Download <em>fatigue</em><br>is real.', 'Your phone is already full. We get it.')
slides[2] = standard(1, 'So,<br><em>good news.</em>', 'My Nail Connection doesn’t need a download.')
slides[3] = standard(2, 'It lives in<br>your <em>browser.</em>', 'Your feed, your saved looks, and your next favorite tech, all in one place.')
slides[4] = standard(3, 'Add it to your<br><em>home screen.</em>', 'It opens just like an app. Nothing to install, no updates to chase.')
slides[5] = page(4, (f'{SPARK}<h1>Here’s <em>how.</em></h1>'
    '<div class="cards">'
    '<div class="card"><div class="plat">On iPhone</div>'
    '<div class="step">Open it in Safari, tap Share, then “Add to Home Screen.”</div></div>'
    '<div class="card"><div class="plat">On Android</div>'
    '<div class="step">Open it in Chrome, tap the menu, then “Install app.”</div></div>'
    '</div>'))
slides[6] = page(5, ('<img class="biglogo" src="logo.png" alt="">'
    '<h1>Find your tech.<br><em>Glow up.</em></h1>'
    '<div class="url">mynailconnection.com/app</div>'
    '<div class="tiny">No app store required.</div>'))

for n, html in slides.items():
    fn = f"{PREFIX}-{n}.html"
    with io.open(fn, "w", encoding="utf-8") as f:
        f.write(html)
    print("wrote", fn)
print("done", FMT)
