# Build tech-guide-v3.html from tech-guide.html.
# Two jobs: (1) rose-gold -> mauve palette, (2) fix the locked-model
# violations. The big one: step 4 currently says "MNC doesn't handle
# bookings", which is the exact opposite of the 3.0 pivot. Step 6 (Posts)
# is replaced wholesale by Standing Appointments. Every rep() asserts.
import pathlib, sys, shutil, re

SRC = pathlib.Path("tech-guide.html")
DST = pathlib.Path("tech-guide-v3.html")
shutil.copyfile(SRC, DST)
h = DST.read_text(encoding="utf-8")
applied = []

def rep(label, old, new, count=1):
    global h
    n = h.count(old)
    if n != count:
        print(f"FAIL [{label}]: expected {count}, found {n}")
        sys.exit(1)
    h = h.replace(old, new)
    applied.append(label)

# ══ 1. PALETTE: rose-gold -> mauve (matches marketing v3) ═══════════════
pal = {
    "#C4786A": "#BFA6BB",   # rose        -> mauve
    "#8B4A40": "#5C3D5E",   # rose-dark   -> deep mauve
    "#FDF0EE": "#F7EBEE",   # rose-light  -> blush
    "#E0A898": "#C9A8C7",   # rose-mid
    "#E8C5BF": "#D9C4D6",   # filled slot gradient start
    "#D4A098": "#BFA6BB",   # filled slot gradient end
    "rgba(196,120,106,": "rgba(191,166,187,",
    "rgba(139,74,64,": "rgba(92,61,94,",
}
for a, b in pal.items():
    n = h.count(a)
    if n:
        h = h.replace(a, b)
        applied.append(f"palette {a}->{b} x{n}")

# ══ 2. PROGRESS TOC: Posts -> Regulars ═════════════════════════════════
rep("toc posts", '<span class="pb-label">Posts</span>',
    '<span class="pb-label">Regulars</span>')

# ══ 3. STEP 2: "5 free photo slots" -> "your first photo is free" ══════
rep("step2 title",
    '<h2 class="step-title">Your 5 free photo slots, <em>make them count.</em></h2>',
    '<h2 class="step-title">Your first photo is free, <em>make it count.</em></h2>')

rep("step2 why",
    "<p>Clients on MNC aren't searching by name, they're browsing <strong>nail photos.</strong> Your photos are your first impression, your portfolio, and your advertisement all rolled into one. These 5 free slots are permanent, they stay with your profile and work for you 24/7.</p>",
    "<p>Clients on MNC aren't searching by name, they're browsing <strong>nail photos.</strong> Your photos are your first impression, your portfolio, and your advertisement all rolled into one. Your first one is free and it's your storefront in the Gallery from the moment you join. Every photo you add after that is permanent too, it stays with your profile and works for you 24/7.</p>")

# the 5-slot "= FREE" visual -> 1 free, then $1 each
slot_filled = '''      <div class="photo-slot filled">
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="rgba(92,61,94,0.7)" stroke-width="1.5" stroke-linecap="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
        <span class="free-label">Slot {n}</span>
      </div>
'''
old_slots = "".join(slot_filled.format(n=i) for i in range(1, 6)) + '      <div class="photo-slots-arrow">= FREE</div>'
new_slots = '''      <div class="photo-slot filled">
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="rgba(92,61,94,0.7)" stroke-width="1.5" stroke-linecap="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
        <span class="free-label">Free</span>
      </div>
      <div class="photo-slot">
        <span class="free-label">$1</span>
      </div>
      <div class="photo-slot">
        <span class="free-label">$1</span>
      </div>
      <div class="photo-slot">
        <span class="free-label">$1</span>
      </div>
      <div class="photo-slot">
        <span class="free-label">$1</span>
      </div>
      <div class="photo-slots-arrow">or 10 for $5</div>'''
rep("step2 slots visual", old_slots, new_slots)

rep("step2 alert",
    '''<strong>These slots are yours, permanently.</strong>
        <p>Your 5 free photos are always included, no subscription, no expiration. They're the foundation of your profile. Fill them with your absolute best work.</p>''',
    '''<strong>Every photo you add is yours, permanently.</strong>
        <p>Nothing expires, nothing lapses, and you never pay to keep a photo up. The set you posted last spring is still pulling clients next spring. Instagram rents attention. Here, you own a billboard.</p>
        <p style="margin-top:10px;"><strong>Joined before 3.0?</strong> Your first five photos stay free, always. That was the promise and it stands.</p>''')

rep("step2 howto2",
    '''<h4>Choose your best 5</h4>
          <p>Think about variety: different shapes, different colors, different styles. Show the range of what you can do. A client looking for ombre nails should see ombre. A client looking for nail art should see nail art. Cover your bases.</p>''',
    '''<h4>Lead with your single best set</h4>
          <p>Your first photo is free, so make it the one that stops a scroll. After that, think variety: different shapes, colors, and styles. A client looking for ombre should see ombre. A client looking for nail art should see nail art. Every photo you add widens the net.</p>''')

# ══ 4. STEP 4: booking. The "MNC doesn't handle bookings" line must go. ═
rep("step4 title",
    '<h2 class="step-title">Connect your booking link, <em>one tap to book you.</em></h2>',
    '<h2 class="step-title">Turn on booking, <em>free forever.</em></h2>')

rep("step4 why",
    "<p>MNC doesn't handle bookings, it's how clients find you and get connected. Once a client falls in love with your work, they should be able to book you in one tap. If you're already on a booking platform, just paste your link. Done.</p>",
    "<p>MNC books for you, and it costs nothing. A client finds your work, taps once, and lands in your calendar. No commission, no per-booking fee, no trial that runs out. Booking lives with MNC and stays free for every tech, forever. Set your services and your hours and you're taking appointments.</p>")

rep("step4 platforms intro",
    'Paste your booking page link from any of these platforms and MNC will automatically label the button on your profile:',
    'Already book somewhere else? Keep it. Paste your existing booking page link and MNC labels the button on your profile automatically. You can run MNC booking, your own link, or both:')

rep("step4 howto",
    '''<div class="how-to-item">
        <div class="how-num">1</div>
        <div class="how-content">
          <h4>Grab your booking page link</h4>
          <p>Open your booking platform, find your public-facing booking page, and copy the URL. It's usually something like <em>vagaro.com/yourname</em> or <em>square.site/yourname</em>.</p>
        </div>
      </div>
      <div class="how-to-item">
        <div class="how-num">2</div>
        <div class="how-content">
          <h4>Paste it in your Dashboard under "Booking Link"</h4>
          <p>Look for the Booking Link field in your profile edit section. Just paste and save.</p>
        </div>
      </div>
      <div class="how-to-item" style="padding-bottom:0;">
        <div class="how-num">3</div>
        <div class="how-content">
          <h4>Preview how it looks on your profile</h4>
          <p>There's a preview button in the dashboard that shows how clients see your booking button. Give it a tap to make sure it points where you expect.</p>
          <div class="tip">
            <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="#5C3D5E" stroke-width="2" stroke-linecap="round"><polyline points="20 6 9 17 4 12"/></svg>
            No booking platform? No problem. Clients can still call or text you directly using your phone number. Add both for maximum options.
          </div>
        </div>
      </div>''',
    '''<div class="how-to-item">
        <div class="how-num">1</div>
        <div class="how-content">
          <h4>Add your services, with a price and a length</h4>
          <p>Full set, fill, soak-off, whatever you actually offer. Each one gets a duration and a price, and that duration is what MNC uses to work out which appointment times you can genuinely fit.</p>
        </div>
      </div>
      <div class="how-to-item">
        <div class="how-num">2</div>
        <div class="how-content">
          <h4>Set your weekly hours</h4>
          <p>Tell MNC the days and hours you work. Clients only ever see slots inside those hours. Add buffer time between appointments if you need a breather, and block off days you're away.</p>
        </div>
      </div>
      <div class="how-to-item" style="padding-bottom:0;">
        <div class="how-num">3</div>
        <div class="how-content">
          <h4>Choose how bookings land</h4>
          <p>By default a booking arrives as a request and waits for you to confirm. Prefer it hands-off? Flip on <strong>auto-confirm</strong> and the slot books itself. Either way you and your client both get a reminder the day before and again three hours out.</p>
          <div class="tip">
            <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="#5C3D5E" stroke-width="2" stroke-linecap="round"><polyline points="20 6 9 17 4 12"/></svg>
            Two clients can never grab the same slot. MNC locks the time the moment one of them takes it.
          </div>
        </div>
      </div>''')

# ══ 5. STEP 6: Posts -> Standing Appointments ══════════════════════════
step6_start = h.index('<section class="section" id="step6">')
step6_end = h.index('<!-- STEP 7: MORE PHOTOS = MORE VIEWS -->')
old6 = h[step6_start:step6_end]
assert 'post-ideas' in old6, "step6 not located"
new6 = '''<section class="section" id="step6">
  <div class="section-inner narrow">
    <div class="step-header fade-up">
      <div class="step-num-badge"><span>06</span></div>
      <div class="step-header-text">
        <span class="step-label">Your Regulars</span>
        <h2 class="step-title">Standing appointments. <em>Your regulars, on autopilot.</em></h2>
      </div>
    </div>

    <div class="why-box fade-up">
      <div class="why-icon">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#BFA6BB" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
      </div>
      <div class="why-text">
        <strong>Why this is the one to set up</strong>
        <p>Your every-three-weeks regular shouldn't have to rebook every three weeks. One forgotten rebook is a gap in your week and a client who drifts. Turn an appointment into a standing one and the chair stays held, automatically, without either of you thinking about it. This is the feature the paid booking tools charge you monthly for.</p>
      </div>
    </div>

    <div class="alert-box fade-up" style="margin-bottom:24px;">
      <div class="alert-icon">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="#5C3D5E" stroke-width="2" stroke-linecap="round"><path d="M3 12h18"/><polyline points="15 6 21 12 15 18"/></svg>
      </div>
      <div>
        <strong>These are real appointments, not reminders.</strong>
        <p>A standing appointment books actual slots on your calendar, the same as any other booking, so nobody else can take that time. MNC keeps topping the series up so there's always another one on the books ahead of you.</p>
      </div>
    </div>

    <p class="fade-up" style="font-size:15px; color:#5A4A44; margin-bottom:24px; line-height:1.65;">How it works, in practice:</p>

    <div class="post-ideas fade-up">
      <div class="post-idea">
        <div class="post-idea-icon">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#BFA6BB" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
        </div>
        <div>
          <h5>Every 1 to 4 weeks</h5>
          <p>Pick the rhythm that matches your client, weekly, fortnightly, every three weeks, monthly.</p>
        </div>
      </div>
      <div class="post-idea">
        <div class="post-idea-icon">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#BFA6BB" stroke-width="1.8" stroke-linecap="round"><polyline points="20 6 9 17 4 12"/></svg>
        </div>
        <div>
          <h5>Booked, not pencilled in</h5>
          <p>Each one is a real slot on your calendar. The time is held, so nobody else can book over it.</p>
        </div>
      </div>
      <div class="post-idea">
        <div class="post-idea-icon">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#BFA6BB" stroke-width="1.8" stroke-linecap="round"><path d="M21 2v6h-6"/><path d="M3 12a9 9 0 0115-6.7L21 8"/><path d="M3 22v-6h6"/><path d="M21 12a9 9 0 01-15 6.7L3 16"/></svg>
        </div>
        <div>
          <h5>Tops itself up</h5>
          <p>As each appointment passes, the next one gets added to the end. The series never quietly runs out.</p>
        </div>
      </div>
      <div class="post-idea">
        <div class="post-idea-icon">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#BFA6BB" stroke-width="1.8" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </div>
        <div>
          <h5>One week off is just one week</h5>
          <p>Cancel a single appointment without touching the rest. Holiday weeks don't break the rhythm.</p>
        </div>
      </div>
    </div>

    <div class="how-to-list fade-up">
      <div class="how-to-item">
        <div class="how-num">1</div>
        <div class="how-content">
          <h4>Open the appointment in Bookings</h4>
          <p>Bookings sits at the top of your dashboard. Tap any confirmed appointment with a client who comes back like clockwork.</p>
        </div>
      </div>
      <div class="how-to-item" style="padding-bottom:0;">
        <div class="how-num">2</div>
        <div class="how-content">
          <h4>Tap "Make this standing" and pick the rhythm</h4>
          <p>Choose every 1, 2, 3, or 4 weeks. MNC books the series out for you from there and keeps it topped up. That's the whole setup.</p>
          <div class="tip">
            <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="#5C3D5E" stroke-width="2" stroke-linecap="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
            Do this for your handful of true regulars first. That's usually most of a predictable week, locked in, in about two minutes.
          </div>
        </div>
      </div>
    </div>
  </div>
</section>


<!-- ══════════════════════════════════════════ -->
'''
h = h[:step6_start] + new6 + h[step6_end:]
applied.append("step6 Posts -> Standing Appointments")

# ══ 6. STEP 7: growth math ═════════════════════════════════════════════
rep("step7 intro",
    "Your 5 free photos are your permanent foundation. When you're ready to grow, whether you're building a bigger portfolio, launching a new specialty, or just want more exposure, you can add more photos anytime.",
    "Your free first photo gets you into the Gallery. Everything after it is how you widen the net, whether you're building a bigger portfolio, launching a new specialty, or just want more people to find you. Add photos whenever you're ready, at your pace.")

rep("step7 alert",
    '''<strong>You control your growth pace.</strong>
        <p>Start with 5 and see how it goes. When you're ready for more visibility, when clients start reaching out and you want to show even more of your range, adding photos is easy and flexible. No contracts, no pressure.</p>''',
    '''<strong>You control your growth pace.</strong>
        <p>Start with your free one and see how it goes. When you want more visibility, add photos for $1 each, $5 for ten, or go Glow Up at $10.99 a month for 40 uploads. That is the entire business model: we only earn when you choose to show more of your work. No contracts, no pressure.</p>''')

rep("step7 howto1",
    '''<h4>Fill your 5 free slots first</h4>
          <p>Get your best, most varied work up. These are permanent, they stay on your profile forever at no cost.</p>''',
    '''<h4>Start with your free photo</h4>
          <p>Make it your strongest set. It's your storefront in the Gallery from day one, and it stays on your profile permanently.</p>''')

rep("step7 howto2",
    "Think of your MNC profile as your <strong>growing portfolio</strong>, every set you add lives here, documented, searchable, working for you 24/7. Make a habit of uploading new photos regularly. Even one new set a week adds up fast, and with Glow Up's <strong>5 new slots every Sunday</strong>, you've got a built-in rhythm to keep it fresh without thinking about it.",
    "Think of your MNC profile as your <strong>growing portfolio</strong>, every set you add lives here, documented, searchable, working for you 24/7. Even one new set a week adds up fast. If you're uploading steadily, <strong>Glow Up</strong> at $10.99 a month covers 40 uploads and works out cheaper than buying them one by one.")

rep("step7 mathsub",
    "When clients browse by style, every photo with matching tags has a chance to appear. Techs with more tagged photos show up more often, it's that simple.",
    "Your share of the Gallery grows exactly with your photo count. No boosting, no pay-to-rank, no mystery math. Techs with more tagged photos show up more often, it's that simple.")

# ══ 7. Misc: browse feed -> Gallery; final CTA ═════════════════════════
rep("browse feed",
    "It's now live on your profile and searchable in the browse feed.",
    "It's now live on your profile and searchable in the Gallery.")

rep("final cta sub",
    "Ten minutes to set up. Free to start. Clients in your area are searching right now, be there when they look.",
    "Ten minutes to set up. Free to join, free to book, forever. Clients in your area are searching right now, be there when they look.")

# ══ 8. No em-dashes ════════════════════════════════════════════════════
if "&mdash;" in h:
    h = h.replace(" &mdash; ", ", ").replace("&mdash;", ",")
    applied.append("em-dashes stripped")

DST.write_text(h, encoding="utf-8")
print(f"applied {len(applied)} changes:")
for a in applied:
    print("  +", a)
print("\nbytes:", DST.stat().st_size)
