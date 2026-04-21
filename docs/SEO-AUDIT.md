# MNC Marketing Site — SEO Audit & Fixes

**Date:** 2026-04-17
**Scope:** `marketing.html` + supporting pages in this folder
**Domain assumed:** `https://mynailconnection.com/` (swap in the audit files if the production domain differs)

---

## TL;DR — what changed

| Area | Before | After |
|---|---|---|
| Page weight (marketing.html) | 175 KB | 100 KB (−43%) |
| Favicon / logo images | 3× massive base64 data URIs (~75 KB inline) | Real files, cacheable, CDN-friendly |
| Canonical URL | — | `https://mynailconnection.com/` |
| Open Graph / Twitter card | — | Full set, 1200×630 branded image |
| Structured data (JSON-LD) | — | Organization + WebSite + WebPage + MobileApplication + FAQPage |
| robots.txt / sitemap.xml | Missing | Created, AI-scraper-blocked, sitemap indexed |
| Footer legal links | `href="#"` stubs | Real `/privacy.html`, `/terms.html`, `mailto:` contact |
| Screenshot imgs | No dimensions, no lazy-load | `width`/`height`/`loading="lazy"`/`decoding="async"` |
| Internal pages (punch list, runbook) | Indexable | `noindex, nofollow` |
| PWA manifest | Referenced missing 1024 icon, no screenshots | Fixed icon, all screenshots listed, `scope`/`id`/`lang` added |
| Analytics | None | Commented-in scaffolding for GA4, Meta, TikTok, Pinterest + consent stub + UTM persistence |

---

## What's new in the folder

**Created:**
- `robots.txt` — allows public pages, blocks ops pages and major AI training crawlers (GPTBot, ClaudeBot, CCBot, Google-Extended, PerplexityBot)
- `sitemap.xml` — 5 URLs, with image sitemap extension on the home URL
- `og-image.png` — 1200×630 branded social card (logo + "Find your tech / Love your nails" + URL chip)
- `favicon.ico` — multi-size (16/32/48)
- `favicon-32.png` — modern PNG favicon
- `apple-touch-icon.png` — 180×180 opaque icon on brand rose background
- `images/mncLogo-1024.webp` — the one the manifest was referencing but missing
- `privacy.html` — stub privacy policy page (pre-launch placeholder, marked as such, with real contact path)
- `terms.html` — stub terms of service page (same treatment)
- `404.html` — branded 404 page

**Modified:**
- `marketing.html` — full SEO head, base64 imgs swapped for real files, screenshot imgs upgraded, footer links fixed
- `tech-guide.html` — full SEO head (HowTo schema) + base64 imgs swapped
- `manifest.json` — fixed 1024 icon reference, added screenshots, scope/id/lang, start_url with UTM
- `punch-list.html` — `noindex, nofollow, noarchive`
- `ANDROID-BUILD-RUNBOOK.html` — `noindex, nofollow, noarchive`

---

## Technical SEO — what was wrong, what I did

**Missing canonical URL.** Search engines had no authoritative URL for the page. Added `<link rel="canonical" href="https://mynailconnection.com/">`.

**No robots directive.** Added explicit `index, follow` plus `max-image-preview:large` so Google can show rich image results, and `max-snippet:-1` to allow full text snippets.

**No sitemap.** Created `sitemap.xml` with the home page, tech guide, and legal pages. robots.txt now references it.

**Language/locale signals weak.** `html lang="en"` was already set. Added `<meta property="og:locale" content="en_US">` and `inLanguage` on JSON-LD, plus `lang: "en-US"` on manifest.

**Noindex for internal surfaces.** `punch-list.html` and `ANDROID-BUILD-RUNBOOK.html` were fully indexable — embarrassing risk (Stripe setup steps, admin flows in the index). Both now have `noindex, nofollow, noarchive` meta tags and are `Disallow`ed in robots.txt.

**404 page.** Added a branded `404.html`. Wire up at the host/CDN level so it's actually served on misses (Netlify: `[[redirects]]`, Vercel: auto, Cloudflare: error page config).

---

## Social / sharing (Open Graph + Twitter)

**Zero social metadata before.** If someone dropped `mynailconnection.com` into iMessage, Slack, LinkedIn, X, or Facebook, they got a bare link. That's bad for launch. Fixed:

- Full OG tag set: `type`, `site_name`, `title`, `description`, `url`, `image`, `image:width`, `image:height`, `image:alt`, `locale`
- Twitter card (`summary_large_image`) with image alt
- Branded 1200×630 PNG at `og-image.png` — logo on left, "Find your tech. / Love your nails." headline, subtitle, and `mynailconnection.com` chip on the brand rose gradient
- Twitter `@handle` slot is commented, uncomment when you claim `@mynailconnection`

**Validate before launch:** paste the URL into
- [Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/)
- [X / Twitter Card Validator](https://cards-dev.twitter.com/validator) (may require login)
- [LinkedIn Post Inspector](https://www.linkedin.com/post-inspector/)

---

## Structured data (JSON-LD)

Five interlinked schemas in a single `@graph`:

1. **Organization** — name, logo, email, description. This is the canonical business entity. Rich-result eligible.
2. **WebSite** — with a `SearchAction` so if/when the site search grows up, Google can surface a sitelinks search box.
3. **WebPage** — the home page, linked to Organization and WebSite.
4. **MobileApplication** — positions MNC as an app with three pricing offers (Starter free, Spotlight $1/photo, Glow Up $9/mo). App-related rich results.
5. **FAQPage** — four Q&As about pricing, finding techs, integration with existing booking, launch timing. FAQ rich results in search.

`tech-guide.html` also got **HowTo** schema.

**Validate:** https://search.google.com/test/rich-results — paste the final URL once deployed.

---

## Performance wins

**Inlined 75 KB of base64 images** that browsers can never cache across pages. Swapped for real files that CDN/browser cache normally. Net: `marketing.html` dropped from 175 KB to 100 KB.

**Hero logo now preloaded** with `fetchpriority="high"` so LCP happens sooner.

**Supabase DNS prefetch + preconnect** added so the waitlist form's first `fetch()` isn't delayed by TCP + TLS handshakes.

**All `<img>` tags now have** `alt`, `width`, `height` (prevents CLS), `loading="lazy"` on below-the-fold, `decoding="async"`.

**Font loading** — already used `display=swap`, already preconnected to `fonts.gstatic.com`. No change needed.

---

## Analytics & tracking (scaffolding only, no IDs yet)

Added a commented-out block in the marketing head with drop-in loaders for:

- **Google Analytics 4** — paste `G-XXXXXXXXXX` and uncomment
- **Meta (Facebook) Pixel** — for retargeting, same pattern
- **TikTok Pixel** — useful since nail content has a huge presence there
- **Pinterest Tag** — visual discovery platform, high-intent audience for nails

Also added:

- **Consent-aware init** — GA4 loads in `denied` default mode; flip `window.mncConsent = true` via a cookie banner to enable. Required for EU/UK traffic under GDPR.
- **UTM persistence** — first-touch `utm_source`/`utm_medium`/`utm_campaign`/`utm_term`/`utm_content`/`ref`/`fbclid`/`gclid` are stored in `sessionStorage` and auto-appended to internal links, so attribution survives tab-level navigation. Zero-dep, runs inline, and swallows its own errors so it can never break the page.

**Search Console verification meta tags** are stubbed with `PASTE_..._HERE` placeholders for Google, Bing, Facebook, Pinterest.

---

## What's still on you (the bits I can't do)

1. **Confirm the production domain.** I assumed `mynailconnection.com`. If it's different, find-and-replace that string across `marketing.html`, `tech-guide.html`, `privacy.html`, `terms.html`, `sitemap.xml`, `robots.txt`, `404.html`.

2. **Decide on `/` routing.** Right now `index.html` is the app and `marketing.html` is the marketing page. The canonical and sitemap point `/` to the marketing page. You need to configure your host to serve `marketing.html` at `/` (or do a rewrite), and move the app to `/app` or `/login`. Otherwise organic traffic lands on the PWA shell. If you want to keep the app at `/`, update all the canonical/OG/sitemap URLs to point at `/marketing.html` explicitly.

3. **Claim these properties and paste the verification tokens** into the marketing head (they're commented, clearly labeled):
   - Google Search Console (submit sitemap.xml here too)
   - Bing Webmaster Tools
   - Facebook Business / Domain verification
   - Pinterest (nail content is gold on Pinterest — do not skip)

4. **Get real tracking IDs** and paste them into the analytics block. At minimum GA4. Meta pixel is worth it if you'll run launch ads.

5. **Wire a consent banner** for EU/UK/California visitors. The `window.mncConsent` stub is ready; any cookie banner library can flip it.

6. **Replace the stub legal pages** before launch. `privacy.html` and `terms.html` are clearly marked placeholders — good enough for a soft launch but need real versions reviewed by counsel before heavy promotion.

7. **Claim the social handle** `@mynailconnection` (or whatever you go with) and uncomment the two `twitter:site` / `twitter:creator` lines.

8. **Add real screenshots to the manifest** at the right dimensions if 1284×2778 isn't accurate for the files in `/screenshots/`. Manifest screenshots are what Android uses in the install prompt UI.

9. **Submit to search engines** after deploy:
   - Google Search Console → Sitemaps → paste `https://mynailconnection.com/sitemap.xml`
   - Bing Webmaster → same
   - Request indexing on the homepage URL

10. **OG image refresh.** The generated one is solid but generic. If you want a launch-grade one with actual nail art photography, have a designer build a 1200×630 at `og-image.png` — the path is already wired site-wide.

---

## File reference

Everything below lives in the root of this folder and is ready to deploy:

- `robots.txt`, `sitemap.xml` — ship to web root
- `favicon.ico`, `favicon-32.png`, `apple-touch-icon.png`, `og-image.png` — ship to web root
- `marketing.html`, `tech-guide.html` — SEO-complete
- `privacy.html`, `terms.html`, `404.html` — stub but live-ready
- `manifest.json` — installable PWA manifest, fixed
- `punch-list.html`, `ANDROID-BUILD-RUNBOOK.html` — marked noindex

---

## Punch list item added

Per your ask, added a High-priority item to `punch-list.html` titled **"Confirm international + at-volume readiness"** covering Supabase tier/region, rate limits, storage bandwidth, Stripe international support, email deliverability at scale, GDPR/CCPA exposure, i18n decision, and a load test. That's pre-launch critical even if everything looks fine today.
