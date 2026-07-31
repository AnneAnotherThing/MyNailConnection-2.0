# Build marketing-v3.html from marketing.html.
# Fixes the locked-model violations (no feed, no posts, photos paid+permanent,
# Glow Up = 40 uploads not unlimited) and rebrands the hero to the hat-lady
# identity. Every replacement asserts, so a missed match fails loudly.
import pathlib, sys, shutil

SRC = pathlib.Path("marketing.html")
DST = pathlib.Path("marketing-v3.html")
shutil.copyfile(SRC, DST)
h = DST.read_text(encoding="utf-8")
applied = []

def rep(label, old, new, count=1):
    global h
    n = h.count(old)
    if n != count:
        print(f"FAIL [{label}]: expected {count} match(es), found {n}")
        sys.exit(1)
    h = h.replace(old, new)
    applied.append(label)

# ── META / SOCIAL ────────────────────────────────────────────────────────
rep("og:description",
    'content="Browse real nail art, filter by style, and Book the tech whose work you love. Free to join, free to book, in full bloom now."',
    'content="Browse real nail art, filter by style, and book the tech whose work you love. Free to join, free to book, always."')

rep("twitter:description",
    'content="Browse real nail art, filter by style, and Book your nail tech through their live gallery. Free to start."',
    'content="Browse real nail art, filter by style, and book your nail tech through their live Gallery. Free to join, free to book."')

# ── SCHEMA.ORG OFFERS ────────────────────────────────────────────────────
rep("schema Starter",
    '"description": "Free forever - in-app booking, 1 profile photo, full public profile, availability toggles, posts, contact options."',
    '"description": "Free forever - in-app booking, your first photo free, full public profile, availability toggles, contact options."')

rep("schema GlowUp",
    '"description": "$10.99/month - unlimited photo uploads, availability spotlight in the live What\'s Happening feed, portfolio that compounds. Cancel anytime."',
    '"description": "$10.99/month - 40 photo uploads a month, and a portfolio that keeps working for you. Cancel anytime."')

# ── FAQ ──────────────────────────────────────────────────────────────────
rep("faq free",
    '"text": "Yes. Clients use MNC completely free. Nail techs get free in-app booking, a full public profile, 1 profile photo, availability toggles, and direct contact options on the free Starter plan. Glow Up unlocks unlimited photos plus availability spotlighting in the live What\'s Happening feed."',
    '"text": "Yes. Clients use MNC completely free, and booking is free for every nail tech, forever. Techs get free in-app booking, a full public profile, their first photo free, availability toggles, and direct contact options. After the first photo, uploads are $1 each, $5 for ten, or Glow Up at $10.99 a month for 40 uploads. Every photo you pay for stays up permanently."')

# ── ANNOUNCE MARQUEE ─────────────────────────────────────────────────────
rep("marquee bloom",
    '<span class="announce-item"><span class="announce-bloom">\U0001F338</span> In full bloom</span>',
    '<span class="announce-item"><span class="announce-bloom">✨</span> Version 3.0 is here</span>', count=2)
rep("marquee free",
    '<span class="announce-item">Live now, free to join</span>',
    '<span class="announce-item">Booking is free, forever</span>', count=2)

# ── TAGLINE STRIP ────────────────────────────────────────────────────────
rep("tagline strip",
    '<strong>MNC 2.0 is officially live!</strong> &nbsp;·&nbsp; Rebuilt from scratch. Better support. Real community.',
    '<strong>MNC 3.0 is here.</strong> &nbsp;·&nbsp; Free booking, forever. One Gallery. Photos that never expire.')

# ── FOR TECHS: section intro ─────────────────────────────────────────────
rep("techs section-sub",
    'Your booking profile is live the moment you join &mdash; free, forever. <strong>One profile photo is included</strong>, and every photo you add lands in the inspo boards where clients browse by style. <strong>Glow Up</strong> adds unlimited photos plus your availability spotlighted in the live <strong>What&rsquo;s Happening</strong> feed. No slow patch penalty. You&rsquo;re active until you take yourself down.',
    'Your booking profile is live the moment you join, free, forever. <strong>Your first photo is free</strong>, and every photo you add lands in the <strong>Gallery</strong> where clients browse by style. After that, photos are $1 each, $5 for ten, or <strong>Glow Up</strong> at $10.99 a month for 40 uploads. No slow patch penalty. You&rsquo;re active until you take yourself down.')

# ── CARD 04: booking ─────────────────────────────────────────────────────
rep("card04 feed",
    'Clients find your work in the feed and book you directly in the app &mdash; no third-party platform required.',
    'Clients find your work in the Gallery and book you directly in the app, no third-party platform required.')

# ── CARD 05: Posts -> Standing Appointments (posts were removed in 3.0) ──
rep("card05 posts",
    '''<h3>Post Updates. Stay Top of Mind.</h3>
        <p>Share availability windows, promos, and behind-the-scenes peeks using the New Post button. Posts appear on your <strong>public profile</strong>, another free way to stay visible with clients who already love your work. The board is intentionally <strong>one-way</strong>: no comments, no replies, no DM threads. Clients read the update and reach out on your terms, a call, a text, or a tap on your booking link.</p>''',
    '''<h3>Standing Appointments <span style="color:var(--rose);">, Set and Forget</span></h3>
        <p>Your every-three-weeks regular shouldn&rsquo;t have to rebook every three weeks. Turn any appointment into a <strong>standing appointment</strong> and MNC books the whole series for you, every 1 to 4 weeks, automatically topped up so the chair is always held. Your regulars stop slipping through the cracks, and you stop chasing them. This is the part the paid booking tools charge you monthly for.</p>''')

# ── CARD 06: weekly rhythm -> the Gallery math ───────────────────────────
rep("card06 rhythm",
    '''<h3>A Weekly Rhythm <span style="color:var(--rose);">, Glow Up</span></h3>
        <p>Every photo you post lands in the <strong>inspo boards</strong> &mdash; that&rsquo;s for everyone, every tier. <strong>Glow Up</strong> layers two things on top: <strong>unlimited photo uploads</strong>, and your availability spotlighted in the live <strong>What&rsquo;s Happening</strong> feed so clients who need someone this week see you first. Have a slow patch? You don&rsquo;t pay to stay active. You&rsquo;re active until you take yourself down.</p>''',
    '''<h3>More Photos, More Presence <span style="color:var(--rose);">, That&rsquo;s the Whole Algorithm</span></h3>
        <p>Every photo you add lands in the <strong>Gallery</strong>, and your share of it grows exactly with your photo count. No boosting, no pay-to-rank, no mystery math. Flip <strong>Available Now</strong> and your work glows in the grid so clients who need someone today spot you first. Have a slow patch? You don&rsquo;t pay to stay active. You&rsquo;re active until you take yourself down.</p>''')

# ── ARCHIVE / PERMANENCE BLOCK ───────────────────────────────────────────
rep("archive block",
    "This isn't a social feed, nothing autodeletes, nothing scrolls into the void. Every photo you add is yours. It's your <strong style=\"color:var(--text);\">portfolio</strong>, your <strong style=\"color:var(--text);\">archive</strong>, your <strong style=\"color:var(--text);\">show-and-tell</strong>, the ombre you did last spring is still there next spring. Start with free booking and 1 profile photo. <em>Ready to grow?</em> Add photos one at a time for $1, grab 10 for $5, or go Glow Up for unlimited photos plus availability spotlighting. Every photo compounds. Your work never disappears.",
    "This isn't a social feed, nothing autodeletes, nothing scrolls into the void. Every photo you add is yours. It's your <strong style=\"color:var(--text);\">portfolio</strong>, your <strong style=\"color:var(--text);\">archive</strong>, your <strong style=\"color:var(--text);\">show-and-tell</strong>, the ombre you did last spring is still there next spring. Start with free booking and your first photo free. <em>Ready to grow?</em> Add photos one at a time for $1, grab 10 for $5, or go Glow Up at $10.99 a month for 40 uploads. Instagram rents attention. Here, you own a billboard.")

# ── PRICING PANEL ────────────────────────────────────────────────────────
rep("pricing panel sub",
    'No contracts. No surprises. Every plan includes availability toggles, posts, contact options, and full client discovery.',
    'No contracts. No surprises. Booking is free on every plan, forever. Photos are the only thing you ever pay for.')

rep("starter posts li",
    '''<li><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="#BFA6BB" stroke-width="2.5" stroke-linecap="round"><polyline points="20 6 9 17 4 12"/></svg> Posts &amp; updates</li>''',
    '''<li><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="#BFA6BB" stroke-width="2.5" stroke-linecap="round"><polyline points="20 6 9 17 4 12"/></svg> Standing appointments</li>''')

rep("starter 1 photo li",
    '<polyline points="20 6 9 17 4 12"/></svg> 1 profile photo</li>',
    '<polyline points="20 6 9 17 4 12"/></svg> Your first photo, free</li>')

rep("glowup desc",
    '<p class="price-desc">Unlimited photos plus your availability spotlighted in the live feed.</p>',
    '<p class="price-desc">40 uploads a month, for techs building a real portfolio.</p>')

rep("glowup li unlimited",
    '<polyline points="20 6 9 17 4 12"/></svg> Unlimited photo uploads</li>',
    '<polyline points="20 6 9 17 4 12"/></svg> 40 photo uploads a month</li>')
rep("glowup li spotlight",
    '<polyline points="20 6 9 17 4 12"/></svg> Availability spotlight in live feed</li>',
    '<polyline points="20 6 9 17 4 12"/></svg> Available Now glow in the Gallery</li>')
rep("glowup li loop",
    '<polyline points="20 6 9 17 4 12"/></svg> Photos loop in the feed forever</li>',
    '<polyline points="20 6 9 17 4 12"/></svg> Every photo stays up permanently</li>')

# ── SPOTLIGHT card: "more views" wording is fine; keep. ──────────────────

# ── GET INSPO section: "photo feed" -> Gallery ───────────────────────────
rep("get inspo feed",
    '<b style="color:rgba(245,237,232,0.8);">Get Inspo</b> mode is a pure photo feed from anywhere in the country.',
    '<b style="color:rgba(245,237,232,0.8);">Get Inspo</b> mode opens the Gallery up to anywhere in the country.')

# ── FINAL CTA ────────────────────────────────────────────────────────────
rep("final cta",
    "Whether you're looking for your next favorite tech or ready to grow your nail business, My Nail Connection is in full bloom and ready when you are.",
    "Whether you're looking for your next favorite tech or ready to grow your nail business, My Nail Connection is ready when you are.")

# ── QUOTE byline stray comma ─────────────────────────────────────────────
rep("quote byline", '<p class="quote-byline">, My Nail Connection</p>',
    '<p class="quote-byline">My Nail Connection</p>')

# ── HERO: swap magnolia + 2.0 logo for the hat-lady identity ─────────────
hero_start = h.index('<!-- HERO -->')
hero_end = h.index('<!-- TAGLINE STRIP -->')
old_hero = h[hero_start:hero_end]
assert 'hero-magnolia' in old_hero, "hero block not located"

new_hero = '''<!-- HERO -->
<section class="hero" id="top">
  <div class="hero-art" aria-hidden="true">
    <img src="images/mnc-lady.png" width="800" height="700" alt="" decoding="async" fetchpriority="high"/>
  </div>
  <div class="hero-inner">
    <div class="hero-badge"><span class="hero-badge-dot"></span> Version <strong style="color:#141317;font-weight:700;letter-spacing:1.5px;">3.0</strong> <svg class="hero-badge-sparkle" aria-hidden="true" viewBox="0 0 16 16" width="11" height="11" style="vertical-align:-1px;"><path d="M8 0 L9 7 L16 8 L9 9 L8 16 L7 9 L0 8 L7 7 Z" fill="#7D6478"/></svg></div>

    <h1>My Nail Connection.<br/><em>Find your tech. Love your nails.</em></h1>
    <p class="hero-sub">Real nail art from real techs near you, searchable, filterable, and ready to book. Booking is free for every tech, forever.</p>
    <div class="hero-buttons">
      <a href="#for-clients" class="btn-primary">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M20.84 4.61a5.5 5.5 0 00-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 00-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 000-7.78z"/></svg>
        I want to find a tech
      </a>
      <a href="#for-techs" class="btn-outline">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-4 3.6-7 8-7s8 3 8 7"/></svg>
        I'm a nail tech
      </a>
    </div>

    <div class="store-btns store-btns--mini" style="margin-top:22px;">
      <a href="https://apps.apple.com/app/id6764125663" target="_blank" rel="noopener" class="store-btn" aria-label="Download My Nail Connection on the App Store">
        <svg viewBox="0 0 24 24" width="20" height="20" fill="white"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
        <div class="store-btn-text"><small>Download on the</small><strong>App Store</strong></div>
      </a>
      <a href="https://play.google.com/store/apps/details?id=com.mynailconnection.app" target="_blank" rel="noopener" class="store-btn" aria-label="Get My Nail Connection on Google Play">
        <svg viewBox="0 0 24 24" width="20" height="20" fill="white"><path d="M3.18 23.76c.28.15.6.19.93.1l11.84-6.72-2.5-2.5-10.27 9.12zM20.7 10.06L17.5 8.22l-2.85 2.85 2.85 2.85 3.22-1.85c.91-.52.91-1.99-.02-2.01zM2.14.7C1.85.98 1.7 1.4 1.7 1.95V22.1c0 .55.15.97.44 1.25l.07.06 11.26-11.26v-.27L2.21.64 2.14.7zm13.13 11.6l-2.96 2.96L1.7 4.65v-.2l13.57 7.85z"/></svg>
        <div class="store-btn-text"><small>Get it on</small><strong>Google Play</strong></div>
      </a>
    </div>
  </div>
</section>

'''
h = h[:hero_start] + new_hero + h[hero_end:]
applied.append("hero rebuilt")

# ── V3 CSS OVERRIDES (appended last so they win the cascade) ─────────────
css = '''
  /* ══════════════════════════════════════════════════════════════
     MNC 3.0 overrides, hat-lady on ivory, echoing the app splash.
     Appended last so these win the cascade over the 2.0 hero rules.
     ══════════════════════════════════════════════════════════════ */
  .hero {
    background: #EDEAE5;
    text-align: left;
    justify-content: flex-start;
    padding: 150px clamp(24px, 6vw, 72px) 80px;
  }
  .hero::before {
    background: radial-gradient(ellipse at 12% 25%, rgba(191,166,187,0.28) 0%, transparent 62%),
                radial-gradient(ellipse at 85% 85%, rgba(125,100,120,0.10) 0%, transparent 55%);
  }
  .hero::after { opacity: 0.14; }
  .hero-art {
    position: absolute;
    top: 0; bottom: 0; right: -4vw;
    width: min(720px, 60vw);
    display: flex; align-items: center; justify-content: flex-end;
    z-index: 0; pointer-events: none;
  }
  .hero-art img {
    width: 100%; height: auto; max-width: none;
    object-fit: contain;
    mix-blend-mode: multiply;
    -webkit-mask-image: linear-gradient(to bottom, transparent 0%, #000 20%, #000 78%, transparent 100%);
            mask-image: linear-gradient(to bottom, transparent 0%, #000 20%, #000 78%, transparent 100%);
  }
  .hero-inner { max-width: 620px; margin: 0; text-align: left; }
  .hero-logo { display: none; }
  .hero h1 { color: #141317; }
  .hero h1 em { color: #7D6478; }
  .hero .hero-sub { color: #56505C; margin-left: 0; margin-right: 0; }
  .hero .hero-buttons { justify-content: flex-start; }
  .hero .store-btns--mini { justify-content: flex-start !important; }
  .hero .hero-badge {
    background: rgba(20,19,23,0.045);
    border: 1px solid rgba(125,100,120,0.22);
    color: #7D6478;
  }
  .hero .hero-badge-dot { background: #7D6478; }

  @media (max-width: 900px) {
    .hero { text-align: center; justify-content: center; padding-top: 132px; }
    .hero-inner { margin: 0 auto; text-align: center; }
    .hero-art {
      right: auto; left: 50%; transform: translateX(-50%);
      width: min(560px, 118vw); opacity: 0.30;
    }
    .hero .hero-buttons, .hero .store-btns--mini { justify-content: center !important; }
    .hero .hero-sub { margin-left: auto; margin-right: auto; }
  }
'''
marker = "</style>"
i = h.index(marker)
h = h[:i] + css + "\n" + h[i:]
applied.append("v3 css appended")

# ── No em-dashes (Anne's rule) ───────────────────────────────────────────
if "&mdash;" in h:
    h = h.replace(" &mdash; ", ", ").replace("&mdash;", ",")
    applied.append("em-dashes stripped")

DST.write_text(h, encoding="utf-8")
print("applied:", len(applied))
for a in applied:
    print("  +", a)
print("\nbytes:", DST.stat().st_size)
