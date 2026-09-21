/* Instagram ad slides for the "found by your work" angle.
   Writes one HTML file per slide per format into campaign/insta-ads/src/,
   then render.sh screenshots them to PNG with headless Chrome.

   Formats: feed 1080x1350 (4:5, carousel) and story 1080x1920 (9:16).
   Design: My Nail Connection 3.0 system. Photos are the real gallery
   images from images/gallery/ (the same ones the live home page shows).
   The phone screens are drawn here in 3.0 styling on purpose: the PNGs
   in app-screens/ still show the retired 2.0 salmon header.

   Run: node campaign/insta-ads/build-slides.js && bash campaign/insta-ads/render.sh
*/
const fs = require('fs');
const path = require('path');
const SRC = path.join(__dirname, 'src');
const G = n => `../../../images/gallery/g${String(n).padStart(2, '0')}.webp`;

const CSS = `
*{box-sizing:border-box;margin:0;padding:0}
:root{
  --ink:#141317;--ink-1:#4A4A4F;--ink-2:#2A2A2E;--muted:#6D6068;
  --rose:#DEB3B5;--rose-mid:#D0A3A5;--rose-dark:#A2636C;--blush:#F7E2E3;--paper:#FAF7F2;
  --cream:#FBF8F8;--border:rgba(125,100,102,0.42);--h1:#1C1A19;--h2:#32302E;--hink:rgba(245,237,232,0.94);
  --grad:linear-gradient(140deg,#4A4A4F 0%,#2A2A2E 60%,#141317 100%);
}
html,body{width:1080px;height:var(--H);overflow:hidden}
body{font-family:'DM Sans',sans-serif;color:var(--ink);-webkit-font-smoothing:antialiased}
.slide{width:1080px;height:var(--H);position:relative;overflow:hidden;display:flex;flex-direction:column;padding:84px 88px 84px}
.light{background:#fff}
.blush{background:linear-gradient(170deg,#FBEEEE 0%,var(--blush) 100%)}
.dark{background:linear-gradient(160deg,var(--h1) 0%,#242221 34%,var(--h2) 66%,var(--h1) 100%);color:var(--hink)}
.dark::before{content:'';position:absolute;inset:0;background:radial-gradient(ellipse at 50% -10%,rgba(200,170,172,0.42) 0%,transparent 60%);pointer-events:none}
.slide>*{position:relative;z-index:1}

.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:56px}
.mark{font-family:'Playfair Display',serif;font-style:italic;font-weight:600;font-size:30px;letter-spacing:.3px}
.dark .mark{color:var(--hink)}
.count{font-size:22px;font-weight:600;letter-spacing:2px;color:var(--muted)}
.dark .count{color:rgba(245,237,232,.5)}

.eyebrow{font-size:22px;font-weight:700;letter-spacing:4px;text-transform:uppercase;color:var(--rose-dark);margin-bottom:26px}
.dark .eyebrow{color:var(--rose)}
h1{font-family:'Playfair Display',serif;font-weight:700;font-size:84px;line-height:1.04;letter-spacing:-1.2px}
h1 em{font-style:italic;color:var(--rose-dark)}
.dark h1 em{color:var(--rose)}
.sub{font-size:32px;line-height:1.45;color:var(--muted);margin-top:28px;max-width:860px}
.dark .sub{color:rgba(245,237,232,.66)}
.sub b{color:var(--ink);font-weight:600}
.dark .sub b{color:var(--hink)}
.grow{flex:1;min-height:0}
.foot{font-size:20px;color:var(--muted);line-height:1.5}
.dark .foot{color:rgba(245,237,232,.45)}

/* photos */
.ph{border-radius:22px;background-size:cover;background-position:center;box-shadow:0 10px 30px rgba(20,19,23,.18)}
.mosaic{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin-top:auto}
.mosaic .ph{aspect-ratio:1}
.mosaic .ph:nth-child(3n+2){transform:translateY(-40px)}

/* chips */
.chips{display:flex;gap:14px;flex-wrap:wrap;margin:44px 0 30px}
.chip{font-size:26px;font-weight:500;padding:13px 28px;border-radius:100px;border:2.5px solid var(--border);background:#fff;color:var(--ink)}
.chip.on{background:var(--grad);color:#fff;border-color:#141317;box-shadow:0 6px 18px rgba(169,139,141,.35)}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}
.tile{position:relative;aspect-ratio:1;border-radius:20px;overflow:hidden;background-size:cover;background-position:center}
.tile.dim{filter:grayscale(1) brightness(1.15);opacity:.28}
.tile .lab{position:absolute;left:0;right:0;bottom:0;padding:34px 16px 14px;font-size:19px;font-weight:600;color:#fff;background:linear-gradient(transparent,rgba(0,0,0,.55))}
.tile.you{outline:6px solid var(--rose-dark);outline-offset:-6px}
.tile .youpill{position:absolute;top:14px;left:14px;background:#fff;color:var(--rose-dark);font-size:18px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;padding:7px 14px;border-radius:100px}

/* phone */
.phone{width:540px;margin:0 auto;background:#fff;border-radius:64px;padding:18px;box-shadow:0 30px 80px rgba(20,19,23,.28),0 0 0 2px rgba(20,19,23,.06)}
.screen{border-radius:48px;overflow:hidden;background:#fff;border:1.5px solid rgba(125,100,102,.2)}
.prof{padding:34px 30px 30px;text-align:center}
.av{width:118px;height:118px;border-radius:50%;margin:0 auto 16px;background-size:cover;background-position:center;border:4px solid #fff;box-shadow:0 0 0 2px var(--rose-mid),0 6px 18px rgba(20,19,23,.18)}
.pname{font-family:'Playfair Display',serif;font-size:34px;font-weight:700}
.pmeta{font-size:19px;color:var(--muted);margin-top:6px}
.open{display:inline-flex;align-items:center;gap:9px;margin-top:14px;font-size:17px;font-weight:600;color:#3F6B4D;background:#E7F0E8;padding:7px 16px;border-radius:100px}
.dot{width:11px;height:11px;border-radius:50%;background:#5F9B72;box-shadow:0 0 0 5px rgba(95,155,114,.2)}
.pgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:4px;margin-top:24px}
.pgrid div{aspect-ratio:1;background-size:cover;background-position:center}
.pgrid div:first-child{border-radius:14px 0 0 0}.pgrid div:nth-child(3){border-radius:0 14px 0 0}
.acts{padding:22px 26px 30px;display:flex;flex-direction:column;gap:12px}
.b1{background:var(--grad);color:#fff;text-align:center;font-size:24px;font-weight:700;letter-spacing:1px;padding:21px;border-radius:16px;box-shadow:inset 0 1px 1px rgba(255,255,255,.18),inset 0 -3px 6px rgba(0,0,0,.3),0 8px 18px rgba(20,19,23,.28)}
.brow{display:flex;gap:12px}
.b2{flex:1;background:var(--paper);color:var(--ink-2);text-align:center;font-size:22px;font-weight:700;letter-spacing:.8px;padding:18px;border-radius:16px;border:1.5px solid rgba(162,99,108,.28)}

/* option cards */
.opts{display:flex;flex-direction:column;justify-content:space-between;gap:26px;margin-top:56px;flex:1}
.opt{flex:1;display:flex;gap:32px;align-items:center;background:var(--cream);border:1.5px solid var(--border);border-radius:28px;padding:36px 40px}
.num{flex:none;width:78px;height:78px;border-radius:50%;background:var(--blush);color:var(--rose-dark);font-family:'Playfair Display',serif;font-size:32px;font-weight:700;display:flex;align-items:center;justify-content:center}
.opt h3{font-family:'Playfair Display',serif;font-size:46px;font-weight:700;line-height:1.15;margin-bottom:8px}
.opt p{font-size:29px;line-height:1.45;color:var(--muted)}
.opt p b{color:var(--ink);font-weight:600}

/* price */
.cols{display:grid;grid-template-columns:1.2fr 1fr;gap:22px;margin-top:56px;flex:1}
.col{border-radius:30px;padding:44px 38px;display:flex;flex-direction:column}
.col.free{background:rgba(255,255,255,.07);border:1.5px solid rgba(222,179,181,.35)}
.col.paid{background:#fff;color:var(--ink)}
.col .k{font-size:19px;font-weight:700;letter-spacing:3px;text-transform:uppercase;margin-bottom:12px}
.col.free .k{color:var(--rose)}.col.paid .k{color:var(--rose-dark)}
.col .big{font-family:'Playfair Display',serif;font-size:84px;font-weight:700;line-height:1;margin-bottom:22px}
.col ul{list-style:none;display:flex;flex-direction:column;gap:20px}
.col li{font-size:29px;line-height:1.35;display:flex;gap:14px}
.col li::before{content:'';flex:none;width:12px;height:12px;border-radius:50%;margin-top:11px;background:var(--rose)}
.col.paid li::before{background:var(--rose-dark)}
.col.free li{color:rgba(245,237,232,.86)}
.col.paid .note{font-size:24px;color:var(--muted);margin-top:auto;padding-top:20px;line-height:1.45}

/* compare */
.vs{display:grid;grid-template-columns:1fr 1fr;gap:22px;margin-top:60px;flex:1;max-height:560px}
.vcard{border-radius:30px;padding:48px 34px;text-align:center;display:flex;flex-direction:column;justify-content:center}
.upto{font-size:24px;font-weight:600;letter-spacing:1px;color:var(--muted);margin-bottom:4px}
.vcard.them{background:var(--cream);border:1.5px solid var(--border)}
.vcard.us{background:var(--grad);color:#fff;box-shadow:0 18px 44px rgba(20,19,23,.3)}
.vcard .who{font-size:20px;font-weight:700;letter-spacing:3px;text-transform:uppercase;margin-bottom:18px}
.vcard.them .who{color:var(--muted)}.vcard.us .who{color:var(--rose)}
.vcard .fig{font-family:'Playfair Display',serif;font-size:140px;font-weight:700;line-height:1}
.vcard.them .fig{color:#9A8B90}
.vcard .what{font-size:24px;line-height:1.4;margin-top:16px}
.vcard.them .what{color:var(--muted)}.vcard.us .what{color:rgba(255,255,255,.8)}
.nolist{display:flex;flex-wrap:wrap;gap:12px;margin-top:40px}
.nolist span{font-size:26px;font-weight:600;padding:12px 22px;border-radius:100px;background:var(--blush);color:var(--rose-dark)}

/* cta */
.stores{display:flex;gap:18px;margin-top:48px}
.store{display:flex;flex-direction:column;background:#fff;color:var(--ink);border-radius:100px;padding:16px 38px}
.store small{font-size:15px;font-weight:600;letter-spacing:1.5px;text-transform:uppercase;color:var(--muted)}
.store span{font-size:30px;font-weight:700}
.url{font-family:'Playfair Display',serif;font-style:italic;font-size:34px;color:var(--rose);margin-top:34px}
.strip{display:flex;gap:14px;margin-top:auto}
.strip .ph{flex:1;aspect-ratio:3/4}

/* story: IG covers roughly the top 250px (profile bar) and bottom 340px
   (reply box), so content sits between them, centred, with the mark just
   below the top zone. Feed slides keep the normal flow. */
.feed .phone{zoom:.8}
.story .slide{padding:370px 88px 380px;justify-content:center}
.story .top{position:absolute;top:262px;left:88px;right:88px;margin:0}
.story .grow{flex:0 0 40px !important}
.story .mosaic,.story .strip{margin-top:60px}
.story .opts{flex:0 0 auto}.story .opt{flex:0 0 auto}
.story .cols{flex:0 0 auto;min-height:720px}
.story .vs{flex:0 0 auto;height:520px}
.story .phone{zoom:.92}
.story .grow[style*="display:flex"]{flex:0 0 auto !important;padding-top:56px !important}
.story .foot{margin-top:30px}
`;

const top = (n, total) => `<div class="top"><div class="mark">My Nail Connection</div>${n ? `<div class="count">${n} / ${total}</div>` : ''}</div>`;

const T = 7;
const slides = [
  {
    id: '01-hook', cls: 'dark', body: n => `
      ${top(n, T)}
      <div class="eyebrow">For nail techs</div>
      <h1>Clients don't search<br>for your name.<br><em>They search<br>for your nails.</em></h1>
      <div class="mosaic">
        <div class="ph" style="background-image:url(${G(14)})"></div>
        <div class="ph" style="background-image:url(${G(12)})"></div>
        <div class="ph" style="background-image:url(${G(9)})"></div>
        <div class="ph" style="background-image:url(${G(22)})"></div>
        <div class="ph" style="background-image:url(${G(4)})"></div>
        <div class="ph" style="background-image:url(${G(16)})"></div>
      </div>`
  },
  {
    id: '02-filter', cls: 'light', body: n => `
      ${top(n, T)}
      <div class="eyebrow">How they find you</div>
      <h1>They filter by the<br><em>look they want.</em></h1>
      <div class="chips">
        <span class="chip on">Coffin</span><span class="chip">Almond</span><span class="chip">Chrome</span><span class="chip">French</span><span class="chip">Nail Art</span>
      </div>
      <div class="grid">
        <div class="tile" style="background-image:url(${G(12)})"><div class="lab">Coffin · Acrylic</div></div>
        <div class="tile you" style="background-image:url(${G(13)})"><div class="youpill">Your set</div><div class="lab">Coffin · Nail Art</div></div>
        <div class="tile dim" style="background-image:url(${G(5)})"></div>
        <div class="tile dim" style="background-image:url(${G(18)})"></div>
        <div class="tile" style="background-image:url(${G(8)})"><div class="lab">Coffin · Bling</div></div>
        <div class="tile" style="background-image:url(${G(11)})"><div class="lab">Coffin · Solid</div></div>
      </div>
      <div class="grow"></div>
      <div class="sub" style="margin-top:34px">Every set you tag comes back <b>in every search that matches it.</b> Untagged sets never show.</div>`
  },
  {
    id: '03-one-tap', cls: 'blush', body: n => `
      ${top(n, T)}
      <div class="eyebrow">Then one tap</div>
      <h1>From your work<br><em>straight to you.</em></h1>
      <div class="grow" style="display:flex;align-items:flex-start;justify-content:center;padding-top:44px;min-height:0">
        <div class="phone"><div class="screen">
          <div class="prof">
            <div class="av" style="background-image:url(${G(20)})"></div>
            <div class="pname">Your name here</div>
            <div class="pmeta">Gel-X · Nail art · 2.4 mi</div>
            <div class="open"><span class="dot"></span>Open today</div>
            <div class="pgrid">
              <div style="background-image:url(${G(13)})"></div><div style="background-image:url(${G(4)})"></div><div style="background-image:url(${G(16)})"></div>
            </div>
          </div>
          <div class="acts">
            <div class="b1">Book right here</div>
            <div class="brow"><div class="b2">Call</div><div class="b2">Text</div></div>
          </div>
        </div></div>
      </div>
      <div class="sub" style="text-align:center;margin:56px auto 0;font-size:30px">The booking tool lives <b>on your gallery.</b><br>They pick the set, pick a time, done. Or they call. Or they text.</div>`
  },
  {
    id: '04-use-some', cls: 'light', body: n => `
      ${top(n, T)}
      <div class="eyebrow">Your book, your rules</div>
      <h1>Use some.<br><em>Use all.</em></h1>
      <div class="opts">
        <div class="opt"><div class="num">1</div><div><h3>Book in MNC</h3><p>Services, times, standing appointments and reminders, <b>attached to the gallery</b> that found them.</p></div></div>
        <div class="opt"><div class="num">2</div><div><h3>Keep the tool you have</h3><p>On Vagaro, GlossGenius or StyleSeat? Add your link and <b>a Book Now button goes there.</b></p></div></div>
        <div class="opt"><div class="num">3</div><div><h3>Just call or text</h3><p>Your number sits <b>right under your work.</b> No app in the middle.</p></div></div>
      </div>`
  },
  {
    id: '05-only-pay', cls: 'dark', body: n => `
      ${top(n, T)}
      <div class="eyebrow">What it costs</div>
      <h1>The only thing<br>you pay for is<br><em>the booking.</em></h1>
      <div class="cols">
        <div class="col free">
          <div class="k">Free, forever</div>
          <div class="big">$0</div>
          <ul><li>Your profile and gallery</li><li>Getting found in every search</li><li>Call and text buttons</li><li>Your own booking link</li><li>Open today for last-minute gaps</li></ul>
        </div>
        <div class="col paid">
          <div class="k">MNC booking</div>
          <div class="big">$10.99<span style="font-size:26px;font-family:'DM Sans';font-weight:600;color:var(--muted)">/mo</span></div>
          <ul><li>Book right on your gallery</li><li>Standing appointments</li><li>Your whole calendar</li></ul>
          <div class="note">First month free, no card to start.</div>
        </div>
      </div>`
  },
  {
    id: '06-no-cut', cls: 'light', body: n => `
      ${top(n, T)}
      <div class="eyebrow">The part nobody mentions</div>
      <h1>When an app finds you<br>a new client, many<br><em>take a cut.</em></h1>
      <div class="vs">
        <div class="vcard them"><div class="who">Marketplace apps</div><div class="upto">up to</div><div class="fig">30%</div><div class="what">of that new client's first visit, charged to you</div></div>
        <div class="vcard us"><div class="who">My Nail Connection</div><div class="fig">$0</div><div class="what">We found them. They're yours. Every visit.</div></div>
      </div>
      <div class="nolist"><span>No commission</span><span>No new-client fee</span><span>No per-booking fee</span><span>Never a charge to your clients</span></div>
      <div class="grow"></div>
      <div class="foot">Based on published new-client marketplace fees of leading beauty booking apps, September 2026. Those fees run 20% to 30%, some with a cap. Not every app charges one.</div>`
  },
  {
    id: '07-cta', cls: 'dark', body: n => `
      ${top(n, T)}
      <h1>Your work is already<br>why they pick you.<br><em>Now it's how<br>they find you.</em></h1>
      <div class="stores">
        <div class="store"><small>Download on the</small><span>App Store</span></div>
        <div class="store"><small>Get it on</small><span>Google Play</span></div>
      </div>
      <div class="url">mynailconnection.com</div>
      <div class="strip">
        <div class="ph" style="background-image:url(${G(1)})"></div>
        <div class="ph" style="background-image:url(${G(10)})"></div>
        <div class="ph" style="background-image:url(${G(21)})"></div>
      </div>`
  }
];

const FORMATS = { feed: 1350, story: 1920 };
fs.mkdirSync(SRC, { recursive: true });
for (const [fmt, H] of Object.entries(FORMATS)) {
  slides.forEach((s, i) => {
    const html = `<!DOCTYPE html><html class="${fmt}"><head><meta charset="utf-8"><link rel="stylesheet" href="../fonts/fonts.css"><style>:root{--H:${H}px}${CSS}</style></head>
<body class="${fmt}"><div class="slide ${s.cls}">${s.body(fmt === 'feed' ? i + 1 : 0)}</div></body></html>`;
    fs.writeFileSync(path.join(SRC, `${fmt}-${s.id}.html`), html);
  });
}
console.log('wrote', slides.length * 2, 'slide sources');
