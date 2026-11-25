# Build the four MNC answer pages (2026-11-24, locked by Anne 2026-11-24 8:21 PM).
#
# Each page answers one question people ask Google and the chat assistants,
# short answer first, then detail, then an FAQ with FAQPage schema.
# Every claim comes from llms.txt / the live site; no prices on these pages.
#
# Run: python build_answer_pages.py   (writes the four .html files at repo root)
# After any edit: run this, then deploy/sync.sh (sync.sh copies all four,
# and they are in sitemap.xml and llms.txt).
import json, pathlib, html

SITE = "https://mynailconnection.com"
APP_STORE = "https://apps.apple.com/app/id6764125663"
PLAY = "https://play.google.com/store/apps/details?id=com.mynailconnection.app"

PAGES = [
  {
    "slug": "find-a-nail-tech-phoenix",
    "title": "How to find a good nail tech near you in Phoenix",
    "meta": "See a nail tech's real work before you book. My Nail Connection is a free app with a Gallery of real sets from nail techs around Phoenix, filtered by style and distance.",
    "eyebrow": "For clients",
    "h1": "How do I find a good nail tech near me in Phoenix?",
    "short": "Look at her real work before you book. My Nail Connection is a free app with a Gallery of real sets from nail techs around the Valley. Filter by shape, type, style and distance, save the looks you love, then book, call or text the tech right from her profile. Clients never pay a booking fee.",
    "sections": [
      ("What to look for in a nail tech",
       ["<b>Photos of her own work.</b> Not stock photos or reposts. The sets she actually did tell you more than any review.",
        "<b>The look you want.</b> If you want almond chrome, French, 3D or gel-X, find a tech whose gallery is full of it.",
        "<b>How far she is.</b> You will be going back every few weeks, so close by matters.",
        "<b>An easy way to reach her.</b> Book, call or text, whichever she offers, without hunting through DMs."]),
      ("How My Nail Connection helps",
       ["The <b>Gallery</b> shows real nail work from techs near you. Filter by shape, type, style and distance.",
        "Tap a set you love to open that tech's profile, see more of her work, and book, call or text her.",
        "Save looks to show your tech, and favorite your go-to tech so she is one tap away.",
        "Need nails soon? The <b>What's happening</b> board shows techs who posted <b>Available now</b>."]),
      ("Where around Phoenix",
       ["Nail techs on My Nail Connection work all over the Valley, from Glendale, Peoria and Surprise to Scottsdale, Tempe, Mesa and Gilbert, and in Phoenix itself.",
        "Set your distance in the Gallery and you only see techs close enough to matter."]),
    ],
    "faq": [
      ("Is My Nail Connection free for clients?", "Yes. It is free for clients, always, with no booking fees."),
      ("Can I find a nail tech for a specific look?", "Yes. The Gallery filters by shape, type and style, such as almond, chrome, French, 3D or gel-X, and by distance, so you see real work in the look you want."),
      ("Can I book a nail appointment today?", "Often, yes. Techs post Available now on the What's happening board when they have an opening, and you can post what you need so techs reply Interested."),
      ("Is My Nail Connection only in Phoenix?", "No. Nail techs join from all over the US, and the Phoenix area has the most of them so far."),
      ("Does My Nail Connection do hair, lashes or brows?", "No. It is built for nails only."),
    ],
  },
  {
    "slug": "nails-today",
    "title": "Where to get your nails done today, near you",
    "meta": "Need nails today or this week? On My Nail Connection, nail techs post Available now and clients post what they need. Techs nearby reply and you book, call or text.",
    "eyebrow": "For clients",
    "h1": "Where can I get my nails done today?",
    "short": "Check the What's happening board in the My Nail Connection app. Nail techs post Available now when they have an opening, and you can post what you need, where and by when. Techs nearby reply Interested, and you get her profile with a Call, Text or Book button. It is free for clients.",
    "sections": [
      ("Two ways to find a same-day opening",
       ["<b>See who is open.</b> A tech posts Available now with an end time and a note, and her work glows in the Gallery for clients looking right now.",
        "<b>Ask for what you need.</b> Post your city, a photo if you have one, the date you need it by and how far you would travel. Techs reply Interested."]),
      ("What happens when a tech replies",
       ["You get that tech's profile and her Call, Text or Book button, so you can see her work and set it up.",
        "Each tech chooses how far she travels, 10, 25 or 50 miles or her whole state, and gets a notification when a request lands within reach."]),
      ("Safe to use",
       ["Every post can be reported and any person blocked. Reports are handled within 24 hours."]),
    ],
    "faq": [
      ("How do I find a nail tech with an opening today?", "Open the What's happening board in My Nail Connection to see techs who posted Available now, or post your own request so nearby techs reply Interested."),
      ("Does it cost anything to post a request?", "No. My Nail Connection is free for clients, with no booking fees."),
      ("Can I add a photo of the nails I want?", "Yes. A request can include a photo, your city, the date you need it by and how far you would travel."),
      ("What if someone posts something inappropriate?", "Every post can be reported or the person blocked, and reports are handled within 24 hours."),
    ],
  },
  {
    "slug": "get-nail-clients",
    "title": "How nail techs get new clients, free",
    "meta": "Be found by clients searching your look and your area. My Nail Connection gives nail techs a free profile and gallery, with no commission and no per-booking fee.",
    "eyebrow": "For nail techs",
    "h1": "How do nail techs get new clients?",
    "short": "Be easy to find by your actual work, close to where clients live. On My Nail Connection, your free profile and gallery show up when clients search the Gallery by shape, type, style and distance. Post Available now when you have an opening, reply to client requests, and keep your own booking. No commission and no per-booking fee, ever.",
    "sections": [
      ("Get found by your work",
       ["Post your sets and tag them by shape, type and style. Clients searching those filters, near you, see your work first-hand.",
        "Photos are free, up to 50 a month, and they never expire."]),
      ("Fill openings fast",
       ["Have a gap today? Post <b>Available now</b> with an end time and a note, and your work glows in the Gallery for clients looking right now.",
        "Clients post what they need and when. Reply <b>Interested</b> and they get your profile and your Call, Text or Book button.",
        "Set how far you travel, 10, 25 or 50 miles or your whole state, and get a notification when a request lands within reach."]),
      ("Keep what you earn",
       ["Free to join and free to stay. Your profile, gallery, place in the Gallery, Available now posts and your own booking link cost nothing.",
        "No commission, no per-booking fee, and your clients are never charged to book you.",
        "Booking is optional: add the link you already use, use calls and texts, or try My Nail Connection's own booking free for your first month."]),
    ],
    "faq": [
      ("Is My Nail Connection free for nail techs?", "Yes. It is free to join and free to stay. The only paid feature is My Nail Connection's own booking, which is free for your first month and optional after that."),
      ("Does My Nail Connection take a commission?", "No. There is no commission and no per-booking fee, ever, and your clients are never charged to book you."),
      ("Do I have to stop using Instagram?", "No. My Nail Connection is one more place clients find you, searchable by your look and how close you are."),
      ("How many photos can I post?", "Up to 50 a month, free, and they never expire."),
      ("Is it only for nails?", "Yes. It is built for nail techs specifically. Nails only."),
    ],
  },
  {
    "slug": "vagaro-styleseat-glossgenius",
    "title": "Already on Vagaro, StyleSeat or GlossGenius?",
    "meta": "Keep the booking system you use. Add your Vagaro, StyleSeat or GlossGenius link to a free My Nail Connection profile and get found by clients searching your look.",
    "eyebrow": "For nail techs",
    "h1": "I already book through Vagaro, StyleSeat or GlossGenius. Can I still use My Nail Connection?",
    "short": "Yes, and it costs nothing. Add your booking link to your free My Nail Connection profile, and a Book Now button appears that sends clients straight to your existing system. You keep your calendar and your clients. My Nail Connection adds a searchable portfolio, so new clients find you by your work and how close you are.",
    "sections": [
      ("How it works",
       ["Make your free profile and post your sets, tagged by shape, type and style.",
        "Add your Vagaro, StyleSeat or GlossGenius link. A Book Now button shows on your profile.",
        "Clients find your work in the Gallery, tap Book Now, and book in the system you already use."]),
      ("What you get on top of your booking app",
       ["A place in a Gallery that clients search by look and distance, not just by your name.",
        "Available now posts to fill a gap today, and client requests you can reply to.",
        "No commission and no per-booking fee. Your clients are never charged to book you."]),
    ],
    "faq": [
      ("Does adding my booking link cost anything?", "No. Adding an external booking link is free, along with your profile, gallery and Available now posts."),
      ("Will my clients have to make a new account to book?", "No. Book Now sends them to your existing booking system, where they book the way they already do."),
      ("Can I switch to My Nail Connection's own booking later?", "Yes, if you want to. It is optional and free for your first month."),
      ("Does My Nail Connection take a cut of my bookings?", "No. No commission and no per-booking fee, ever."),
    ],
  },
]

CSS = """
:root{--rose:#DEB3B5;--rose-dark:#A2636C;--link:#8A4F58;--rose-light:#F7E2E3;--cream:#FAF7F2;--ink:#141317;--muted:#6D6068;--border:#EBDDDA}
*{box-sizing:border-box}html,body{margin:0;padding:0}
body{font-family:'DM Sans',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:var(--ink);background:var(--cream);line-height:1.65;-webkit-font-smoothing:antialiased}
a{color:var(--link)}
.top{display:flex;align-items:center;gap:10px;padding:14px 22px;max-width:760px;margin:0 auto}
.top a{display:flex;align-items:center;gap:10px;text-decoration:none;color:var(--ink);font-weight:600}
.top img{width:36px;height:36px}
.hero{background:linear-gradient(135deg,#F7E2E3 0%,#DEB3B5 100%);padding:44px 22px 40px}
.hero .in{max-width:760px;margin:0 auto}
.eyebrow{font-size:12px;letter-spacing:2px;text-transform:uppercase;color:var(--ink);font-weight:600;margin-bottom:10px}
h1{font-family:'Playfair Display',Georgia,serif;font-size:36px;line-height:1.2;margin:0;font-weight:600}
main{max-width:760px;margin:0 auto;padding:28px 22px 40px}
.short{background:#fff;border:1px solid var(--border);border-left:4px solid var(--rose-dark);border-radius:2px;padding:18px 20px;margin:0 0 28px;font-size:17px}
.short b{display:block;font-size:12px;letter-spacing:1.5px;text-transform:uppercase;color:var(--link);margin-bottom:6px}
h2{font-family:'Playfair Display',Georgia,serif;font-size:24px;margin:30px 0 10px;font-weight:600}
ul{padding-left:20px;margin:0}li{margin:0 0 8px}
.faq details{background:#fff;border:1px solid var(--border);border-radius:2px;padding:14px 16px;margin:0 0 10px}
.faq summary{font-weight:600;cursor:pointer}
.faq p{margin:10px 0 0}
.cta{margin:34px 0 0;padding:22px;background:var(--ink);color:#fff;border-radius:2px;text-align:center}
.cta p{margin:0 0 14px;font-size:17px}
.cta a{display:inline-block;margin:4px 6px;padding:11px 18px;background:var(--rose);color:var(--ink);text-decoration:none;font-weight:600;border-radius:2px;box-shadow:0 2px 0 var(--rose-dark)}
.cta a:hover{background:var(--rose-dark);color:#fff}
.more{margin:30px 0 0;font-size:15px}.more li{margin:0 0 6px}
footer{text-align:center;font-size:13px;color:var(--muted);padding:24px 22px 40px}
footer a{color:var(--muted)}
@media(max-width:560px){h1{font-size:28px}}
"""

def esc(s):
    return html.escape(s, quote=True)

def strip_tags(s):
    import re
    return re.sub(r"<[^>]+>", "", s)

def build(p):
    url = f"{SITE}/{p['slug']}.html"
    schema = {"@context": "https://schema.org", "@graph": [
        {"@type": "FAQPage", "@id": url + "#faq", "url": url,
         "mainEntity": [{"@type": "Question", "name": q,
                         "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in
                        [(p["h1"], strip_tags(p["short"]))] + p["faq"]]},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "My Nail Connection", "item": SITE + "/"},
            {"@type": "ListItem", "position": 2, "name": p["title"], "item": url}]},
    ]}
    secs = "\n".join(
        f"<h2>{esc(h)}</h2>\n<ul>\n" + "\n".join(f"<li>{li}</li>" for li in items) + "\n</ul>"
        for h, items in p["sections"])
    faq = "\n".join(f"<details><summary>{esc(q)}</summary><p>{esc(a)}</p></details>" for q, a in p["faq"])
    others = "\n".join(f'<li><a href="/{o["slug"]}.html">{esc(o["h1"])}</a></li>' for o in PAGES if o is not p)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(p['title'])} - My Nail Connection</title>
<meta name="description" content="{esc(p['meta'])}">
<link rel="canonical" href="{url}">
<meta property="og:title" content="{esc(p['title'])}">
<meta property="og:description" content="{esc(p['meta'])}">
<meta property="og:type" content="article">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}/og-image-2026-09.png">
<meta property="og:site_name" content="My Nail Connection">
<meta property="og:image:alt" content="My Nail Connection, the app for finding nail techs by their real work">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.ico">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600&family=DM+Sans:wght@400;600&display=swap" rel="stylesheet">
<style>{CSS}</style>
<script type="application/ld+json">
{json.dumps(schema, indent=2)}
</script>
<script src="/ga4.js" defer></script>
<script src="/visit.js" data-page="answer:{p['slug']}" defer></script>
</head>
<body>
<header class="top"><a href="/"><img src="/images/mncLogo-round-256.webp" width="36" height="36" alt="">My Nail Connection</a></header>
<section class="hero"><div class="in">
<div class="eyebrow">{esc(p['eyebrow'])}</div>
<h1>{esc(p['h1'])}</h1>
</div></section>
<main>
<p class="short"><b>Short answer</b>{p['short']}</p>
{secs}
<h2>Questions people ask</h2>
<div class="faq">
{faq}
</div>
<div class="cta">
<p>Get My Nail Connection, free on iPhone and Android.</p>
<a href="{APP_STORE}">App Store</a><a href="{PLAY}">Google Play</a><a href="/app/">Open on the web</a>
</div>
<div class="more"><b>More answers</b>
<ul>
{others}
<li><a href="/techs/">Nail techs on My Nail Connection, by city</a></li>
<li><a href="/tech-guide-v3.html">How it works, step by step, for nail techs</a></li>
</ul></div>
</main>
<footer><a href="/">Home</a> · <a href="/privacy.html">Privacy</a> · <a href="/terms.html">Terms</a> · <a href="/support.html">Support</a></footer>
</body>
</html>
"""

if __name__ == "__main__":
    for p in PAGES:
        out = pathlib.Path(p["slug"] + ".html")
        out.write_text(build(p), encoding="utf-8")
        print("wrote", out)
