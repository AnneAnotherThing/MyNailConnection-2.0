# Google Play Store Listing — My Nail Connection 2.0

Drafted 2026-04-28. Copy each field into the corresponding box in Play Console → Main store listing.

---

## App name (max 30 chars)

**My Nail Connection**

(20 chars — fits well under the limit)

---

## Short description (max 80 chars)

**Find your tech. Love your nails. Browse local nail artists in one place.**

(73 chars)

Alternates if you want to A/B:
- `Discover talented nail techs near you. Browse real work. Connect direct.` (72)
- `The home for nail art lovers and the techs who create it. Free to start.` (72)

---

## Full description (max 4000 chars)

```
Stop scrolling Instagram hoping to find a local nail tech. My Nail Connection puts every talented artist near you in one beautiful place — searchable, filterable, and ready to connect.

FIND YOUR TECH

Browse real nail art from real techs in your area. Filter by style, location, and what you actually want. Tap to see the artist's full portfolio, their story, and how to reach them directly. No bots, no booking middlemen — just a clean way to find someone whose work you love.

LOVE YOUR NAILS

Save the looks that catch your eye. Build a feed of techs you're obsessed with. When you're ready, message them straight from their profile. We don't handle bookings — we just make sure you find the right tech and get in touch.

FOR NAIL TECHS

Your work deserves to be found. My Nail Connection is built to give nail artists a real storefront — not another social feed where your best work gets buried. Upload photos, tag styles, write a profile that actually sounds like you. Clients in your area are already searching. Let them find you.

Free to start. Premium options when you're ready to grow.

WHAT MAKES MNC DIFFERENT

• Built for nails, by people who love nails — not a generic services app
• Real portfolios, not a feed of strangers' selfies
• Direct connection between you and the tech, no booking layer in the middle
• Glow Up subscription gives techs a steady rhythm of new photo slots so portfolios stay fresh
• Beautiful by design, powerful by default

WHO IT'S FOR

• Anyone who's ever screenshotted a nail set and asked "where do I find someone who does this?"
• Nail techs ready to be discovered by the clients who'll love their work
• Salon owners building a team presence in their local market

JOIN THE COMMUNITY

My Nail Connection is more than an app — it's a community of artists and clients who care about beautiful nails and good people. Sign up free, browse for as long as you like, and connect when you find your match.

Your talent is already there. We just make sure clients can find it.

mynailconnection.com
```

(~2,050 chars — leaves room to add more if you want.)

---

## What's new (release notes, max 500 chars)

```
Welcome to My Nail Connection 2.0 — fully rebuilt from the ground up.

What's new:
• Faster, cleaner browsing with filter by style and location
• Real artist profiles with full portfolios
• Glow Up subscription for techs — fresh photo slots on a steady cadence
• Direct in-app messaging between clients and techs
• Push notifications for messages and updates
• Beautiful new design throughout

Free to start. Welcome back, and welcome in. 🌸
```

(~480 chars)

---

## Other Play Console fields you'll need to fill

These aren't description copy but Play Console will ask:

- **App category:** Lifestyle (primary). Beauty as secondary if available.
- **Tags / keywords:** nails, nail art, nail tech, beauty, salon, manicure, pedicure, nail artist
- **Contact email:** annewilson1021@gmail.com (or a support@ alias if you have one)
- **Website:** https://mynailconnection.com
- **Privacy policy URL:** https://mynailconnection.com/privacy.html
- **Content rating:** Everyone (run the questionnaire — no violence, no UGC moderation issues to flag beyond standard "users can post photos" → answer honestly that yes, users post images, and you have report/block flows)

---

## Heads-up before you hit publish

- **Data safety form** — Play will ask you to declare what data you collect (email, photos, push token, location if used). Match what's actually in `index.html` + Supabase. Don't undercount; rejections here come back as 7-day delays.
- **Target API level** — Make sure the Capawesome build targets the current Play minimum (API 34 as of 2026, likely 35 by now — confirm in Capawesome's build config).
- **App Links / `assetlinks.json`** — Still need this live at `mynailconnection.com/.well-known/assetlinks.json` BEFORE the build ships, or every Supabase auth email will dump users into the browser instead of the app. This is the one risk I'd double-check before promoting to production.
- **In-app purchases** — If photo bundles / Glow Up bill through Stripe on Android (not Play Billing), Google may flag it. Worth confirming what the build does on Android specifically before review.
```

