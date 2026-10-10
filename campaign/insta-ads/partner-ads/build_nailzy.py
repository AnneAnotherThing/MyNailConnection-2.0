"""Nailzy partner ad tile for the Gallery (Build 1). 1080 square.
Their mark (nailzy-logo.png, white on black) sits on an ink top; the lower
band is MNC cream with the line in Playfair and DM Sans. The app adds the
Sponsored tag itself, bottom left. Run from this folder: python build_nailzy.py
"""
import pathlib, sys
from PIL import Image
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'comic'))
import screens as S

# Their mark is white on black; lift the letters off the black so they sit on the ink gradient.
logo = Image.open(HERE / 'nailzy-logo.png').convert('L').crop((160, 380, 864, 660))   # the wordmark only
mark_img = Image.new('RGBA', logo.size, (255, 255, 255, 0)); mark_img.putalpha(logo)
mark_img.save(S.BUILD / 'nailzy-mark.png')
mark = (S.BUILD / 'nailzy-mark.png').as_uri()

css = """
body{background:#141317}
.top{height:640px;background:linear-gradient(140deg,#4A4A4F 0%,#2A2A2E 60%,#141317 100%);display:flex;align-items:center;justify-content:center}
.top img{width:560px;display:block}
.band{height:440px;background:#FAF7F2;padding:58px 72px 0;position:relative}
.h{font-family:'Playfair Display',serif;font-weight:700;font-size:62px;line-height:1.08;letter-spacing:-.5px;color:#141317}
.h em{font-style:italic;font-weight:600;color:#A2636C}
.s{font-family:'DM Sans',sans-serif;font-size:30px;line-height:1.4;color:#6D6068;margin-top:22px}
.cta{position:absolute;right:72px;bottom:54px;font-family:'DM Sans',sans-serif;font-size:24px;font-weight:700;letter-spacing:.6px;text-transform:uppercase;color:#A2636C}
"""
body = f"""
<div class="top"><img src="{mark}" alt="nailzy"/></div>
<div class="band">
  <div class="h">Pro supplies, <em>delivered.</em></div>
  <div class="s">Gel, acrylic, builder gel and tools from the brands you already use, shipped to your door.</div>
  <div class="cta">Tap to shop &rarr;</div>
</div>
"""
out = S.render('nailzy-tile', 1080, 1080, css, body)
out.convert('RGB').save(HERE / 'nailzy-tile-1080.png')
print('wrote', HERE / 'nailzy-tile-1080.png')
