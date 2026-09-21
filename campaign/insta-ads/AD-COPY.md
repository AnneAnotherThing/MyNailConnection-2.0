# Instagram ads: found by your work

Audience: nail techs. One carousel (feed, 4:5) and the same seven frames as stories (9:16).
PNGs are in `png/`. Rebuild with `node build-slides.js && bash render.sh`.

Story frames keep everything between 262px and 1540px, clear of Instagram's
profile bar at the top and the reply box at the bottom.

## Carousel ad (feed)

**Primary text** (first 125 characters show before "more"):

> Clients don't search for your name. They search for your nails. On My Nail Connection they filter by the look they want, find your set, and reach you in one tap: book right on your gallery, call, or text.
>
> Your profile, your gallery, getting found and your call and text buttons are free, forever. The only thing you pay for is the booking tool, $10.99 a month, first month free.
>
> No commission. No new-client fee. Never a charge to your clients.

**Headline:** Get found by your work

**Description:** First month free. Nails only.

**Call to action button:** Download

## Single-frame variants

Any frame runs alone. The strongest solo frames:

| Frame | Headline | Primary text |
| --- | --- | --- |
| 01 hook | Get found by your work | Clients don't search for your name. They search for your nails. Tag your sets and every matching search brings them to you. |
| 06 no cut | We found them. They're yours. | Many booking apps charge you up to 30% of a new client's first visit when their marketplace finds them. We charge $0. Every visit. |
| 05 only pay | The only thing you pay for is the booking | Profile, gallery, getting found, call and text: free forever. Our booking tool is $10.99 a month, first month free. |
| 04 use some | Keep the booking tool you have | Already on Vagaro, GlossGenius or StyleSeat? Add your link and clients who find your work land there. Or they call. Or they text. |

## Claim check

- "Up to 30%" and "20% to 30%": StyleSeat 30% capped at $50, Booksy Boost 30%, Fresha 20% with a $6 minimum, all per new marketplace client. Checked 2026-09-20. Vagaro and GlossGenius do not charge one, which is why the slide says "many", not "most" or "all".
- Competitors are not named in the ad frames except frame 04, where naming them is the feature (the Book Now button links out to them).
- "Founding tech, locked for life" is left out, same as the email series, until the live page and the 2026-08-17 decision agree.
- No frame claims MNC is the only app with a marketplace. StyleSeat, Booksy, Fresha and Vagaro all have one.

---

# Set 2: Open today

Six frames, same two formats, files `png/feed-open-*` and `png/story-open-*`.

**Primary text:**

> Had a cancellation? Flip Open today and every one of your photos glows in the Gallery, you land in the Open today rail on the home screen, and you show up twice as often until midnight. No discount, no fee, free on every plan.
>
> We're filling the Gallery with techs first so clients never open an empty app. Client marketing comes next, and your photos never expire, so what you post now is still working when they arrive.

**Headline:** Your work glows when you're open

**Description:** Free to join. Open today is free, always.

**Call to action button:** Download

## What Open today actually does (from the app, 2026-09-20)

- Every photo gets a green ring and an OPEN TODAY banner in the Gallery (`.avail-glow-tile`).
- The tech appears in the Open today rail on the client home screen.
- Gallery weight doubles while it is on (`index.html`, availability boost, 2026-08-03).
- It clears itself every midnight. Open this week resets Sunday.
- If a tech flips it on with call, text and instant booking all off, the app warns her that today's clients have no way to reach her.

## Claim check, set 2

- Frame 4 compares ways of filling a gap, not named apps. Last-minute discounts: Booksy and Fresha. Automated waitlists: StyleSeat and Vagaro. Neither reaches new clients without a marketplace, which is where the 20% to 30% new-client fees apply.
- Frame 5 promises client marketing "next" with no date. That is a public commitment; Anne should be ready to point at it.
- The ad never says Open today fills a chair today. With the client side still small, it says the switch works and gets louder as clients arrive.
