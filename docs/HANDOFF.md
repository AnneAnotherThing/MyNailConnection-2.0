# MNC 3.0 — Handoff Summary (as of 2026-07-15)

Paste this into a new chat to continue with full context.

---

## What this is
**My Nail Connection (MNC)** is Anne's nail-tech app. **3.0** is a pivot +
rebrand: discovery-first flopped, so the new model is **free booking as the
hook**, **photos paid and permanent** (they double as the tech's advertising),
**one Gallery**, launched under a new visual identity.

## Where the code lives
- **Repo (3.0 work):** `C:\Users\amwhi\repos\My Nail Connection 3.0` — this is
  a **git worktree on branch `v3`**.
- **2.0 maintenance:** `C:\Users\amwhi\repos\My Nail Connection` — branch `main`.
- **Deploy:** GitHub Pages Action publishes `deploy/ghpages/` ONLY on push to
  `main`. Nothing on `v3` can deploy. Cutover = merge `v3`→`main`, run
  `deploy/sync.sh`, Anne pushes `main` via GitHub Desktop.
- **The app is one giant file:** `index.html` (~18k lines, single-page).
  Edit big HTML via bash/python scripts, never risk Edit-tool truncation;
  always tail-check for `</body>` after edits; run `deploy/sync.sh`.
- **Local preview:** use the **`mnc3`** launch config (port 8123). Do NOT use
  `mnc-static`, that one serves the **2.0 repo** and will silently show you
  stale pages. Configs live in `C:\Users\amwhi\.claude\launch.json` (the
  repo-level `.claude/launch.json` is NOT what the harness reads).

---

## THE OLD BLOCKER IS RESOLVED (2026-07-15)

The old free DB (`ktiztunuifzbzwzyqrrq`) was never actually "asleep." The
dashboard showed **Unhealthy** + a **Disk IO budget** warning while still
serving ~46% of requests. The real reason nothing could connect was that
**the database password was stale**. Anne reset it in the dashboard and the
connection succeeded in **2.2 seconds**.

**Lesson worth keeping:** a pooler (Supavisor) error of
`password authentication failed` or `EAUTHQUERY: connection to database not
available` can look exactly like a dead project. Rule out the credential
before concluding the instance is down.

### The rescue is COMPLETE and verified. Everything lives in `rescue/`
(`rescue/` is **gitignored**, so it never lands in the public repo, which
matters because it holds password hashes.)

- `rescue/data/*.csv` — **61 tables**, all parse-verified against row counts.
  Includes `auth.users` (**66 logins, `encrypted_password` intact**),
  `public.techs` (28), and `storage.objects` (239).
- `rescue/data/_manifest.json` — table list + true row counts + column order.
  **Trust this over CSV line counts** (multi-line bios inflate line counts).
- `rescue/schema-fragments.sql` — **80KB of DDL**: 30 tables, 28 functions
  (incl. `create_booking` with its advisory lock), 80 RLS policies, plus
  constraints, indexes, triggers, views. This is the **real tested end-state
  from old prod**, which is a better artifact than replaying the migration
  files.
- `rescue/storage/tech-photos/` — **239/239 photo binaries, ~148MB**, pulled
  over HTTPS from the public bucket.
- Scripts: `pydump.py` (data), `grab_ddl.py` (schema), `storage_pull.py`
  (photos, resumable). All Docker-free.

**Tooling gotcha:** `supabase db dump` needs **Docker** (installed but not
running), and the only local `pg_dump` is **v10.7** vs a **v17** server, so it
refuses. Everything above was pulled with **psycopg**, which sidesteps both.

---

## The new home
- New project: **"My Nail Connection 3"**, ref `nwqnakoongrorbwnrqzc`, in the
  **Hive-Rise Pro org**, micro compute, us-east-1. Daily backups + real support.
- Auth URL config done — Site URL `https://mynailconnection.com/app/`;
  Redirect URLs `https://mynailconnection.com/app/**` and `http://localhost:8123/**`.
- **Still empty.** The restore has NOT been run yet.
- DB passwords are in Anne's password manager. Both the old (rotated) and new
  passwords were handed over in-session on 2026-07-15.

---

## WHAT'S BUILT (on `v3`, NOT deployed)

Everything from the prior handoff still stands (booking engine end-to-end
tested 11/11 on old prod, Tier 1 time-off/buffers/push reminders, standing
appointments, blocklist + pause switch, international/location-agnostic, the
splash/portal rebrand, dev-login tools).

### New, 2026-07-15 (UNCOMMITTED, prototypes)
- **`marketing-v3.html`** — the 3.0 marketing page. Hero rebranded to the
  hat-lady-on-ivory identity (text left-anchored, capped 620px; magnolia
  flowers and the rose-gold logo removed). Model copy corrected throughout:
  feed and posts removed, Standing Appointments card added, Glow Up fixed to
  **40 uploads/month**, photos framed as permanent, one Gallery.
- **`tech-guide-v3.html`** — the 3.0 tech guide. Full rose-gold→mauve palette
  swap. Step 2 "5 free photo slots" → "your first photo is free" (+ the
  grandfather note). **Step 4 rewritten**: it previously said *"MNC doesn't
  handle bookings"*, the exact opposite of the 3.0 pivot; it now covers
  services/hours/auto-confirm. Step 6 Posts → **Standing Appointments**.
- Build scripts kept as a record: `build_v3_marketing.py`,
  `build_v3_techguide.py` (repo root).
- `marketing-v3.html` links to `tech-guide-v3.html`.

---

## DECIDED (Anne, 2026-07-15)
- **The customer is the TECH, not their client.** `marketing-v3.html` is
  repositioned accordingly: hero is now the locked pivot line **"Still booking
  in your DMs?"**, primary CTA is **"Set up my free book"**, For Techs now
  precedes For Clients, nav reordered, and title/description/keywords/OG/
  schema.org are all tech-first. The schema had described MNC as a
  **"discovery platform"** (the model that flopped) and an FAQ answered
  *"No, MNC doesn't replace how clients reach you"*, the same wrong framing as
  the old tech-guide step 4. Both fixed. Client SEO was not a real loss:
  "nail techs near me" is local-intent, owned by Maps/Yelp, and was never
  winnable for a small app site.
- **Glow Up = 25 uploads/month.** Not 40, never "unlimited". Photos are
  permanent by promise, so unlimited uploads is unbounded storage that can
  never be reclaimed. Applied to marketing-v3, tech-guide-v3, and
  transparency-copy.md. Note the tradeoff: at 25, Glow Up is $0.44/photo vs
  $0.50 on the 10-pack, only ~11% off, so Glow Up sells on convenience, not
  price. A typical tech uploads well under 25/month, so the cap only bites
  outliers, which is the point.

## OPEN QUESTIONS FOR ANNE
1. **Voice.** HANDOFF says client copy is first-person singular ("I/me");
   `transparency-copy.md` uses "we". The v3 pages stayed neutral
   product-voice rather than pick.
2. **The For Clients section** still reads as 2.0 client-discovery copy. It
   now sits second, which is right, but nobody has decided how hard it should
   work now that clients arrive via their tech's shared link, not via search.

## STILL TO BUILD
- **`marketing.html` is in a broken hybrid state** in the working tree
  (mauve colors + 2.0 copy) from an earlier uncommitted pass. It is neither
  2.0 nor 3.0. Everything in it is superseded by `marketing-v3.html`, so it's
  safe to revert to committed 2.0 until cutover.
- ~~og-image~~ **DONE 2026-07-15**, see below.
- ~~favicon + app icons~~ **DONE 2026-07-15**, see below.
- ~~Waitlist~~ **REVIVED and BUILT 2026-07-15.** The 2026-07-07 pivot had killed
  it ("COUNTDOWN AND WAITLIST BOTH DEAD"), but Anne explicitly asked for one on
  the 2.5 teaser. Her call supersedes the pivot on this point. See below.
- **Two-path tech signup** — "I need booking" vs "I book elsewhere".
- **Finish auth config** on the new project: email templates (reset uses
  `/app/?token_hash=...&type=recovery`; signup confirm uses `type=email` NOT
  `type=signup`), leaked-password protection, min length 8+.

---

## RESTORE STATUS (2026-07-15 night) - DB IS RESTORED

New project `nwqnakoongrorbwnrqzc` now holds the full 3.0 database.
**Pooler host is `aws-0-us-east-1`** (the OLD project is `aws-1`; using the
wrong one gives a confusing ENOTFOUND-style failure).

DONE and verified:
- **Schema: 298/298 statements, 0 failures.** Exact parity with old prod:
  30 tables, 28 functions, 80 RLS policies, 71 constraints, 83 indexes,
  3 triggers, 4 sequences.
- **Public data: 30/30 tables match the rescue manifest.**
- **auth: 66 users + 66 identities**, 0 missing password hashes, 0 orphans.
  Deliberately NOT restored: sessions, refresh_tokens, mfa_amr_claims,
  one_time_tokens, audit_log_entries. They are signed against the OLD
  project's JWT secret and are meaningless here. Everyone re-logs in once
  with their existing password. `confirmed_at` is a GENERATED column and
  recomputes itself (that's why the CSV has 34 cols vs the table's 35).
- **Bucket `tech-photos` created** (public), matching old config.
- **Storage policies HARDENED.** The old project granted INSERT/UPDATE/DELETE
  on storage.objects to role `public`, i.e. anyone holding the anon key (which
  ships in index.html) could delete or overwrite ANY tech's paid, permanent
  photos. New policies: reads `public`, writes `authenticated`.
  **If photo upload breaks in testing, this is the first thing to check**
  (revert = grant the write policies back to `public`).

THREE BUGS CAUGHT DURING THE RESTORE, do not reintroduce:
1. **`truncate ... CASCADE` per table silently wiped already-loaded data.**
   Tables load alphabetically, so truncating `techs` (13th) cascaded and
   emptied `bookings`, `tech_availability`, `tech_services` which had already
   loaded. Each had reported "OK" at insert time. Only a post-load count check
   against the manifest caught it. Never CASCADE mid-load.
2. **Sequences were unowned and left at 1.** grab_ddl.py emits
   `create sequence if not exists`, which creates them standalone, so the
   pg_depend ownership link is missing and a resync keyed on pg_depend finds
   nothing. `marketing_hits` had 697 rows and its sequence sat at 1, so the
   next insert would have thrown a duplicate key. Fixed via column DEFAULT
   (`nextval`) lookup + setval + `alter sequence ... owned by`.
3. **`ALTER TABLE ... VALIDATE CONSTRAINT` proves NOTHING here.** It is a
   no-op on constraints that are already VALID, so it returns success without
   checking a single row. It reported "14/14 valid" while a real orphan
   existed. Check integrity by querying for orphans directly.

## PHOTOS: DONE (2026-07-15 night)
- **239/239 uploaded** to the new `tech-photos` bucket, 154.5 MB, 0 failures.
  Verified by fetching sampled files PUBLICLY (no auth) at the exact original
  byte size + mime type. `rescue/upload_photos.py` reads the key from env
  `SB_KEY` (never written to disk); re-runnable, it upserts.
- **68 stale photo URLs rewritten** old ref -> new ref across all 8 columns.
  A full re-scan of every public column shows ZERO remaining old-project refs.
- Live-fetch check straight out of the restored DB: photo URLs load from the
  new project.

### Two pre-existing oddities found, NEITHER caused by the migration
- **5 photo URLs point at `buildfire-proxy.imgix.net`** (leftovers from the old
  BuildFire platform), affecting Acrylic Bliss Nails, Rustic Nails By Caity,
  Izzy, Katie Daugherty. All 4 still load today, but they live on a third-party
  CDN Anne does not control and were NEVER part of the 239 rescued files. If
  BuildFire kills that proxy those images vanish and we have no copy. Worth
  re-uploading into our own bucket at some point.
- **1 dangling reference**: user_inspo -> gallery/monica-mynailconnection/
  1778116337077-nkbl4.jpg. Already 404 on the OLD project and absent from the
  old storage inventory, so the row was orphaned long before the move. The
  migration faithfully reproduced it. Delete the row or ignore.

## KEY SWAP: DONE (2026-07-15 night)
The app now points at the NEW project. Swapped BOTH the project URL and the
anon key in **12 source files**, not the 4 the old handoff listed:
admin-feedback, admin-stats, founders, index, marketing, marketing-v3,
punch-list, reset-password, stats, tech-guide, tech-guide-v3, and
supabase/functions/revenuecat-webhook/index.ts. A repo-wide grep of source
shows ZERO remaining old-project refs. All touched HTML passed the `</body>`
truncation guard; all real JS blocks pass `node --check`.

Verified live against the new project with the anon key exactly as index.html
holds it:
- `GET /rest/v1/techs` -> **200**, returns real tech names.
- `GET /rest/v1/users` -> **200 []**, RLS correctly blocks anon reads.

Security check done: only ONE distinct JWT was ever embedded in source (the
anon key). No service_role key has ever leaked into client code.

Note: `node --check` reports a false error on marketing-v3's first script block
because it is `application/ld+json` (JSON, not JS). It parses fine as JSON.

## GLOW UP 25: NOW ENFORCED END-TO-END (2026-07-15 night)
Anne spotted that the app still referenced the old photo allowances. She was
right, and the copy change alone was NOT enough. **40 was hardcoded in 3 live
places** while marketing already promised 25, i.e. a tech would read "25" and
silently be granted 40:
- `index.html` `STRIPE_CONFIG.monthly_limit` -> now **25**
- DB `consume_upload_slot()` `v_period_cap := 40` -> now **25** (server-side
  enforcement, this is the one that actually matters)
- DB `peek_upload_slots()` `coalesce(c.monthly_limit, 40)` -> now **25**
Also fixed the user-facing "You have used all N of this month's uploads" modal,
which read 40, and the `|| 40` subscriber fallbacks.
Source of truth updated too: `sql/free-upload-counter-fix.sql`.

**Comped techs are GRANDFATHERED at 40 on purpose.** `tech_comps.monthly_limit`
is stored per row: 17 rows hold 40, one holds 999. Those rows are untouched, in
keeping with Anne's own grandfathering principle. Only the *column default*
moved to 25, so NEW comps get 25. The three remaining `40`s in index.html
(~2916, ~2939, ~2958) are the comp path and are correct; they are annotated so
nobody "fixes" them.

### On "the first 5 are free" (Anne's question, answered)
That reference is CORRECT and intentional, not a bug.
`PHOTO_FREE_CUTOVER = '2099-01-01'` is parked in the future, so every existing
tech counts as pre-cutover and keeps the grandfathered 5. `NEW_TECH_FREE_PHOTOS
= 1`. On launch day set `PHOTO_FREE_CUTOVER` to the real launch date and new
techs drop to 1 free while everyone already on the platform keeps their 5. The
localhost-only "DEV - New pricing" chip previews the post-cutover behaviour.

## STATE DROPDOWN RESTORED / INTERNATIONAL PARKED (2026-07-15, Anne's call)
International is on hold because it cannot be tested (all 28 techs are US).
The state field is a **US dropdown again** in both LIVE forms, restored
verbatim from `5d4e6d8^` (the "international location pass" commit):
`reg-state-field` (signup, ~line 1332) and `ue-state` (user-edit, ~17967).
51 options each, values are 2-letter codes with "AZ, Arizona" labels.

**This makes the address stack coherent again**, which was the real problem:
- The dropdown stores 2-letter codes, which is exactly what `stateAbbr()`,
  `stateFull()` and `addrSelect()` already assume. `stateFull()`'s comment
  about "state dropdowns" is accurate once more.
- `addrSelect()`'s `postcode.slice(0,5)` is now CORRECT, not a bug: US ZIPs
  really are 5 digits (it just trims ZIP+4). Do not "fix" it while US-only.
- Verified live: writing `'AZ'` sticks and renders "AZ, Arizona"; writing
  `'Arizona'` silently BLANKS the field. So `addrSelect`'s coercion to
  2-letter is now load-bearing, not contradictory.
- Data check: every stored state in techs / users / archived_techs is already
  a valid 2-letter code, so nothing blanks on edit. No migration needed.

**`te-state` UPDATE (2026-07-16): the "deliberately NOT restored" call below
was WRONG and is now REVERSED. See "TECH EDIT MODAL RESTORED" further down.**
The reasoning here assumed `openTechEdit()` was unreachable admin dead code.
It was not. The tech-edit modal is the tech's OWN profile + photo editor, not
an admin surface; it was authored inside `#admin` and removed as collateral
damage. `te-state` is now restored AS A US DROPDOWN (not the old free-text
input), matching `reg-state-field` / `ue-state`, precisely because the address
stack assumes 2-letter codes. Original (now-superseded) note kept for history:
~~`te-state` belongs to the admin panel... unreachable dead code... was always
a plain text input, never a dropdown.~~

If international is ever revived: the blockers are no `country` column, the
`slice(0,5)` truncation, and hardcoded "Within 5 mi" labels at ~7054.
`mncFmtDist()` already converts to km off `navigator.language` and is harmless
to leave.

## HAT-LADY ICON SET + HERO LINE FIX (2026-07-15)

### The "hard line" was baked into the artwork, not CSS
`images/mnc-lady.png` had a **1px dark line** on its right edge; the 800px
master `marketing/brand/mnc-3.0-logo-hat-lady.png` had **2px** (100% dark
columns at x=798,799). No mask or CSS tweak could ever have fixed it. Cropped
off the master (original preserved as `mnc-3.0-logo-hat-lady.orig.png`).
Also dropped `mix-blend-mode: multiply` from `.hero-art img`: multiplying the
art's ivory background against the ivory hero DARKENED it into a visible
rectangle. The two ivories are near-identical, so normal blending makes the art
sit invisibly. Hero now uses **`images/mnc-lady.webp` (23KB vs 447KB PNG)** at
798x697, so it is no longer upscaled from 400px either.

### Icons: TWO crops on purpose
The hat-lady does not survive a single scaled crop, so:
- **Favicon (16/32/48 + mncLogo-32/64.webp): TIGHT crop** `(130,95,470,415)`,
  hat brim + eyes + lips. Tested at 32px magnified against 2 alternatives; the
  full lady turns to noise (the hand becomes speckle) and a tighter crop loses
  the hat's diagonal sweep.
- **App icons (apple-touch 180, mncLogo-180/192/512/1024, round-256/512):
  FULL lady** `(35,25,675,600)`, hat + face + lips + nails. Beautiful at 180px+.
- **Maskable (512)**: FULL lady with 16% padding. Verified against a simulated
  80% safe-zone circle: only 7.5% of the hat's ink falls outside (its corners,
  which are meant to bleed); face and lips sit well inside.
- Regenerate any time with `python make_icons.py` (repo root).

**Honest limitation:** at **16px** this artwork is a dark blob with a pink
smudge. That is inherent to a detailed line drawing, not a crop problem. The
180px+ app icons are where she shines, which is the right trade since PWA/home
screen matters most.

**Bug caught:** PIL writes ONLY a 16x16 entry if you save a `.ico` from an
already-16px image. Save from a large image and pass `sizes=[...]` so PIL
downsamples. Verified: favicon.ico now holds 16/32/48 and all three load.

### manifest.json was still rose-gold
`theme_color` **#C4786A -> #BFA6BB**, `background_color` **#FAF5F7 -> #EDEAE5**.

## HERO BUTTONS + FULL ROSE-GOLD PURGE (2026-07-15, Anne spotted it)

Anne: "I'm looking for a tech button needs contrast" and "Set up my free book is
in rose gold still." Both were dark-hero leftovers, and chasing them found a lot
more. The earlier palette pass only swapped the CSS *variables*; every
**hardcoded gradient** survived.

**Hero buttons (marketing-v3), measured live:**
- `.btn-primary` "Set up my free book": was `linear-gradient(#D4908A,#A9665D)`
  (terracotta). Now **black** convex-by-light `#34303A -> #141317 -> #0B0B0D`,
  blush text. Text contrast **11.09**, boundary vs hero **16.39**.
- `.btn-outline` "I'm looking for a tech": was cream `#F5EDE8` text on
  `rgba(255,255,255,0.14)`, built for the DARK hero, so on ivory the SURFACE
  scored **1.03** vs the hero, i.e. invisible (its text was always readable, the
  button shape was not). Now **mauve** fill + **solid deep-mauve `#7D6478`
  keyline**. Text **6.99**, boundary **4.41**. The keyline is doing the work: a
  mauve fill alone only reaches ~1.6 vs ivory because it reads by hue, not
  lightness, and WCAG wants 3:1 for a control edge.
- Both convex-by-light, no keyline rings, per Anne's stated button preference.

**Everything else that was still 2.0:**
- **tech-guide-v3 `.hero` was dark TERRACOTTA** `#3D1F1A -> #6B3228`. The whole
  "Get seen. Get booked." hero was still 2.0. Now black/deep-mauve.
- tech-guide `.final-cta` (same brown) -> black/deep-mauve; its `.cta-btn`
  inverts to a light blush face on the dark section; `.nav-cta` -> black;
  progress dots -> mauve gradient.
- marketing `.final-cta` warm peach -> blush/ivory; announce-banner peach stop
  -> deep-mauve; footer heart + `.store-btn-tag` salmon `#F0B0A5` -> mauve;
  petal/confetti JS colour array re-palletted; `#E8907E` salmon headings on the
  dark showcase -> mauve; warm whites `#FDF5F2`/`#F5E8E4` -> blush/ivory.
- marketing's `.nav-cta`/`.waitlist-form`/`.popin-form` are **dead CSS (0
  usages)** but were rebranded anyway so the rose-gold can't come back.

**Verified:** a full DOM scan of every painted colour finds no 2.0 warm palette
left. The only warm colours remaining are 4 deliberate vivid feature-icon chips
(`#FF6B8A/#E8376A` pink, `#FFD166/#FF9F1C` gold) — accent chips, not rose-gold.
Leave or restyle on request.

**Lesson:** swapping palette VARIABLES misses hardcoded gradients entirely.
For any rebrand, scan *painted* colours in the browser, not just `:root`.

## OG-IMAGE + WEB BUTTON + MNC-ON-BRIM FAVICON (2026-07-15)

### og-image.png rebuilt (`python make_og_image.py`)
The old card was fully 2.0: the rose-gold **hand+flower** mark (the RETIRED 2.0
logo), warm peach, and "Find Your Tech. Love Your Nails." — so every social share
advertised the old logo AND the client-first positioning we just abandoned.
New card mirrors the hero: text LEFT on ivory, hat-lady bleeding off the RIGHT
with a 110px left fade (190px smeared the black brim into grey). Copy is the
locked pivot line "Still booking / in your DMs?" + "Free booking for nail techs,
forever. Your work is your booking page." + chips (No commission / No
per-booking fee / Nails only). Real brand fonts from `marketing-slides/`.
Original preserved at `marketing/brand/og-image-2.0-original.png`.

### "Use on Web" PWA button (Anne's request)
Third button in BOTH store rows (hero + footer): globe icon, "NO INSTALL /
Use on Web", -> `https://mynailconnection.com/app/`. Absolute URL on purpose:
`/app/` only resolves in the deploy bundle, not the local preview where the app
IS root. While there: `.hero .store-btn:hover` was **`#4D2A23` (brown)** with
warm brown shadows — rose-gold hiding in a `:hover`, which a static DOM colour
scan can never catch. Now black.

### Favicon: MNC on the brim
Anne's idea, and it fixes the legibility limit I'd flagged: the hat is the one
shape that survives small, so the wordmark ON it is what makes the favicon
readable. `marketing-slides/PlayfairDisplay.ttf` is a **VARIABLE font (weight
400-900)** — 400 is the brand wordmark weight but its thin serifs disintegrate
small, so the favicon uses **700**, size 64, y=75, tracking 10, blush `#F7EBEE`
on the solid full-width brim band (y~40-115 of the TIGHT crop). Verified by
decoding the real 32px PNG: wordmark ink confirmed on the dark brim. Reads
clearly at **48 and 32px**; at **16px** the three letters mush (~10px of type, a
physical limit, not a crop problem) but the hat+lips silhouette still reads.
Browsers use 32px for hi-DPI tabs, so it lands where it counts.
App icons (180px+) deliberately have **no** wordmark — she asked for the favicon.
Offer it for the app icon if she wants home-screen consistency.

## THE GALLERY STRIP -- the page finally shows the product (2026-07-15)
Anne un-deferred the pics ("YES!! the pics!!"). The page described an app for
browsing nail work and booking, and showed neither; this fixes that.
`#the-gallery` sits right after the hero: a black band, a slow 64s marquee of
**real sets from real techs**, ends feathered so it reads endless, pauses on
hover. **One tile carries the Available-Now glow + pill, so the perk is
demonstrated rather than claimed.**
- Source: the rescued originals in `rescue/storage/`, re-cut to 440px square
  webp in `images/gallery/g01..g10.webp` -- **288KB for all ten**, vs originals
  up to **2.9MB EACH**. 10 unique tiles, duplicated in markup for a seamless
  loop. Lazy-loaded. `prefers-reduced-motion` stops the scroll.
- **Curated by eye, not picked blind.** I built a contact sheet of 20 candidates
  and looked. Excluded: two **pedicure/toe** shots (wrong lead image for a
  homepage) and a **Halloween gore** set ("SAW", blood spatter -- bold but
  seasonal and divisive). Excluded all **test-account galleries**
  (`apple-review`, `ios-test-user`, `test1234`, `sara-tester`, ...) which would
  otherwise have shipped. Kept work that sits with the black/mauve/blush palette.
- Featured techs: laura-ortega, faith-at-marshels, maria-alejandra-osorio-de-macias,
  esperanza-figueroa, ana-soto, leslie-flores.

**FLAG FOR ANNE:** these are real techs' photos, used as marketing. It is aligned
with the locked model (photos are public, permanent ads, and this is free promo
for them) and the bucket is public, but featuring *specific* techs on the homepage
is her call. Swap any tile by dropping a new `images/gallery/gNN.webp`.

## STILL DEFERRED
- ~~The `app-screens/` phone screenshots still show the **ROSE-GOLD app** and are
  still used by the dark showcase section.~~ **RESOLVED 2026-07-17:** Anne asked
  to remove that section ("See It In Action / Beautiful by design / Powerful by
  default"). The whole dark screenshot-showcase `<section>` was deleted from
  `marketing-v3.html` (71 lines), which removed the last use of the rose-gold
  `app-screens/` on the page. Verified: 0 `app-screens/` refs remain, sections
  6/6 + divs 136/136 balanced, `</html>` intact, no console errors, page flows
  cleanly into the quote + final CTA. Backup: `scratchpad/marketing-v3-before-showcase-remove.html`.
  (`marketing.html` and the `deploy/` bundles still contain the old section, but
  they're superseded, marketing-v3 -> marketing.html at promotion regenerates them.)

## HERO SPACING FIX + THE 2.5 TEASER PAGE (2026-07-15)

### Hero: dead space at wide, overlap on mobile (Anne spotted both)
- **Wide:** the copy was pinned to the left padding while the art was pinned to
  the VIEWPORT's right edge, so they flew apart as the screen grew, **628px of
  dead ivory at 1900px**. Both are now capped inside a **1280 content track**
  (`padding-left/right: max(clamp(...), calc((100% - 1280px)/2))` and the art's
  `right` follows the same track). Gap at 1900px: **628px -> 60px**.
- **Mobile:** the lady sat BEHIND the headline at 30% opacity, which read as
  overlap. Now the hero **stacks**: copy first, lady below as a real element at
  full opacity. Measured vertical overlap: **0px**, no horizontal overflow.

### `mnc-2.5.html` — the teaser (NEW, standalone)
Anne: "is there a 2.5 mnc page we can use for a few days to drum up interest?
like maybe our old logo morphing into our new one... and have a waitlist" +
**"don't mess up on new one"** — so it is a SEPARATE file that shares nothing
with `marketing-v3.html` (only `images/morph-*.webp`). marketing-v3 verified
untouched afterwards.
- **The morph**: 2.0 rose-gold hand+flower plaque melts into the 3.0 hat-lady
  (blur + scale + halo bloom, 9s loop), reusing the treatment from
  `campaign-assets/countdown/logo-melt.html` (which is a 9:16 SOCIAL asset for
  Leslie to screen-record, not a web page). Both marks are square 512s so they
  register exactly, verified aligned with transforms removed. Assets:
  `images/morph-2.0.webp` (84KB, down from logo-2.png's **1.6MB**) and
  `images/morph-3.0.webp` (14KB).
- Copy runs "You loved 2.0." -> "3.0 is even better." then the locked pivot
  headline. Honours `prefers-reduced-motion` (jumps straight to the 3.0 mark).
- **Waitlist** -> `public.launch_waitlist` on the **NEW** project. Deliberate:
  the page is standalone, so it can use the healthy backed-up DB regardless of
  where the app is pointed during cutover. `source: 'teaser-2.5'`.
- **Tested live end-to-end:** insert **201**; duplicate **409** (the UI treats
  that as success = "already on the list", matching the PK on email); and
  crucially **anon SELECT returns `[]`** — the anon key is public in page
  source, so RLS is what stops anyone scraping the emails. Test row deleted;
  table back to its original 10 rows.
- **noindex** on purpose: a page that lives for a few days should not linger in
  or compete in search. Sharing is unaffected.

**TO SHIP IT** (not done, needs Anne's call): the teaser is self-contained, so
it can be copied to the **main** worktree and pushed WITHOUT merging v3 — which
matters, because merging v3 into main would also ship the app now pointed at the
new DB and strand native users. It also needs adding to `deploy/sync.sh`.

## HERO STORE BUTTONS SHRUNK (2026-07-15, Anne: "make the app buttons smaller")

Adding the third (Use on Web) button exposed that they were oversized:
**230x78 each**, so three in a 620px column **wrapped onto two lines**, and at
78px tall they stood **taller than the primary CTA (58px)** — the download
buttons literally outweighed "Set up my free book". Hierarchy inverted.

`.store-btns--mini` was on the hero row but only ever set `justify-content`, so
the name was a lie. It now actually shrinks: padding 9/17, icon 16px, small
8.5px, strong 13.5px, gap 10px.

**The trap:** the base `.store-btn` pins **`min-width: 230px`**, which silently
overrode every size reduction — padding and fonts all shrank while the width sat
at 230 and the row kept wrapping. Fixed with `min-width: 0` on the mini variant.

Result at 1440px: **~140x49 each, all three on ONE line** (was 230x78 over two),
now shorter than the CTA, and still >=44px tall so the tap target survives.

Mobile is unchanged by design: line ~1210 `@media (max-width: 768px)` already
stacks store buttons column/full-width (max 320px). That is pre-existing and
intentional; the mini sizing still applies so they are 49px tall there instead
of 78px.

**Footer store row left at full size on purpose** (230x78 desktop): it is the
final download CTA, not the hero, where bigger is appropriate. Shrink on request.

## HERO ART -> RAISED CARD (2026-07-15, Anne: "love the lady on 2.5, do that
## for main v3, the raised card")

The hero art is no longer a bleeding, mask-faded landscape image. She is now a
**square raised card** matching the 3.0 mark on `mnc-2.5.html`: rounded 30px
corners, lifted shadow, plus a soft mauve halo echoing the teaser's bloom. All
the masking is gone, so there is no smeared brim and no fade to tune.
- New asset **`images/lady-card.webp`, 900x900, 30KB** (the teaser's card is only
  512px, too small for a hero on retina; the old `mnc-lady.webp` was landscape).
- Sits inside the same 1280 track as the copy. At 1440px: **420x420 card**, 240px
  clear of the text, no overlap.
- Mobile: **293x293**, centred under the copy, 0px overlap, radius 26px.

**Bug caught:** the card rendered **293x298** on mobile, i.e. not square despite
`aspect-ratio: 1`. Cause: `<img>` defaults to `display: inline` with
`vertical-align: baseline`, so phantom descender space stretched the container
and defeated the aspect ratio. Fixed with `display: block`. Worth remembering,
it silently breaks any aspect-ratio box wrapping a bare `<img>`.

`images/mnc-lady.webp` / `.png` are now unused by marketing-v3 but are still
referenced elsewhere (admin-stats), so they were NOT deleted.

## COPY: OBJECTION-KILLER + THE AVAILABLE-NOW PERK (2026-07-15, Anne)

- **Hero sub closing line.** Was "Nails only, nothing else bolted on." Now
  **"Already book somewhere else? Keep your link, nothing to switch."** Matches
  the phrasing already used in tech-guide step 4 and the FAQ ("Already book
  somewhere else? Keep it"). Better line: the old one was a feature claim, the
  new one kills the objection that stops the Vagaro/Booksy crowd cold ("I'm not
  migrating my whole book"). "Nails only" survives in meta/og/og-image chips.
- **For-Techs card 03** was a description of a toggle ("Toggle Available Right
  Now... clients will see you first"). Now sells the perk Anne asked for:
  **"Had a Cancellation? Fill It Today."** — a no-show used to be money gone;
  flip Available Now, your work GLOWS in the Gallery exactly when people who
  need nails today are looking, and the empty 2pm turns back into a booking.
- **De-duplicated the glow**: card 06 was repeating the Available-Now line,
  splitting the idea across two cards. 03 now owns it; 06 sticks to the
  photo-count algorithm and carries Anne's ad-spend angle ("nobody can outspend
  you into invisibility, presence tracks your work, not your budget").

**Possible next**: the og-image still has a "Nails only" chip. Swapping it for
"Keep your link" would put the objection-killer on every share. Anne's call.

## HERO MOTION: "BOOKINGS LANDING" + DEAD-CSS PURGE (2026-07-15)

Anne: "how can we animate or improve... we need something." First finding: the
page was **not** inert. Scroll reveals already work (IntersectionObserver, 12
targets, verified firing) and the marquee runs. **Only the hero was static** (a
badge dot and a sparkle).

Second, and more useful: the real gap was not motion, it was **proof**. The hero
asks "Still booking in your DMs?" and then shows a portrait, which never answers
the headline. Nothing on the page shows the product doing anything. The obvious
fix (app screenshots) is exactly what Anne deferred, because they are all still
rose-gold.

**Built (Anne chose it): "bookings landing".** Three chips cycle near the lady
card on a 12s loop, styled like real app notifications:
`New booking · Thu 2:00` / `Standing appointment · renewed` /
`Available Now · you're glowing`. They answer the headline by showing the
alternative arriving, need no photos, and keep the card she likes. Decorative
(`aria-hidden`, `pointer-events:none`), and `prefers-reduced-motion` collapses
them to a single static chip.

**Collision, caught and fixed:** the chips overhang the card's left edge toward
the copy. At **1160px all three overlapped the text** (the text/card gap is only
26px there). Rule is `gap > overhang + margin`, so they are gated to
**min-width: 1300px** and the overhang trimmed to <=20%. Verified by sweeping
**nine widths (1120 -> 1900)** in an iframe: hidden below 1300, clearance
38px -> 156px above it, zero collisions. **Spot-checking one width is how I
missed it the first time.**

**Dead CSS purged: 35 blocks, 169 lines, 6.2KB (119.7 -> 113.6KB).**
All orphaned: the `hero-magnolia` / `mag-*` flower rules + 6 keyframes
(`petalUnfurl`, `budOpen`, `leafSpread`, `petalSway`, `centerFade`,
`branchGrow`) left behind when the magnolia SVG was removed from the hero, plus
`waitlist-form` / `popin-form` / `waitlist-pop` (0 markup usages). Verified
after: hero, card, both CTAs, store buttons, tech + price cards, marquee, all 12
scroll reveals, and the pings all unchanged. Backup of the pre-cleanup file is in
the session scratchpad.

**Still the honest gap:** no product is visible anywhere on the page. When Anne
un-defers the pics, the strongest single addition is a real Gallery strip (the
239 rescued photos are sitting in `rescue/storage/`) and/or a non-rose-gold app
screenshot.

## PUSH NOTIFICATIONS WERE 100% DEAD, NOW FIXED (2026-07-15) -- BIG ONE

Anne: "we need for the app to actually do those push notifications!" She was
right. The app sent **zero** push, for three stacked reasons.

**1. Nobody was ever subscribed.** The post-login code fetched
`/users?email=eq...&select=role,image_url` -- **`id` was never SELECTed** -- then
did `if (row.id) showPushPrompt(row.id)`. `row.id` was always `undefined`, so the
guard never passed and the subscribe prompt NEVER ran. Proof: `push_subscriptions`
had **0 rows in old production**. This was never "the VAPID key didn't survive the
move"; there was never a single subscriber.

**2. Senders disagreed with each other.** Booking pushes passed **emails**
(`b.client_email`, `tech.email`) while admin pushes passed **UUIDs**
(`me.id`, `u.id`) and Contact-Anne passed `ANNE_USER_ID`. `send-push` does
`.eq('user_id', user_id)` against ONE column. The file even contradicted itself:
line ~13077 said "their push subscription is keyed by email" while line ~14250
said it's "the users-table UUID".

**3. The UUID was ambiguous anyway.** `public.users.id` and `auth.users.id`
disagree for **63 of 66** accounts (the ID-mismatch landmine, now measured).

**THE KEY IS NOW LOWERCASED EMAIL, EVERYWHERE.** Chosen on evidence:
`lower(email)` is unique in auth.users (66/66) and public.users (66/66), resolves
every tech (28/28), 0 non-lowercase emails, and the DB reminders **already**
passed emails. `push_subscriptions.user_id` is `text` and the table is EMPTY, so
the switch cost zero migration. All writes/reads go through a new `pushKey()`
helper. `ANNE_PUSH_EMAIL = 'anne@mynailconnection.com'` (verified = ANNE_USER_ID).

### Two MORE migration gaps found while in there
- **`_booking_push()` hardcoded the OLD project URL *and* the OLD anon key.** My
  earlier URL rewrite only scanned table DATA, never function bodies. Repointed.
  Verified: **0 of 28** DB functions now reference the old project.
- **All 4 pg_cron jobs were missing** -- my schema dump only covered `public`,
  and cron jobs live in `cron.job`. Recreated and active:
  `booking-reminders` (*/15), `reset-available-now` (0 0 * * *),
  `reset-open-this-week` (0 0 * * 0), `standing-extend` (0 9 * * *).
  Without these: **no reminders ever fire, techs stay "Available Now" FOREVER**
  (killing the perk we just marketed), and **standing appointments silently stop
  extending** -- the flagship feature.

### STILL NEEDS LIVE VERIFICATION (cannot be tested from here)
Push needs the **edge functions deployed to the new project + VAPID secrets set**
and a **real device**. The code path is fixed and consistent; delivery is unproven.
Test: log in (prompt should now appear ~4s in), confirm a `push_subscriptions` row
appears keyed by your email, then make a booking.

## MARKETING: the pings now STACK (Anne's ask)
Six chips, each lands with a small pop then **stays** while the next arrives, so
they pile up ("the bookings keep coming") rather than replacing each other; the
pile clears and loops (20s). Staggered lefts so it reads hand-dealt, not a rigid
column. Re-swept **7 widths (1240-1920)**: hidden below 1300, clearance 38-156px,
no overflow, and no ping overlaps another. `prefers-reduced-motion` shows 3 static.

## THE GALLERY IS NOW A LIVE FILTER DEMO (2026-07-15, Anne's idea)

Anne asked for tags, a filter being applied with the photos changing, more pics,
opposite directions, and multiple Available-Now indicators. Built, and the key
decision was **honesty**: the tags are the techs' OWN tags straight out of
`techs.photos`, never invented.
- **Two rows counter-scrolling** (70s / 84s, opposite directions), ends feathered,
  pause on hover. 23 unique tagged photos, duplicated -> 46 tiles.
- **8 filter chips** of real in-use tags (Square, Acrylic, Nail Art,
  Bling/Rhinestones, Coffin, French Manicure, Almond, Solid Color). They
  auto-cycle while the section is on screen; hover/click takes over.
  Non-matching tiles **dim + desaturate**, matching tiles pop and reveal that
  tech's real tag. **All 8 filters verified**: hit/dim counts match the tag data
  exactly for every chip.
- **4 tiles carry the Available-Now glow** (Anne asked for multiple).
- Assets: `images/gallery/g01..g23.webp`, 420px, **424KB total**.
  Runs only while visible (IntersectionObserver); `prefers-reduced-motion`
  stops the scroll and softens the dim.

### The demo exposed a REAL product problem, not just a marketing one
**Only 29 of 161 photos (18%) carry any tags.** Per the tech-guide's own words,
an untagged photo is *invisible to filtered browsing* -- so **82% of your techs'
work cannot be found by the main way clients search.** That is a live growth
problem worth a nudge campaign, and it is why this strip uses only tagged photos.

### Junk this nearly shipped to the homepage
Curated by eye from a contact sheet (do NOT pick by folder):
- **2 photos that are literally the OLD 2.0 rose-gold LOGO**, uploaded into a
  tech's gallery.
- **4 pedicure/toe shots** (wrong lead image), a **Halloween gore** set
  ("SAW"/blood), a July-4th seasonal set, and every **test-account** gallery
  (`apple-review`, `ios-test-user`, `test1234`, `sara-tester`...).
- Also found: **50 of 149 `gallery/` storage objects are orphaned** -- not
  referenced by any tech's live gallery (deleted/stale uploads still in the
  bucket). Worth a cleanup pass; they cost storage forever.

### Bug worth remembering
The cycler script silently never ran: `replace("</body>", ...)` hit the **first**
`</body>`, which sits **inside an HTML comment** at ~line 79 ("the inline cleanup
script near </body>"). The script was injected *into the comment*. `node --check`
still counted it as a valid block because the regex matches `<script>` tags
regardless of being commented out. **Insert before the LAST `</body>`
(`rindex`), and verify the script is actually in the live DOM, not just the file.**

## "AVAILABLE NOW" -> "AVAILABLE TODAY" + the availability-glow answer (2026-07-15)

**Anne asked: is there a glow for techs with availability in the next 5 days?**
**No.** Answer, from the code:
- The glow fires on ONE thing: `index.html:~11200`
  `if (p.tech.is_available) div.classList.add('avail-glow-tile')`.
- `is_available` is a **manual toggle** the tech flips. Nothing computes real
  availability from the booking calendar.
- There is a second flag, `is_same_day`, labelled **"Open This Week"**, and it
  does **NOT** glow at all.
- So: no 5-day glow, and no computed availability of any kind. **A "has an open
  slot in the next N days" glow would be NEW work** -- but it is now feasible,
  because the 3.0 booking engine already does server-side open-slot math
  (tech_availability + bookings + time off). Good roadmap candidate: it would
  make the glow *true* rather than self-declared, and self-declared flags rot.

**Renamed "Available Now" -> "Available Today" everywhere (28 strings: 22 in
index.html, 6 in marketing-v3).** Anne's instinct is backed by the code: the
`reset-available-now` cron clears `is_available` at **midnight daily**, so the
flag lives for a DAY, not a moment. "Available Now" overpromised; "Available
Today" is literally what the flag means. Renamed in the app too, not just
marketing, because a mismatch between the tech's toggle and the public label is
worse than either wording.
- The hyphenated identifiers (`available-now` in two comments), the column
  `is_available`, and the class `avail-glow-tile` were deliberately NOT touched.
- Follow-on copy fixed: the tech badge said *"I could take a client right now!"*
  (now "today"), and the gallery footer had a doubled "today".
- `is_same_day` / "Open This Week" left alone. NOTE its cron is
  `reset-open-this-week` (weekly, Sunday), so weekly reset matches the label --
  but a stale internal name (`liveToday` at ~7196) still calls it "today".
  Cosmetic, but confusing; worth renaming if anyone touches that code.

## I BROKE THE HERO AND FIXED IT (2026-07-15) -- READ THIS

Anne sent a screenshot: the pings were unstyled inline text on a purple
background. **The entire 3.0 hero override CSS block had been deleted -- by me.**
`build_gallery_demo.py` located the gallery CSS with `h.index("  /* ═══")`, which
matched the **FIRST** `/* ═══` banner in the file -- the **"MNC 3.0 overrides"**
header. It replaced from there through the gallery CSS, wiping: the ivory `.hero`,
the 1280 track, `.hero-art` (the raised card), all `.hero-ping` styling,
`.store-btns--mini` sizing, and the mobile stack. The hero silently reverted to
the 2.0 dark gradient. The markup was untouched, so only the CSS died.

**Same root cause as the `</body>` bug an hour earlier: matching the FIRST
occurrence of a non-unique anchor.** Two self-inflicted bugs, one lesson:
**anchor on something unique, and re-verify the WHOLE page after CSS surgery,
not just the section you were working on.** I verified the gallery (which was
fine) and never re-checked the hero.

**Recovered** from `scratchpad/mv3-before-cleanup.html` (the pre-purge backup),
re-applying the 6-ping stack on top. Verified restored: ivory hero
`rgb(237,234,229)`, 420x420 card @30px radius, 620px capped copy, left-aligned,
6 styled pings on `pingStack`, mini store buttons 147x49, gallery intact (46
tiles), no overflow, 9 JS blocks 0 errors. **Keep taking backups before CSS
surgery.**

## THREE STATES, THREE COLOURS (Anne's ask)
The gallery had one mauve state doing two jobs. Now:
- **Available Today = MAUVE `#BFA6BB`** (4 tiles) -- matches the app's own
  `avail-dot.now`, which is `--rose`.
- **Open This Week = GOLD `#D9B44A`** (2 tiles) -- matches the app's
  `avail-dot.today`, which is `--gold`. This state exists in the app
  (`is_same_day`) but never had a marketing presence.
- **Filters = BLUSH `#F7EBEE`** (chips, hit ring, tag label) -- deliberately a
  *control* colour so a filter never reads as an availability state.
Verified all three resolve distinct in the live DOM, plus a two-dot legend.

**Anne asked "should I be seeing examples of Open This Week?" -- she was right,
she couldn't.** Both gold tiles had landed in row A at indices 0 and 1, permanently
OFF-SCREEN (x=-665, -473), and row B had **none**. Cause: I stamped them with
`h.index('gs-row-b')`, which matched the **`.gs-row-b` CSS rule** (earlier in the
file) instead of the row's markup -- **the THIRD first-occurrence bug of the day**
(after `</body>`-in-a-comment and `/* ═══`). Fixed by slicing each row's markup by
its actual `<div class="gs-track gs-row-X">` tag and stamping chosen indices in
BOTH duplicate copies: row A [7, 19] of 24, row B [3, 14] of 22. Now 4 week tiles
(was 2), never colliding with a `live` tile, and at any moment ~2 are on screen and
clear of the edge fades.

**THE RECURRING LESSON, three times in one session:** `str.index` / `replace(x, y, 1)`
grab the FIRST match, and in a 113KB single-file page the first match is usually the
CSS rule or a comment, not the markup you meant. **Anchor on something unique
(a full tag), slice the region first, then edit inside it.**

**Gotcha:** reading `getComputedStyle` immediately after toggling a class returns
the MID-TRANSITION value (`.gs-chip` has a .25s transition), which looks like the
rule failed. Wait out the transition before asserting a colour.

## "DID YOU MEAN FOR THEM TO STOP SCROLLING?" (Anne, 2026-07-15)
No. The strip scrolls continuously; verified by measuring real movement on a
clean load: row A -419 -> -469 (-49px/1.5s), row B -1785 -> -1747 (+38px/1.5s),
opposite directions, `animation-play-state: running`.

Two honest notes from this:
- **I had paused it in MY browser tab** (an injected `animation:none` style) to
  take the screenshots. Runtime only, never written to the file; a reload clears
  it. If a screenshot shows it frozen, that is the capture, not the page.
- **I claimed "pauses on hover" and that was WRONG.** The
  `.gs-track-wrap:hover .gs-track { animation-play-state: paused; }` rule was
  silently dropped in the two-row rewrite, and I repeated the claim from memory
  instead of re-checking. Restored and verified present.

**The one case where stopping is CORRECT:** `@media (prefers-reduced-motion:
reduce)` sets `.gs-row-a, .gs-row-b { animation: none; }` by design. If the strip
is static on a given machine, check that OS setting first (Windows: Settings >
Accessibility > Visual effects > Animation effects). Same media query trims the
hero pings to 3 static chips. That is intended, not a bug.

## APP AUDIT: READ-ONLY SWEEP DONE (2026-07-16) -- see findings below

Anne asked for a full app audit ("make it the very best it can be"). The
2026-07-16 session ran the full read-only sweep (copy/model dimension by hand +
two parallel agents: a null-deref/dead-code sweep and a security sweep). ONE fix
has been applied since (the tech-edit modal restore, logged below); everything
else is reported and NOT yet changed. Findings, worst first:

1. **[FIXED 2026-07-16] Techs could not upload photos at all.** The tech-edit
   modal markup was removed as collateral by `9fb31c3`; `openTechEdit()` threw
   on null and `saveTechEdit()` (only photo-persist path) had zero callers. This
   was the revenue path for all of 3.0. Restored + verified live. See
   "TECH EDIT MODAL RESTORED" below.
2. **Dev-login block must be stripped before the native cutover (NOT a live
   prod issue).** CORRECTION 2026-07-17: an earlier draft of this finding
   claimed the DEV buttons "very likely ship in the CURRENT store builds." That
   was WRONG and is retracted. Verified: the dev-login was added in commit
   f54e714, which `git branch --contains` shows lives on **v3 only**. `main`
   (the branch the shipped 2.0 apps were built from) has NO `devLogin`, no DEV
   buttons, no test password in a login button -- only a comment saying the old
   bypass was removed. So dev login is NOT in prod today. The real, narrower
   point: the block sits in the v3 tree, and IF v3 ships to native as-is, the
   `location.hostname === 'localhost'` gate (~5346) would likely expose
   DEV-Tech / DEV-Client + the plaintext `MNC2026` (~5338), because Capacitor
   serves the WebView from localhost. This is already launch-sequence step 7
   ("remove the dev-login block"); treat it as a pre-flight checklist item, not
   an incident. (The line-10 comment claiming dev-login was removed is stale on
   v3, since f54e714 re-added it under a different mechanism.)
3. **[FIXED 2026-07-17] Stored XSS: text was escaped, URLs were not.** Added a
   `safeUrl()` helper (http(s)-only; blocks javascript:/data:) right after
   `esc()`, and wrapped every tech-controlled URL sink in `esc(safeUrl(...))`:
   tech-grid photo slot + avatar, inspo/gallery img, nearby-list avatar +
   preview pics, and the booking_link/gallery_link `href`s. Tags now `esc(t)`.
   The dead board render (td-bulletin-board markup is gone) was hardened too and
   its dual-context inline `onclick` dropped. Verified live: `javascript:` and
   `data:` links collapse to empty, a `"><script>` payload injects 0 script
   nodes, tags render as text, and legit https Vagaro/Instagram links still
   render clickable. Keys were already clean (no service_role / Stripe secret /
   VAPID private; one anon JWT by design).
4. **[FIXED 2026-07-17] Glow Up 40 -> 25 in app copy.** How It Works screen, the
   Glow Up upgrade card, and the welcome-stat `|| 40` fallback all now read 25.
   The impossible "post a new look every day" (>=30 at a 25 cap) reworded to
   "keep your gallery growing all month" across the two toasts, the welcome
   body, and the sw-body. The comp-path `|| 40` in `_periodSlotsRemaining()`
   was LEFT at 40 on purpose (comped techs are grandfathered at 40).
5. **[FIXED 2026-07-17] "feed" copy -> "Gallery".** The feed is gone; the
   Release Wizard's user-facing strings were the lie. "live in the feed now" ->
   "live in your Gallery now" (post-upload modal x3), "Release to feed ->" ->
   "Add to Gallery ->" (x6 buttons), the Glow Up welcome + sw bodies, and the
   stale release-routing comment. NOTE: the `board_posts` INSERT itself still
   fires (harmless orphan write; nothing reads it). Left in place because
   removing it touches the upload commit path; safe to retire in a later pass.
   Photos genuinely land in `techs.photos` (the Gallery) and release routes to
   `browse-style`, so the copy is now truthful.
6. **Two server-side checks to confirm in SQL** (not answerable from the
   client): does any RLS policy let a user PATCH their own `users.role`
   (`promoteToAdmin()` at 11402 tries it)? Does `append_tech_photo` enforce
   quota itself (the client slot gate is genuinely atomic + server-enforced,
   but a direct RPC call from the console would skip the client path)?

Dead code confirmed for deletion (all zero-caller 2.0 leftovers, all crash on
null if ever called): the broadcast/push cluster (~6423-6690), the admin
users-table cluster (~12008-12120, 15597-15872), `openNewPostModal` /
`submitPost` (~13322, 13341), `ueSetPhotoUrl` (~15497, has a defective
`|| {}` guard). Low priority -- they're unreachable -- but they're noise.

### Original 2026-07-15 note (superseded, kept for history)
**Only the first read-only sweep ran. Nothing was changed. No conclusions
beyond what is listed below.**

### Confirmed GOOD (verified, do not re-check)
- `IAP_DIAGNOSTIC_FAILURE_MODE = false` and `IAP_DIAGNOSTIC_SUCCESS_MODE = false`
  -- both already correct for an App Store build (CLAUDE.md flags this every time).
- `PHOTO_FREE_CUTOVER = '2099-01-01'` (correctly parked; set to launch date on the
  day) and `NEW_TECH_FREE_PHOTOS = 1`. Model intact.
- `PUSH_ENABLED = true`, a real `VAPID_PUBLIC_KEY` is present.
- Zero "unlimited photo" / "in full bloom" left in the app.

### FLAGGED, needs a look (NOT yet investigated)
- **"what's happening" x3** in index.html -- the feed was removed from 3.0
  entirely. Could be dead CSS/comments or live copy. **Check before launch.**
- **"new post" x6** -- posts were removed in 3.0. Same question: dead or live?
  (The admin panel is unreachable dead code, so some of this may be inside it.)
- **"5 free photos" x1** -- likely the legitimate grandfather promise, but verify
  it is not stated as the promise for NEW techs.
- **Dev backdoors to review before launch:** `dev-login` (~line 10),
  `mnc_force_new_pricing` (~3771-3784, the localhost-only pricing preview chip),
  and several `localhost` checks. The launch sequence already says to remove the
  dev-login block; confirm the pricing chip is localhost-gated too.

### Audit dimensions NOT yet run
security (XSS via innerHTML, key exposure), unguarded DOM access (the
`te-state` class of null deref), dead code beyond the admin panel, accessibility,
performance, and error handling. **Treat the app as un-audited.**

## HERO BUTTON HIERARCHY FIXED (2026-07-15, Anne: "4 black buttons and one purple")

Anne spotted that the hero had **4 solid black buttons and 1 purple**. The
diagnosis was a hierarchy inversion, not a palette problem: "Set up my free book"
(the conversion goal) was solid black -- and so were App Store, Google Play and
Use on Web. The primary CTA was **camouflaged among three download links**, while
the mauve secondary, being the only distinct thing, pulled MORE eye than the goal.

**Fix: quiet the store links rather than recolour the primary.** Anne suggested a
different colour for the CTA, but the brand direction is *black primary buttons*
and black is correctly the loudest colour on ivory. The store links are TERTIARY
(how you get the app, not the thing we want you to do), so they became outlined
chips: translucent white fill, near-black text, mauve keyline.

Verified in the live DOM:
- **`solidBlackCount: 1`** -- exactly one loud button on the hero.
- primary: surface vs hero **10.74**, text **11.09** (dominant)
- secondary (mauve): text **9.95**
- store chips: text/icon **17.07**, surface vs hero 1.11 (present but quiet)
- **Gotcha handled:** the Apple/Play marks are `fill="white"` *attributes* and
  would have gone invisible on a light chip. CSS `fill` overrides a presentation
  attribute, so `.hero .store-btn svg { fill: #141317 }` flips them (17:1). The
  Use-on-Web globe is `stroke="currentColor"` and followed automatically.

Reading order on the hero is now: **black CTA -> mauve alternative -> three quiet
download chips.**

## NOT SYNCED, ON PURPOSE
`deploy/sync.sh` has NOT been run. The deploy bundle still points at the OLD
project, which is correct for now: the moment `deploy/ghpages` ships from
`main`, the live site would move to the new DB while the 2.0 native apps still
have the OLD URL compiled in. Do not sync/push until the native cutover is
decided (see launch sequence step 10).

## STILL BLOCKED, needs Anne
- **Rotate the service_role AND anon keys** once the migration is finished.
  Both were pasted into a chat transcript on 2026-07-15, so they live in a
  durable log. Nothing is publicly exposed (the anon key is public by design
  anyway); this is hygiene, not an incident. If the service_role key is rotated,
  nothing in the repo breaks (it is only used by `rescue/upload_photos.py` via
  env). If the anon key is rotated, re-run the swap across those 12 files.

## NEXT, in order
1. Upload the 239 photos to the new `tech-photos` bucket (needs service_role).
2. **Rewrite 68 rows of stale OLD-project photo URLs.** They are absolute and
   hardcode `ktiztunuifzbzwzyqrrq.supabase.co`, so every photo breaks when the
   old project dies. Affected: techs.image_url (19), techs.photos jsonb (14),
   user_inspo.photo_url (12), board_posts.image_url (11), users.image_url (5),
   user_favorites.tech_image (3), archived_techs.image_url (2) + .photos (2).
   Do this AFTER the upload, or the URLs point at an empty bucket.
3. Edge functions + secrets (VAPID, NEW Stripe + RevenueCat webhook endpoints).
4. App key swap: index.html (2 spots), reset-password.html, marketing, trackers.
5. Anne tests: booking both sides, email flows, push, photos+glow, real phone.

## LAUNCH SEQUENCE (updated)
1. ~~Wake old DB → rescue~~ **DONE.** Next: **restore into the new project**
   from `rescue/`, WITH the "do it right" cleanups (drop dead 2.0 tables,
   normalize email casing + CHECK, add `auth_id` bridge columns, drop bookings
   legacy columns, auth hardening). Restoring `auth.users` into a fresh
   Supabase project is delicate, do it with Anne available.
2. **Finish auth + edge functions + secrets:** deploy edge functions
   (send-push, stripe-webhook v3, broadcast-push, delete-account,
   revenuecat-webhook); set VAPID secrets; create NEW Stripe + RevenueCat
   webhook endpoints pointing at the new project.
3. **Point the app at the new DB:** swap URL + anon key in `index.html`
   (2 spots), `reset-password.html`, marketing + trackers. Then `deploy/sync.sh`.
4. **Re-upload the 239 photos** to the new project's `tech-photos` bucket from
   `rescue/storage/`, and make sure `storage.objects` rows line up.
5. Promote `marketing-v3.html` → `marketing.html` and `tech-guide-v3.html` →
   `tech-guide.html`; rebrand icons + og-image.
6. **Add waitlist capture** to the live site.
7. **Flip launch switches:** set `PHOTO_FREE_CUTOVER` to launch date; remove the
   dev-login block; run `restore-paused-photos.sql`; clean ZZ TEST accounts.
8. **UptimeRobot monitors** (site + new Supabase REST).
9. **Go live:** merge `v3`→`main`, `deploy/sync.sh`, push main.
10. **Submit new native app-store builds** — old 2.0 native apps have the OLD
    DB URL baked in. Decide whether to keep the old project read-only until
    store approval.

## DEFERRED LOGIN: clients browse anonymously (2026-07-17, Anne's call)

**The change:** clients no longer log in to see anything. The old splash was a
hard wall (only "Sign In" / "Create a Free Account"), which in 3.0 is actively
hostile -- clients arrive via a tech's shared link and hit a login form instead
of nails. Now login is DEFERRED to the moment of intent (book / profile).
Model chosen: **A, login at the book tap** (not guest booking), so reminders,
appointment history, and push all survive because a booking still ties to an
account -- just created at the moment of booking, not up front.

**Why it was small:** the app already loaded tech data at boot (`applyFilters()`
runs before any login), `show()` has no auth gate, and every login funnels
through `showCorrectHome()`. Verified LIVE that an anonymous `GET /techs`
returns all 28 rows with every display column (bio, photos, availability,
subscription_tier) -- so RLS was never a blocker and the anonymous browse path
reads exactly one table.

**Edits to `index.html` (v3 working tree, NOT deployed/committed):**
- Splash: primary CTA is now **"Browse nails"** -> `enterGuest()` (= `show('home')`);
  "Sign In" demoted to secondary; "Create a free account" + "Forgot password"
  kept as small links.
- New helpers before `showCorrectHome`: `enterGuest()`, `requireLogin(action)`
  (stashes `window._pendingAction`, toasts, sends to auth), `resumePendingAction()`
  (after login, re-opens the exact tech's booking). `showCorrectHome()` is now a
  thin wrapper over `_showCorrectHomeInner()` that calls `resumePendingAction()`,
  so ALL four login paths (password, signup, restore, redirect) resume for free.
- `openBookModal()`: the dead-end "Sign in to book" toast is now
  `requireLogin({type:'book', techId: tech.id})`.
- `navToProfile()`: anonymous tap routes to auth instead of an empty profile.
- Backup: `scratchpad/index-before-guest-browse.html`.

**Verified live** (localhost:8123, real logged-out session): splash shows "Browse
nails" -> lands on home while anonymous, 28 techs load, greeting degrades to no
name; opening a tech profile works anonymously; tapping Book routes to auth and
stashes `{type:'book',techId}`; signing in RESUMES the booking on the exact tech
(landed back on tech-detail, book modal open, pending cleared, 0 JS errors);
anonymous Profile tap routes to auth. `</body>` intact, all new symbols unique,
`node --check` clean on all 7 JS blocks.

**Finding worth Anne's attention (data, not a bug):** **0 of 28 techs have
`booking_enabled=true`**, so the native in-app "Book" button currently shows for
nobody -- today's clients reach techs via external booking links (Vagaro etc.),
which open externally and never needed login anyway. The login-at-book gate is
correct and future-proof (proven by driving `openBookModal` directly), but it
only becomes visible once techs turn on native booking. Worth deciding whether
`booking_enabled` should default true, or whether native booking is a later
push. The browse-without-login win is live for all 28 techs regardless.

**Bottom-nav auth slot (2026-07-17):** the 8 client bottom-nav "Sign Out"
items now carry `class="auth-nav"` and route through `authNav()` (signed-in ->
`doSignOut()`, anon -> `show('auth')`). `styleAuthNav()` runs on every `show()`
and flips the label + title + opacity: anon reads a full-opacity **"Sign In"**,
signed-in reads the dim **"Sign Out"**. Verified live both ways (anon: all slots
"Sign In", tap -> auth; signed-in: "Sign Out", tap -> signs out to splash). The
two `<button>` sign-out variants (home header `#home-signout-btn`, profile
screen) are on signed-in-only surfaces and were left alone.

**Still open (deliberately not built this pass):** OAuth/magic-link login
round-trips through a page reload, which drops the in-memory `_pendingAction`,
so resume only fires for password sign-in + signup (the common client path).
Favorites/save-inspo already gate correctly (toast + show('auth')). If you want
resume to survive an OAuth round-trip, persist `_pendingAction` to
sessionStorage.

## WAITLIST POP-IN REBUILT on marketing-v3 (2026-07-17)

Anne asked for the 2.0-style "popup after ~5 sec" waitlist. The old pop-in was
removed 2026-05-04 (only the `.popin*` CSS survived); `launch_waitlist` table
still exists. Rebuilt onto the existing styles:
- Markup + JS injected before the LAST `</body>` (line 28 has a `</body>` inside
  a COMMENT -- the comment-trap; a `replace(...,1)` would have injected into the
  comment. Used `rfind`.)
- Slides in bottom-right ~5.2s after load; shows ONCE per visitor (localStorage
  `mnc_wl_v3` = 'joined'|'dismissed'); dismiss X + email form + success/dupe
  states. Writes `launch_waitlist`, `source:'marketing-v3'`.
- Added the missing `@keyframes waitlist-pop` (the leftover `.popin-success` CSS
  referenced it but it didn't exist).
- Backend re-verified LIVE via REST: insert 201, duplicate 409 (UI = "already on
  the list"), anon SELECT `[]` (RLS blocks scraping). Probe rows deleted.
- **Not visually verified** (preview down); JS `node --check` clean. Backup:
  `scratchpad/marketing-v3-before-waitlist.html`.
- Show-once (no re-nag) was my call; if Anne wants a re-show cadence, adjust the
  localStorage gate.

**PUBLISH marketing-v3: PREPPED ON MAIN, awaiting Anne's push (2026-07-17).**
Anne chose "prep it to go live, linked." Done in the MAIN worktree
(`C:\Users\amwhi\repos\My Nail Connection`), the 2.5-teaser standalone pattern,
NO app/DB cutover:
- Copied `marketing-v3.html` (with the new waitlist) + the 24 v3-only assets
  (`images/lady-card.webp`, `images/gallery/g01-23.webp`) into main SOURCE and
  the live `deploy/ghpages/` bundle. Shared logos/favicons already existed on main.
- Added `<meta name="robots" content="noindex,nofollow">` + `robots.txt`
  Disallow `/marketing-v3.html` (pre-launch, out of search).
- Linked it from the current marketing page footer ("Preview the new 3.0 ->") in
  both `marketing.html` (source) and `deploy/ghpages/index.html` (live homepage).
- Wired `sync.sh` via the existing `copy_if_exists` helper (same pattern a prior
  session used for `pivot.html`) so future syncs keep it.
- Did NOT run sync.sh (to avoid churning main's pre-existing dirty files); placed
  bundle files manually. Verified bundle: marketing-v3 present, noindex, waitlist,
  23/23 gallery + lady-card, homepage link, robots disallow, JS clean.
- **Anne pushes `main` via GitHub Desktop** to go live at
  `mynailconnection.com/marketing-v3.html`.

**FLAG for Anne before pushing:** main had **pre-existing uncommitted changes from
June/July** that are NOT from this session, `admin-stats.html`, `sw.js` (cache
bump), and a whole `pivot.html` standalone page (+ its bundle copies + a
`mnc-lady.png`). GitHub Desktop will show ALL of it alongside the marketing-v3
files. Anne should decide whether that older work should ship too or if she wants
to commit only the marketing-v3 files. It's stale (last main commit 2026-06-17),
so worth a conscious look, not a blind "commit all."

## "COULD NOT SAVE TO GALLERY" -- storage uploads used the anon key (2026-07-17)

Anne hit "could not save to gallery" testing photo upload. Root cause, PROVEN
empirically against the live bucket (browser preview was down, so tested via
REST):
- Every `POST /storage/v1/object/tech-photos/...` upload authenticated with
  **`Bearer SUPABASE_ANON_KEY`** (the anon key), not the signed-in tech's token.
- The migration HARDENED storage.objects writes to role `authenticated` (old
  prod granted writes to `public`). The handoff literally predicted this: "If
  photo upload breaks in testing, this is the first thing to check."
- Empirical proof: anon-key upload -> **HTTP 400**; same upload with the tech's
  access token -> **HTTP 200**. (Signed in as the test tech via REST password
  grant to get the token.)
- Also confirmed the DB half is NOT broken: `PATCH /techs` (own row) returns 204
  with BOTH anon key and token, so table RLS matches old prod (permissive). Only
  STORAGE writes needed fixing. Do NOT revert the storage hardening (that reopens
  the hole where any anon-key holder could overwrite/delete any tech's photos).

**Fix:** changed the Authorization on all **11** storage-write calls (uploads +
deletes to `/storage/v1/object/tech-photos/`) from bare `SUPABASE_ANON_KEY` to
`window._mncAccessToken || SUPABASE_ANON_KEY` -- the exact pattern the rest of
the file already uses for authenticated calls. The `apikey` header stays anon
(correct/required). Non-storage calls (reads, table writes) untouched. JS clean,
`</body>` intact, 0 storage writes left on bare anon. Backup:
`scratchpad/index-before-storage-auth-fix.html`.

**Narrow edge left (flagged, not fixed):** the signup-time profile upload
(~17009, `regData.first`) now uses the token IF a session exists, but if a NEW
tech uploads their photo BEFORE `completeSignup()` establishes the auth session,
`_mncAccessToken` is null -> falls back to anon -> still 400. Existing
authenticated techs (the reported case) are fully fixed; new-tech-signup photo
ordering may need the upload moved to after the session is created.

**Test-data note:** used the test tech (`annewilson1021+booktech`) for the REST
probes; its `hours_available` was overwritten during testing and restored to
`''` after. The `_authtest/probe.txt` storage object was created and deleted.

## SPLASH + HOME MERGED (2026-07-17, Anne)

Resolves the "two overlapping hubs" seam from the nav audit. The app now boots
straight into `home` (the single hub); the separate `splash` launcher is retired.
- `home` is the first-paint screen (`class="screen active"`); `splash` lost
  `active`. `_currentScreen` init = `'home'`.
- Boot: after `restorePersistedSession()`, anon visitors get `show('home')` so
  the home data hook (updateGreeting/loadTechs/availCounts) runs. Signed-in users
  were already routed by showCorrectHome.
- Repointed every `show('splash')`: `navHome()` -> `show('home')` for everyone
  (no more anon->splash), `doSignOut` -> home, `backFromAuth` fallback -> home,
  the auth catch-fallback -> home. 0 `show('splash')` refs remain.
- The `#splash` markup is left in the DOM but never shown (dead; safe to delete
  later). `setSplashWelcoming/clearSplashWelcoming` are now harmless no-ops on the
  hidden splash.
- Home already carried the brand (wordmark "My Nail Connection" + "Find · Connect
  · Glow") + browse cards + gallery + bottom nav, so it IS the merged screen.
  Did NOT move the splash's hat-lady logo / "Beauty. Connected." into the home
  header (kept the change low-risk, unverifiable visually). Offered as a follow-up.
- Verified: exactly one active screen (home), `</body>` intact, `node --check`
  clean. **Not visually verified** (preview down). Refreshed the phone-test build
  `C:\Users\amwhi\mnc-3-preview` with the merged app (dev-login re-enabled).
  Backup: `scratchpad/index-before-splash-home-merge.html`.

## NAVIGATION COHERENCE PASS (2026-07-17) -- fixing the "disjointed" feel

Anne: the app felt disjointed after the browse-first splash change. Root cause:
the whole nav model assumed everyone lands on `home` (the single hub that all
back buttons return to) and treated `splash` as a one-way launcher. Browse-first
made people land on a browse screen instead, so `home` became a redundant middle
chooser and "back" pointed at it from screens the user reached another way.

Fixes applied to `index.html` (v3, NOT deployed/committed; backup
`scratchpad/index-before-nav-coherence.html`):
1. **`navHome()` dispatcher:** anon -> `splash` (their real chooser), signed-in
   -> `home`. Wired the 8 bottom-nav "Home" tabs + the 2 browse back arrows to
   it. Anon browsers no longer get dumped on a `home` chooser they never saw.
2. **`backFromAuth()`:** the sign-in screen's Back returned to `_prevScreen`
   (the tech you were about to book), falling back to splash only from a cold
   entry. Was hardcoded `show('splash')`, which ejected mid-browse users to the
   start. (Applied to both the auth AND signup Back links; harmless on signup.)
3. **SCREEN_DEPTH:** added `'my-photos':3` and `'find-us':3`. They were missing
   (defaulted to 0), so drilling into them from a depth-2 hub animated as
   "going shallower" (fade) instead of deeper (slide-up). Now directionally
   correct.
4. **Techs land in their portal:** `showCorrectHome()` routed techs to `home`
   (client browse) after login; now routes them to `tech-home` (3 branches:
   role==='tech', tech-in-techs-table, and the isTechUser fallback). Directly
   answers "is it easy for a nail tech" -- log in -> your portal, not a client
   screen you navigate away from.

Verified: 8 edits with uniqueness asserts, `node --check` clean, `</body>`
intact, navHome wired 12x, 3 tech-home landings. **Could NOT get live browser
proof** (shared :8123 preview kept loading blank all session). Manual check
below.

**Known rough edge left (flagged to Anne, not fixed):** no quick toggle between
Browse by Look and Browse by Location once browsing -- you go back to the start
and pick the other. A small Look/Location toggle on the browse header would fix
it; deferred pending Anne's call on whether switching is common.

**After-map artifact:** https://claude.ai/code/artifact/72270369-fd4f-4636-a262-c6ca264d95e9

## "BOOK WITH X" BUTTON NEVER RENDERED -- dropped field (2026-07-17)

Anne (testing the browse-first splash): "there's no 'book with XXXX' button."
Root cause found and fixed. It was NOT just "no tech has booking on" (that's
also true); it was a real bug on top of that.

**The bug:** `loadTechsFromSupabase()` (~17138) maps each DB row into a curated
object for `ALL_TECHS`, and **`booking_enabled` was not in the map** (nor
`listing_paused`). `openTechDetail()` reads `tech.booking_enabled` to decide
whether to render the native "Book with X" button (index.html ~6588), so it was
always `undefined` -> button NEVER rendered for ANY tech, even one with booking
switched on in the DB. Exact same class as the `accepting_new_clients` bug the
code comment right above it documents. Fixed by adding
`booking_enabled: !!t.booking_enabled` + `listing_paused: !!t.listing_paused`
to the map. JS clean, `</body>` intact. Backup:
`scratchpad/index-before-bookingenabled-fix.html`.
**Could not get live browser proof** (the shared :8123 preview kept dropping);
verified at the code level only. Manual check: browse to "ZZ TEST, do not book"
-> the "Book ZZ TEST" button should now appear -> tapping it hits the deferred
-login gate.

**The data reality behind it (separate from the bug):** only ONE tech has
`booking_enabled=true` -- the test account "ZZ TEST" (which also has the only
`tech_services` row + only `tech_availability` row). ALL 28 real techs migrated
from 2.0 with booking OFF (they used external links / DMs). So even with the bug
fixed, a real user sees no book button until real techs enable it via Tech Portal
-> Bookings -> toggle On (`tbToggleEnabled`, ~12842) + add a service + weekly hours.
**Open product decision for Anne:** the app markets "free in-app booking, no DMs"
but 0 real techs have turned it on. Default it on (risks "no bookable services"
if they haven't set services), or drive an onboarding nudge to switch it on?

## TECH EDIT MODAL RESTORED (2026-07-16) -- the audit's #1 fix

**What broke:** `9fb31c3` ("admin panel removed", Jul 6) deleted 513 lines and
took the tech-edit modal with it. The modal was authored INSIDE the `#admin`
screen and relocated at runtime into `.device` by the `modal-overlay` class, so
it read as admin markup but is actually the tech's OWN profile + photo editor.
With its markup gone, `openTechEdit()` threw at the unguarded
`getElementById('tech-edit-modal').style.display` (was ~8256); the throw was
caught upstream and surfaced only as a "Could not load profile" toast.
Downstream, `saveTechEdit()` -- by its own comment "the only place photos get
persisted" -- had ZERO callers, and the Release Wizard it launches was
unreachable. Net: no tech could upload a photo, i.e. no one could pay. Not in
V3-PLAN; pure collateral damage.

**Fix applied to `index.html` (v3 working tree, NOT deployed, NOT committed):**
- Restored the modal (lines 3033-3303 of `9fb31c3^`) but **authored at TOP
  LEVEL** now, right after the admin-removal comment, so no future screen
  removal can take it again. Relocation still works (verified parent = `.device`).
- `te-state` restored **as the 51-option US dropdown** (reusing
  `reg-state-field`'s options), NOT the original free-text input, because the
  address stack (`stateAbbr`/`addrSelect`) assumes 2-letter codes and free text
  silently blanks the field. This is the reversal noted up in the STATE DROPDOWN
  section.
- Backup before edit: `scratchpad/index-before-modal-restore.html`.

**Verified live** (localhost:8123, signed in as the test tech against the NEW
DB): `openTechEditFromProfile()` no longer throws, no "Could not load profile"
toast, modal opens with real data (name/city/`te-state`=AZ from DB), photo grid
renders, slots read "5 free uploads left", both Save buttons present,
`saveTechEdit` has callers again, 0 JS/console errors. `</body>` intact, all 6
restored ids unique, `node --check` clean. (Screenshot capture timed out twice;
proof is DOM-level, not visual.)

**Side effect to settle next:** restoring the modal re-activates the Release
Wizard, so the "Release to feed" copy (audit finding #5) is now live again.

---

## KEY RULES / PREFERENCES (carry into any chat)
- **No em-dashes** anywhere (copy, code, docs) — use commas.
- Be a **devil's advocate**: honest pushback, verify against real evidence.
- When given A/B/C architecture choices, **make the call** and explain briefly.
- Client-facing copy is **first-person singular**, warm and understated, no hype.
- Messaging rule for 3.0: never imply 2.0 "failed"; frame is "we made it better."
- Model rules (locked 2026-07-05, from V3-PLAN): booking free for EVERYONE
  forever; **no feed, one Gallery**, visibility exactly proportional to photo
  count (never imply pay-to-rank); **photos never expire**; grandfathered
  (pre-cutover) techs keep **5 free photos**, new techs get **1**.

## Current status one-liner
Data is rescued and safe. The DB blocker is gone. Nothing is deployed. The app
audit ran (2026-07-16): the photo-upload path was silently broken and is now
fixed + verified; five other findings are reported and un-fixed (dev-login on
native, URL XSS, "40" copy, feed-write orphan, two SQL checks). Next real steps
unchanged: finish edge functions/secrets, then the launch sequence below.
