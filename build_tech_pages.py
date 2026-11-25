# Build one public page per nail tech, plus a /techs/ index (2026-11-24, DRAFT).
#
# Why: inside the app a tech's work is invisible to Google and the chat
# assistants. A plain page per tech, with her real sets, city and styles,
# can be found for "gel-X Glendale" or her own name, and gives her a link
# to share that points at MNC.
#
# Source: public.techs_public on the live 3.0 project, read with the public
# key (the same rows any guest sees in the app). Only techs who are visible
# (not self-paused) and have at least MIN_PHOTOS photos get a page; thinner
# pages would hurt more than help. Never shown: zip, lat/lng, street address.
#
# Also runs nightly in .github/workflows/deploy.yml (3:17 AM Phoenix).
# Run: python build_tech_pages.py --publish   (rewrites techs/ and the marked
# block in sitemap.xml), then deploy/sync.sh. Without --publish it only builds
# techs/ for review. Re-run before each deploy so new techs
# and photos appear and paused techs drop off.
import json, pathlib, re, html, urllib.request, sys
from build_answer_pages import CSS as BASE_CSS, SITE, APP_STORE, PLAY

MIN_PHOTOS = 3
MAX_PHOTOS = 12
OUT = pathlib.Path("techs")
PROJECT = "https://nwqnakoongrorbwnrqzc.supabase.co"

def anon_key():
    src = pathlib.Path("index.html").read_bytes().decode("utf-8", "ignore")
    for k in sorted(set(re.findall(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", src))):
        import base64
        body = k.split(".")[1]; body += "=" * (-len(body) % 4)
        claims = json.loads(base64.urlsafe_b64decode(body))
        if claims.get("role") == "anon" and claims.get("ref") == "nwqnakoongrorbwnrqzc":
            return k
    sys.exit("anon key for the 3.0 project not found in index.html")

def fetch():
    k = anon_key()
    cols = "id,name,shop_name,bio,tags,city,state,photos,image_url,booking_link,is_visible,is_bookable"
    req = urllib.request.Request(f"{PROJECT}/rest/v1/techs_public?select={cols}",
                                 headers={"apikey": k, "Authorization": "Bearer " + k})
    return json.load(urllib.request.urlopen(req, timeout=30))

def slugify(s):
    s = re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")
    return s or "tech"

def esc(s):
    # techs' own text: dashes become hyphens (house rule), then escape
    s = (s or "").replace("—", " - ").replace("–", "-")
    return html.escape(s, quote=True)

CONTACT_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}|\+?1?[ .-]?\(?[0-9]{3}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}")

def web_bio(s):
    # Phone numbers and emails stay in the app; the open web gets a pointer.
    s = CONTACT_RE.sub("(contact details in the app)", s or "")
    return re.sub(r"\s*\(contact details in the app\)", " (contact details in the app)", s).strip()

def thumb_img(url, alt, size=300):
    # The app writes <name>_thumb.jpg (500px) beside every photo; fall back to the full one.
    t = re.sub(r"\.(jpe?g|png|webp|heic)$", "_thumb.jpg", url, flags=re.I)
    return (f'<img src="{esc(t)}" onerror="this.onerror=null;this.src=\'{esc(url)}\'" loading="lazy" '
            f'decoding="async" width="{size}" height="{size}" alt="{esc(alt)}">')

def nice_name(n):
    # Capitalize words a tech typed in lowercase; keep particles like "de" lowercase.
    small = {"de", "del", "la", "las", "los", "y", "van", "von", "da", "di"}
    out = []
    for i, w in enumerate((n or "").strip().split()):
        if w.islower() and not (i and w in small):
            w = w[:1].upper() + w[1:]
        out.append(w)
    return " ".join(out)

def tidy_city(c):
    return " ".join(w.capitalize() for w in (c or "").strip().split())

CSS = BASE_CSS + """
[hidden]{display:none!important}
.meta{color:var(--muted);margin:8px 0 0}
.tags{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0 0;padding:0;list-style:none}
.tags li{background:#fff;border:1px solid var(--border);border-radius:2px;padding:3px 10px;font-size:14px;margin:0}
.bio{white-space:pre-line}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;margin:18px 0 0}
.grid img{width:100%;aspect-ratio:1;object-fit:cover;display:block;border-radius:2px;background:var(--rose-light)}
@media(max-width:560px){.grid{grid-template-columns:repeat(2,1fr)}}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:14px;margin:12px 0 0}
.card{background:#fff;border:1px solid var(--border);border-radius:2px;overflow:hidden;text-decoration:none;color:var(--ink);display:block}
.card img{width:100%;aspect-ratio:1;object-fit:cover;display:block;background:var(--rose-light)}
.card div{padding:10px 12px}.card b{display:block}.card span{color:var(--muted);font-size:14px}
.lede{margin:12px 0 0;max-width:60ch;color:#3d2f35}
main.wide{max-width:1120px}
.hero.wide .in{max-width:1076px}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}
.fbar{position:sticky;top:0;z-index:5;background:rgba(250,247,242,.94);backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);border-bottom:1px solid var(--border);padding:12px max(16px,calc((100% - 1120px)/2 + 22px))}
.frow{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.fsearch{flex:1 1 220px}.fsearch input,.fsel select{width:100%;font:inherit;font-size:15px;padding:9px 12px;border:1px solid var(--border);border-radius:2px;background:#fff;color:var(--ink)}
.fsel{flex:0 1 220px}
.chips{display:flex;gap:6px;overflow-x:auto;padding:10px 0 2px;scrollbar-width:none}.chips::-webkit-scrollbar{display:none}
.chip{flex:0 0 auto;font:inherit;font-size:13.5px;font-weight:600;padding:7px 13px;border:1px solid var(--border);border-radius:2px;background:#fff;color:var(--ink);cursor:pointer;box-shadow:0 1px 0 var(--border)}
.chip:hover{border-color:var(--ink)}
.chip[aria-pressed="true"]{background:var(--ink);color:#fff;border-color:var(--ink)}
.chip.tog[aria-pressed="true"]{background:var(--link);border-color:var(--link)}
.chip:focus-visible,.fsearch input:focus-visible,.fsel select:focus-visible,.clear:focus-visible{outline:2px solid var(--link);outline-offset:2px}
.fcount{display:flex;gap:12px;align-items:center;font-size:13.5px;color:var(--muted);margin-top:6px}
.clear{font:inherit;font-size:13.5px;font-weight:600;color:var(--link);background:none;border:0;padding:0;cursor:pointer;text-decoration:underline}
.place h2{margin-top:30px}
.tcards{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px;margin:12px 0 0}
.tcard{display:flex;flex-direction:column;background:#fff;border:1px solid var(--border);border-radius:2px;overflow:hidden;text-decoration:none;color:var(--ink);transition:transform .18s ease,box-shadow .18s ease}
.tcard:hover,.tcard:focus-visible{transform:translateY(-3px);box-shadow:0 12px 28px rgba(20,19,23,.12);outline:none}
.mosaic{display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr);grid-template-rows:repeat(2,minmax(0,1fr));gap:3px;aspect-ratio:3/2;overflow:hidden;background:var(--rose-light)}
.mosaic img{width:100%;height:100%;min-height:0;object-fit:cover;display:block;aspect-ratio:auto}
.mosaic img:first-child{grid-row:1 / span 2}
.mosaic img:only-child{grid-column:1 / span 2}
.tbody{padding:12px 14px 14px;display:flex;flex-direction:column;gap:4px}
.tbody b{font-size:17px}
.where{color:var(--muted);font-size:13.5px}
.mini{display:flex;flex-wrap:wrap;gap:5px;list-style:none;padding:0;margin:4px 0 0}
.mini li{font-size:12px;background:var(--rose-light);border-radius:2px;padding:2px 8px;margin:0}
.foot{display:flex;gap:8px;align-items:center;font-size:12.5px;color:var(--muted);margin-top:6px}
.bk{font-weight:700;color:#2D6A4F;background:#EAF3EC;border-radius:2px;padding:1px 7px}
.none{margin:24px 0;color:var(--muted)}
@media (prefers-reduced-motion: reduce){.tcard{transition:none}.tcard:hover{transform:none}}
"""

def head(title, desc, url, image, schema, ogtype="profile", visit="tech-page"):
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(desc)}">
<link rel="canonical" href="{url}">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(desc)}">
<meta property="og:type" content="{ogtype}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{esc(image)}">
<meta property="og:site_name" content="My Nail Connection">
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
<script src="/visit.js" data-page="{visit}" defer></script>
</head>
<body>
<header class="top"><a href="/"><img src="/images/mncLogo-round-256.webp" width="36" height="36" alt="">My Nail Connection</a></header>
"""

FOOT = """<footer><a href="/">Home</a> · <a href="/techs/">All nail techs</a> · <a href="/find-a-nail-tech-phoenix.html">Find a nail tech</a> · <a href="/privacy.html">Privacy</a> · <a href="/terms.html">Terms</a></footer>
</body>
</html>
"""

def live_check(tech_id=None):
    # Hide in the admin panel (techs.stealth) or a self-pause takes a tech out
    # of techs_public at once; the page checks on load so she disappears now,
    # not at the next nightly rebuild (which then removes the page itself).
    k = anon_key()
    q = f"select=id&id=eq.{tech_id}" if tech_id else "select=id"
    if tech_id:
        act = """if (rows.length === 0) {
      var m = document.createElement('meta'); m.name = 'robots'; m.content = 'noindex'; document.head.appendChild(m);
      document.querySelector('.hero .in').innerHTML = '<div class="eyebrow">Nail techs</div><h1>Not listed right now</h1>';
      document.querySelector('main').innerHTML = '<p class="short"><b>Not listed</b>This nail tech is not listed on My Nail Connection right now. <a href="/techs/">See the other nail techs</a> or open the free app to browse by style and distance.</p>';
    }"""
    else:
        act = """if (!rows.length) return;  // an empty answer is a fault, never "hide everyone"
    var live = {}; rows.forEach(function (r) { live[r.id] = 1; });
    document.querySelectorAll('.tcard[data-id]').forEach(function (c) { if (!live[c.getAttribute('data-id')]) c.setAttribute('data-gone', '1'); });
    if (window.__techFilter) window.__techFilter();"""
    return f"""<script>
(function () {{
  fetch('{PROJECT}/rest/v1/techs_public?{q}', {{ headers: {{ apikey: '{k}', Authorization: 'Bearer {k}' }} }})
    .then(function (r) {{ return r.ok ? r.json() : null; }})
    .then(function (rows) {{ if (!Array.isArray(rows)) return;
    {act}
  }}).catch(function () {{}});
}})();
</script>
"""

def cta(tech_id):
    return f"""<div class="cta">
<p>See her full gallery and book, call or text her in the free My Nail Connection app.</p>
<a href="/app/?tech={esc(tech_id)}&amp;src=techpage">See her in the app</a><a href="{APP_STORE}">App Store</a><a href="{PLAY}">Google Play</a>
</div>"""

def tech_page(t, slug):
    name = nice_name(t["name"])
    city, state = tidy_city(t.get("city")), (t.get("state") or "").strip().upper()
    where = ", ".join(x for x in (city, state) if x)
    url = f"{SITE}/techs/{slug}.html"
    tags = [x for x in (t.get("tags") or []) if x]
    photos = [p for p in (t.get("photos") or []) if isinstance(p, dict) and p.get("url")][:MAX_PHOTOS]
    style_txt = ", ".join(tags[:6])
    title = f"{name}, nail tech in {where} - My Nail Connection" if where else f"{name}, nail tech - My Nail Connection"
    desc = (f"See real nail work by {name}" + (f" in {where}" if where else "") +
            (f": {style_txt}." if style_txt else ".") + " Book, call or text her on My Nail Connection, free for clients.")
    image = t.get("image_url") or photos[0]["url"]
    person = {"@type": "Person", "name": name, "jobTitle": "Nail technician", "image": image, "url": url}
    if t.get("shop_name"): person["alternateName"] = t["shop_name"].strip()
    if where: person["address"] = {"@type": "PostalAddress", "addressLocality": city, "addressRegion": state}
    if tags: person["knowsAbout"] = tags
    schema = {"@context": "https://schema.org", "@graph": [
        {"@type": "ProfilePage", "url": url, "mainEntity": person},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "My Nail Connection", "item": SITE + "/"},
            {"@type": "ListItem", "position": 2, "name": "Nail techs", "item": SITE + "/techs/"},
            {"@type": "ListItem", "position": 3, "name": name, "item": url}]}]}
    imgs = "\n".join(
        thumb_img(p["url"], (" ".join((p.get("tags") or [])[:3]) + " nails by " + name) if p.get("tags") else "Nail set by " + name)
        for p in photos)
    shop = f'<p class="meta">{esc(t["shop_name"].strip())}</p>' if t.get("shop_name") else ""
    if (t.get("bio") or "").strip():
        bio = f'<h2>About {esc(name)}</h2>\n<p class="bio">{esc(web_bio(t["bio"]))}</p>'
    else:
        bio = (f'<h2>About {esc(name)}</h2>\n<p>{esc(name)} is a nail tech' + (f' in {esc(where)}' if where else '')
               + '.' + (f' On My Nail Connection she lists {esc(", ".join(tags[:5]))}.' if tags else '')
               + ' The gallery above is her own work, and you can reach her through the free My Nail Connection app.</p>')
    tag_ul = "<ul class=\"tags\">" + "".join(f"<li>{esc(x)}</li>" for x in tags) + "</ul>" if tags else ""
    ext = ""
    if (t.get("booking_link") or "").startswith("http"):
        ext = f'<p>Already know her? <a href="{esc(t["booking_link"])}" rel="nofollow ugc noopener">Book on her booking site</a>.</p>'
    return head(title, desc, url, image, schema, "profile", "tech:" + slug) + f"""<section class="hero"><div class="in">
<div class="eyebrow">Nail tech{(" in " + esc(where)) if where else ""}</div>
<h1>{esc(name)}</h1>
{shop}
{tag_ul}
</div></section>
<main>
<h2>Her work</h2>
<div class="grid">
{imgs}
</div>
{bio}
{ext}
{cta(t["id"])}
<div class="more"><b>More on My Nail Connection</b>
<ul>
<li><a href="/techs/">All nail techs on My Nail Connection</a></li>
<li><a href="/find-a-nail-tech-phoenix.html">How to find a good nail tech near you</a></li>
<li><a href="/nails-today.html">Where to get your nails done today</a></li>
</ul></div>
</main>
""" + live_check(t["id"]) + FOOT

def index_page(entries):
    url = f"{SITE}/techs/"
    by_place = {}
    for slug, t in entries:
        where = ", ".join(x for x in (tidy_city(t.get("city")), (t.get("state") or "").upper()) if x) or "Other"
        by_place.setdefault(where, []).append((slug, t))
    order = sorted(by_place, key=lambda w: (not w.endswith(", AZ"), -len(by_place[w]), w))
    # Style chips: the tags most techs use, so a tap usually finds someone.
    counts = {}
    for _, t in entries:
        for tag in set(x for x in (t.get("tags") or []) if x):
            counts[tag] = counts.get(tag, 0) + 1
    chips = [k for k, _ in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0].lower()))[:12]]
    blocks = []
    for w in order:
        cards = []
        for s, t in sorted(by_place[w], key=lambda e: e[1]["name"].lower()):
            ph = [p for p in (t.get("photos") or []) if isinstance(p, dict) and p.get("url")]
            name = nice_name(t["name"])
            tags = [x for x in (t.get("tags") or []) if x]
            books = bool(t.get("is_bookable")) or (t.get("booking_link") or "").startswith("http")
            mosaic = thumb_img(ph[0]["url"], "") + "".join(thumb_img(p["url"], "", 150) for p in ph[1:3])
            cards.append(
                f'<a class="tcard" data-id="{esc(t["id"])}" data-name="{esc(name.lower())}" data-city="{esc(w)}" '
                f'data-tags="{esc("|".join(tags))}" data-book="{1 if books else 0}" href="/techs/{s}.html">'
                f'<div class="mosaic">{mosaic}</div>'
                f'<div class="tbody"><b>{esc(name)}</b><span class="where">{esc(w)}</span>'
                + ('<ul class="mini">' + "".join(f"<li>{esc(x)}</li>" for x in tags[:3]) + "</ul>" if tags else "")
                + f'<span class="foot">{len(ph)} {"photo" if len(ph) == 1 else "photos"}'
                + ('<span class="bk">Books online</span>' if books else "")
                + "</span></div></a>")
        blocks.append(f'<section class="place" data-place="{esc(w)}"><h2>{esc(w)}</h2>\n<div class="tcards">\n' + "\n".join(cards) + "\n</div></section>")
    schema = {"@context": "https://schema.org", "@type": "CollectionPage", "url": url,
              "name": "Nail techs on My Nail Connection",
              "hasPart": [{"@type": "ProfilePage", "url": f"{SITE}/techs/{s}.html"} for s, _ in entries]}
    title = "Nail techs on My Nail Connection, by city"
    desc = "Browse nail techs on My Nail Connection by city and style and see their real work before you book. Free for clients."
    city_opts = "".join(f'<option value="{esc(w)}">{esc(w)} ({len(by_place[w])})</option>' for w in order)
    chip_html = "".join(f'<button type="button" class="chip" data-tag="{esc(c)}" aria-pressed="false">{esc(c)}</button>' for c in chips)
    return head(title, desc, url, f"{SITE}/og-image-2026-09.png", schema, "website", "techs") + f"""<section class="hero wide"><div class="in">
<div class="eyebrow">For clients</div>
<h1>Nail techs on My Nail Connection</h1>
<p class="lede">{len(entries)} techs with a gallery of their own work. Pick a city or a style, tap a tech to see her sets, then book, call or text her in the free app.</p>
</div></section>
<div class="fbar" id="fbar">
  <div class="frow">
    <label class="fsearch"><span class="sr">Search by name</span><input id="f-q" type="search" placeholder="Search by name" autocomplete="off"></label>
    <label class="fsel"><span class="sr">City</span><select id="f-city"><option value="">All cities</option>{city_opts}</select></label>
    <button type="button" class="chip tog" id="f-book" aria-pressed="false">Books online</button>
  </div>
  <div class="chips" role="group" aria-label="Filter by style">{chip_html}</div>
  <div class="fcount"><span id="f-count">{len(entries)} techs</span><button type="button" id="f-clear" class="clear" hidden>Clear filters</button></div>
</div>
<main class="wide">
{chr(10).join(blocks)}
<p class="none" id="f-none" hidden>No techs match those filters yet. <button type="button" class="clear" onclick="document.getElementById('f-clear').click()">Clear filters</button></p>
{cta("").replace('/app/?tech=&amp;src=techpage', '/app/?src=techindex').replace("See her full gallery and book, call or text her", "Browse every tech, filter by style and distance, and book, call or text")}
</main>
<script>
(function () {{
  var q = document.getElementById('f-q'), city = document.getElementById('f-city'), book = document.getElementById('f-book');
  var chips = [].slice.call(document.querySelectorAll('.chips .chip')), clear = document.getElementById('f-clear');
  var count = document.getElementById('f-count'), none = document.getElementById('f-none');
  function on(b) {{ return b.getAttribute('aria-pressed') === 'true'; }}
  function apply() {{
    var term = (q.value || '').trim().toLowerCase(), c = city.value, wantBook = on(book);
    var tags = chips.filter(on).map(function (b) {{ return b.getAttribute('data-tag'); }});
    var shown = 0;
    document.querySelectorAll('.place').forEach(function (sec) {{
      var any = false;
      sec.querySelectorAll('.tcard').forEach(function (card) {{
        if (card.getAttribute('data-gone') === '1') {{ card.hidden = true; return; }}
        var t = '|' + card.getAttribute('data-tags') + '|';
        var ok = (!term || card.getAttribute('data-name').indexOf(term) !== -1)
          && (!c || card.getAttribute('data-city') === c)
          && (!wantBook || card.getAttribute('data-book') === '1')
          && tags.every(function (x) {{ return t.indexOf('|' + x + '|') !== -1; }});
        card.hidden = !ok; if (ok) {{ any = true; shown++; }}
      }});
      sec.hidden = !any;
    }});
    count.textContent = shown + (shown === 1 ? ' tech' : ' techs');
    none.hidden = shown !== 0;
    clear.hidden = !(term || c || wantBook || tags.length);
  }}
  window.__techFilter = apply;
  q.addEventListener('input', apply); city.addEventListener('change', apply);
  [book].concat(chips).forEach(function (b) {{ b.addEventListener('click', function () {{ b.setAttribute('aria-pressed', on(b) ? 'false' : 'true'); apply(); }}); }});
  clear.addEventListener('click', function () {{ q.value = ''; city.value = ''; [book].concat(chips).forEach(function (b) {{ b.setAttribute('aria-pressed', 'false'); }}); apply(); }});
}})();
</script>
""" + FOOT

def main():
    rows = fetch()
    keep = [t for t in rows if t.get("is_visible") and (t.get("name") or "").strip()
            and len([p for p in (t.get("photos") or []) if isinstance(p, dict) and p.get("url")]) >= MIN_PHOTOS]
    used, entries = set(), []
    for t in sorted(keep, key=lambda t: t["id"]):
        base = slugify(t["name"] + " " + (t.get("city") or ""))
        slug = base if base not in used else f"{base}-{t['id'][:6]}"
        used.add(slug); entries.append((slug, t))
    # Safety: an empty or collapsed answer (a view or key change) must never
    # take the live pages down. Exit non-zero so the nightly step keeps the
    # committed pages.
    live_now = len([f for f in pathlib.Path("deploy/ghpages/techs").glob("*.html") if f.name != "index.html"])
    if not entries:
        sys.exit("0 tech pages from the app; keeping the committed ones")
    if live_now and len(entries) < live_now / 2:
        sys.exit(f"only {len(entries)} tech pages vs {live_now} live; keeping the committed ones")
    if OUT.exists():
        for f in OUT.glob("*.html"): f.unlink()
    OUT.mkdir(exist_ok=True)
    for slug, t in entries:
        (OUT / f"{slug}.html").write_text(tech_page(t, slug), encoding="utf-8")
    (OUT / "index.html").write_text(index_page(entries), encoding="utf-8")
    if "--publish" not in sys.argv:
        print(f"{len(entries)} tech pages built (draft: sitemap untouched; run with --publish once locked)")
        return
    # sitemap: rewrite the marked block
    sm = pathlib.Path("sitemap.xml"); h = sm.read_text(encoding="utf-8")
    start, end = "  <!-- TECH PAGES START (build_tech_pages.py) -->\n", "  <!-- TECH PAGES END -->\n"
    urls = [f"{SITE}/techs/"] + [f"{SITE}/techs/{s}.html" for s, _ in entries]
    block = start + "".join(f"  <url>\n    <loc>{u}</loc>\n    <changefreq>weekly</changefreq>\n    <priority>0.6</priority>\n  </url>\n" for u in urls) + end
    if start in h:
        h = h[:h.index(start)] + block + h[h.index(end) + len(end):]
    else:
        h = h.replace("</urlset>", block + "</urlset>")
    sm.write_text(h, encoding="utf-8")
    print(f"{len(entries)} tech pages of {len(rows)} techs (visible with {MIN_PHOTOS}+ photos)")

if __name__ == "__main__":
    main()
