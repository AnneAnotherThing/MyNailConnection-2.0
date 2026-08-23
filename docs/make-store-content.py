# Generate docs/STORE-CONTENT.md with REAL character counts.
#
# Why this exists (2026-08-23): the doc carried hand-written counts and its
# header promised "Every field below is inside its character limit". Two were
# not. The Play short description was labelled 74/80 and was actually 98, and
# Apple's promotional text was 175 against a 170 limit. Both would have been
# refused in the form, and the wrong label is exactly what stops anyone
# noticing — you trust the number and paste.
#
# Counts are now computed, and anything over its limit aborts loudly instead
# of being written to the file.
#
# Run: py -3 docs/make-store-content.py
import sys, pathlib

# ── Apple ────────────────────────────────────────────────────────────────
APPLE_NAME = "My Nail Connection"

APPLE_SUBTITLE = "Booking built for nail techs"

APPLE_KEYWORDS = ("nail tech,nail booking,nails near me,nail salon,manicure,"
                  "nail art,book nails,appointments")

# The ONLY App Store field editable without shipping a build. The offer lives
# here on purpose: when it changes, this is a browser edit, not a release.
APPLE_PROMO = ("Still booking in your DMs? Your work is already why clients pick you. "
               "Now it's your booking page too. First month free, then $10.99 - "
               "and no commission, ever.")

FREE_BLOCK = """FREE, FOREVER
Your profile, your whole gallery, and your place in the Gallery clients browse are free and stay free. Post up to 50 looks a month. Your photos never expire - this is a portfolio, not a feed that buries you in a week. Flip "Open today" so clients can see you have a chair right now. Keep your Call and Text buttons. Already booking somewhere else? Paste that link and a Book button appears on your profile. None of this ever costs you anything."""

TECH_LIST = """FOR NAIL TECHS
* Clients book you right in the app - approve each request, or auto-confirm
* Set your services, your hours, your buffer between sets and how much notice you need
* Standing appointments book your regulars automatically, every 1 to 4 weeks
* Add walk-ins and phone clients to your own calendar
* Automatic reminders go to your clients, so fewer no-shows
* Keep a private note on any client - only you ever see it
* Search your clients by name or number when you can't remember who's who
* Your own shareable profile link and QR code - your bio, your stories, your station
* Every photo you post lands in the Gallery, where clients browse by shape, type and style
* Notifications stay put, so a booking request you swiped away isn't gone"""

CLIENT_LIST = """FOR CLIENTS
Always free.
* Browse real sets from real techs, and filter by shape, type and style
* Find techs near you on the map, at whatever distance suits you
* See who is open today and book them before the chair fills
* Heart the looks you love and bring them to your appointment
* Get a reminder before your appointment"""

WHY = """WHY NAILS ONLY
A general beauty app has to describe a haircut, a lash fill and a full set in the same words. We don't. You tag your work by shape, type and style, and a client looking for almond chrome finds almond chrome - and finds you."""

OPENER = """Still booking in your DMs? Your work is already why clients pick you. Now it's your booking page too.

My Nail Connection is booking built for nail techs only. Not salons, not barbers, not everybody. Nails."""

# Apple requires the subscription's title, length, price and functional Terms
# and Privacy links in metadata the user sees before buying (Guideline 3.1.2).
# Omitting it is one of the most common subscription rejections.
APPLE_SUB_BLOCK = """SUBSCRIPTION DETAILS
Glow Up - booking on My Nail Connection: $10.99 per month, auto-renewing, with the first month free. Locked at that price for life as a founding tech. Payment is charged to your Apple ID at confirmation of purchase. The subscription renews automatically unless auto-renew is turned off at least 24 hours before the end of the current period. Manage or cancel any time in your Apple ID account settings. Your gallery and your calendar stay exactly as they are either way.

Terms of Use: https://mynailconnection.com/terms.html
Privacy Policy: https://mynailconnection.com/privacy.html"""

APPLE_PAID = """WHAT YOU PAY FOR
MNC's own booking - the part where a client taps Book and lands on your calendar. No commission. No per-booking fee. And never a charge to your clients."""

APPLE_DESC = "\n\n".join([OPENER, FREE_BLOCK, APPLE_PAID, TECH_LIST, CLIENT_LIST, WHY, APPLE_SUB_BLOCK])

APPLE_WHATS_NEW = """3.0: Real booking is here. Clients book you right in the app - no commission, no per-booking fee, and nothing charged to them. Your own shareable profile link and QR, standing appointments for your regulars, walk-in entry, private client notes, and automatic reminders so fewer people no-show. Notifications now stay put, so a request you swiped away isn't gone. Photos stay free - 50 a month, and they never expire."""

# ── Google Play ──────────────────────────────────────────────────────────
PLAY_NAME = "My Nail Connection: Booking"

# No price here on purpose: it renders tiny and it is the field most likely to
# go stale. The full description carries the number.
PLAY_SHORT = "Booking built for nail techs. No commission, no per-booking fee."

PLAY_PAID = """WHAT YOU PAY FOR
MNC's own booking - the part where a client taps Book and lands on your calendar. First month free, then $10.99/month, locked at that price for life as a founding tech. No commission. No per-booking fee. And never a charge to your clients."""

PLAY_CLOSER = """Free to set up. First month of booking free, then $10.99/month at the founding rate. Cancel any time; your gallery and your calendar stay exactly as they are."""

PLAY_DESC = "\n\n".join([OPENER, FREE_BLOCK, PLAY_PAID, TECH_LIST, CLIENT_LIST, WHY, PLAY_CLOSER])

PLAY_RELEASE = APPLE_WHATS_NEW

# ── Emit ─────────────────────────────────────────────────────────────────
FIELDS = [
    ("Apple App Store", [
        ("Name", APPLE_NAME, 30),
        ("Subtitle", APPLE_SUBTITLE, 30),
        ("Keywords", APPLE_KEYWORDS, 100),
        ("Promotional Text", APPLE_PROMO, 170),
        ("Description", APPLE_DESC, 4000),
        ("What's New in This Version", APPLE_WHATS_NEW, 4000),
    ]),
    ("Google Play", [
        ("App name", PLAY_NAME, 30),
        ("Short description", PLAY_SHORT, 80),
        ("Full description", PLAY_DESC, 4000),
        ("Release notes", PLAY_RELEASE, 500),
    ]),
]

over = [(s, n, len(v), lim) for s, fs in FIELDS for n, v, lim in fs if len(v) > lim]
if over:
    for s, n, ln, lim in over:
        print(f"OVER LIMIT: {s} / {n} is {ln}, limit {lim}", file=sys.stderr)
    sys.exit(1)

out = ["# MNC 3.0 Store Content — ready to paste",
       "",
       "GENERATED by docs/make-store-content.py — edit the copy there, not here,",
       "then re-run it. Counts below are computed, and the script refuses to write",
       "this file if any field is over its limit. Hand-written counts are what let",
       "a 98-character short description sit under a `74/80` label until 2026-08-23.",
       ""]

for section, fields in FIELDS:
    out += ["---", "", f"## {section}", ""]
    for name, value, limit in fields:
        out += [f"**{name}** ({len(value)}/{limit})", "```", value, "```", ""]

out += ["---", "",
        "## Panel order (both stores)",
        "1. Still booking in your DMs? (tech hook)",
        "2. Home — Everything starts here",
        "3. Gallery — Browse real sets",
        "4. Map — Find techs near you",
        "5. Find the look. Find the tech. Book them. (client hook)",
        "",
        "## Assets",
        "- Play feature graphic: `docs/play-store-assets/mnc-play-feature-graphic-1024x500.png` (1024x500, RGB, no alpha)",
        "- Play store icon: `docs/play-store-assets/mnc-play-icon-512.png` (512x512)",
        "- iOS app icon: ships INSIDE the build, `ios/App/App/Assets.xcassets/AppIcon.appiconset/`.",
        "  There is no upload field for it in App Store Connect.",
        "- Phone screenshots: shoot on a real device. Apple needs 1290x2796 (6.9\"),",
        "  Play needs 1080x1920 or similar 9:16. Signed OUT, light mode.",
        "",
        "## Category / misc",
        "- Apple category: Lifestyle (primary). Secondary was Social Networking, which",
        "  suited the 2.0 photo-feed pitch; Business fits a booking tool better.",
        "- Play category: Lifestyle / Beauty where available",
        "- Content rating: Everyone",
        "- Support URL: https://mynailconnection.com/",
        "- Privacy policy: https://mynailconnection.com/privacy.html",
        ""]

p = pathlib.Path("docs/STORE-CONTENT.md")
p.write_text("\n".join(out), encoding="utf-8")
print("wrote", p)
for section, fields in FIELDS:
    for name, value, limit in fields:
        print(f"  {section:<16} {name:<27} {len(value):>4}/{limit}")
