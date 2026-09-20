/* Builds the "Introducing New" email series as Resend-ready HTML.
   One file per email in campaign/emails/.

   Design: My Nail Connection 3.0 identity (white first, ink gradient
   primaries, rose-dark accents, Playfair + DM Sans). The older
   docs/founders-email.html used the retired 2.0 terracotta rose; these
   do not.

   Email-client rules followed here:
   - Table layout, every critical style inlined on the element.
   - Gradients carry a solid bgcolor fallback for Outlook.
   - Google Fonts via <link>, with Georgia / system sans fallbacks.
   - No rgba() where a solid hex will do.
   - 480px card, same as the founders email, so it renders on a phone.

   Run: node campaign/build-emails.js
*/
const fs = require('fs');
const path = require('path');
const OUT = path.join(__dirname, 'emails');

const T = {
  pageBg:   '#F4EEEE',
  card:     '#FFFFFF',
  ink:      '#141317',
  muted:    '#6D6068',
  rose:     '#A2636C',   // rose-dark, the only rose you may set text in
  blush:    '#F7E2E3',
  paper:    '#FAF7F2',   // rose-light
  rule:     '#DCCFD0',   // solid stand-in for the 1.5px app border
  gold:     '#8C7E76',
  btnSolid: '#2A2A2E',   // ink-2, the Outlook fallback under the gradient
  btnGrad:  'linear-gradient(140deg,#4A4A4F 0%,#2A2A2E 60%,#141317 100%)'
};

const APP  = 'https://mynailconnection.com/app/';
const SITE = 'https://mynailconnection.com/';
const NEWS = 'https://mynailconnection.com/whats-new.html';
const GUIDE = 'https://mynailconnection.com/tech-guide-v3.html';
const LOGO = 'https://mynailconnection.com/images/mncLogo-email.png';

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/* A bulleted "what this actually means" row. */
function bullet(text) {
  return `
        <tr><td style="padding:0 0 10px;">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
            <tr>
              <td width="22" valign="top" style="padding-top:7px;">
                <div style="width:7px;height:7px;border-radius:100px;background:${T.rose};"></div>
              </td>
              <td valign="top" style="font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;line-height:1.6;color:${T.ink};">${text}</td>
            </tr>
          </table>
        </td></tr>`;
}

/* The pull-quote panel: blush ground, the one line worth remembering. */
function panel(line, sub) {
  return `
        <tr><td style="padding:6px 0 20px;">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" bgcolor="${T.blush}" style="background:${T.blush};border-radius:16px;">
            <tr><td style="padding:18px 20px;">
              <div style="font-family:'Playfair Display',Georgia,serif;font-size:17px;line-height:1.35;color:${T.ink};font-weight:600;">${line}</div>
              ${sub ? `<div style="font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;line-height:1.55;color:${T.muted};margin-top:6px;">${sub}</div>` : ''}
            </td></tr>
          </table>
        </td></tr>`;
}

function button(label, href) {
  return `
        <tr><td align="center" style="padding:6px 0 4px;">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0">
            <tr><td align="center" bgcolor="${T.btnSolid}" style="background:${T.btnSolid};background-image:${T.btnGrad};border-radius:12px;">
              <a href="${href}" style="display:inline-block;padding:14px 30px;font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;font-weight:700;letter-spacing:0.9px;color:#FFFFFF;text-decoration:none;border-radius:12px;">${label}</a>
            </td></tr>
          </table>
        </td></tr>`;
}

function render(e) {
  const bullets = e.bullets.map(bullet).join('');
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${esc(e.subject)}</title>
<!-- Gmail, Apple Mail and Outlook for Mac strip <head><style> but allow
     Google Fonts via <link>. Every critical style is inlined below, so the
     design holds where the link is stripped too. -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,600;0,700;1,600&family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  body { margin:0; padding:0; width:100% !important; }
  a { color:${T.rose}; }
  @media (max-width:520px) {
    .mnc-pad { padding-left:22px !important; padding-right:22px !important; }
    .mnc-h1  { font-size:25px !important; }
  }
</style>
</head>
<body style="margin:0;padding:0;background:${T.pageBg};font-family:'DM Sans',-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:${T.ink};">

<!-- Preheader: the grey line beside the subject in the inbox. Hidden in the body. -->
<div style="display:none;font-size:1px;color:${T.pageBg};line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">${esc(e.preheader)}&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>

<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" bgcolor="${T.pageBg}" style="background:${T.pageBg};">
  <tr><td align="center" style="padding:30px 14px 36px;">

    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="480" style="max-width:480px;width:100%;background:${T.card};border-radius:18px;overflow:hidden;box-shadow:0 6px 28px rgba(20,19,23,0.09);">

      <!-- Header: white, the wordmark typeset, FIND CONNECT GLOW beneath it. -->
      <tr><td align="center" style="padding:26px 24px 20px;border-bottom:1px solid ${T.rule};">
        <img src="${LOGO}" width="46" height="46" alt="" style="display:block;margin:0 auto 10px;border:0;border-radius:12px;">
        <div style="font-family:'Playfair Display',Georgia,serif;font-style:italic;font-size:21px;font-weight:600;color:${T.ink};letter-spacing:0.3px;">My Nail Connection</div>
        <div style="font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:700;color:${T.rose};letter-spacing:2px;text-transform:uppercase;margin-top:5px;">Find Connect Glow</div>
      </td></tr>

      <!-- Body -->
      <tr><td class="mnc-pad" style="padding:26px 28px 8px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">

          <tr><td style="padding:0 0 6px;">
            <div style="font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:700;color:${T.muted};letter-spacing:1.6px;text-transform:uppercase;">${esc(e.eyebrow)}</div>
          </td></tr>

          <tr><td style="padding:0 0 12px;">
            <h1 class="mnc-h1" style="margin:0;font-family:'Playfair Display',Georgia,serif;font-size:28px;line-height:1.14;font-weight:700;color:${T.ink};letter-spacing:0.2px;">${e.headline}</h1>
          </td></tr>

          <tr><td style="padding:0 0 16px;">
            <p style="margin:0;font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.62;color:${T.ink};">${e.lede}</p>
          </td></tr>

          ${e.panelLine ? panel(e.panelLine, e.panelSub) : ''}

          <tr><td style="padding:0 0 4px;">
            <div style="font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:700;color:${T.muted};letter-spacing:1.6px;text-transform:uppercase;padding-bottom:10px;">${esc(e.listLabel)}</div>
          </td></tr>

          ${bullets}

          <tr><td style="padding:8px 0 18px;">
            <p style="margin:0;font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.62;color:${T.ink};">${e.close}</p>
          </td></tr>

          ${button(e.cta, e.ctaHref)}

          <tr><td align="center" style="padding:10px 0 4px;">
            <a href="${NEWS}" style="font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:${T.rose};text-decoration:none;">See everything that is new &rarr;</a>
          </td></tr>

        </table>
      </td></tr>

      <!-- Sign-off -->
      <tr><td class="mnc-pad" style="padding:20px 28px 24px;">
        <div style="border-top:1px solid ${T.rule};padding-top:18px;">
          <p style="margin:0 0 4px;font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;line-height:1.6;color:${T.ink};">${e.signoff}</p>
          <p style="margin:0;font-family:'Playfair Display',Georgia,serif;font-style:italic;font-size:15px;color:${T.rose};">The My Nail Connection team</p>
        </div>
      </td></tr>

      <!-- Footer -->
      <tr><td align="center" bgcolor="${T.paper}" style="background:${T.paper};padding:20px 24px 22px;border-top:1px solid ${T.rule};">
        <div style="font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;line-height:1.7;color:${T.muted};">
          <a href="${SITE}" style="color:${T.rose};text-decoration:none;font-weight:600;">mynailconnection.com</a>
          &nbsp;&middot;&nbsp;
          <a href="${GUIDE}" style="color:${T.rose};text-decoration:none;font-weight:600;">Setup guide</a>
          &nbsp;&middot;&nbsp;
          <a href="${SITE}privacy.html" style="color:${T.muted};text-decoration:none;">Privacy</a>
        </div>
        <div style="font-family:'DM Sans',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;line-height:1.6;color:${T.muted};margin-top:12px;">
          You are getting this because you have a My Nail Connection tech profile.<br>
          <a href="{{{RESEND_UNSUBSCRIBE_URL}}}" style="color:${T.muted};text-decoration:underline;">Unsubscribe</a>
        </div>
      </td></tr>

    </table>

  </td></tr>
</table>
</body>
</html>
`;
}

/* ─────────────────────────────────────────────────────────────────────
   The series. Every claim below is taken from the live marketing page
   or the shipping app. Nothing here is invented.
   ───────────────────────────────────────────────────────────────────── */
const EMAILS = [
  {
    file: '01-introducing-3-0',
    subject: 'Introducing: everything that changed while you were working',
    preheader: 'Version 3.0 is here. Your gallery, your chair, your book, your link.',
    eyebrow: 'Introducing new',
    headline: 'Your profile got a lot busier.<br><em style="font-style:italic;color:#A2636C;">You did not have to do a thing.</em>',
    lede: 'Version 3.0 is live, and it is not a fresh coat of paint. There is a whole booking engine behind your gallery now, plus a handful of things you can turn on in under a minute that most techs still have not found.',
    panelLine: 'Did you know your gallery is not a scrapbook?',
    panelSub: 'It is how clients find you. Every photo you tag puts you in a search you were not in before.',
    listLabel: 'What is new',
    bullets: [
      '<strong>One Gallery.</strong> Clients filter by shape, type and style, and only tagged photos come back.',
      '<strong>Open today.</strong> Flip it after a cancellation and your work glows for the clients looking right now.',
      '<strong>Standing appointments.</strong> Your every-three-weeks regular, booked once, topped up automatically.',
      '<strong>Your own link and QR.</strong> Instagram bio, story, a text, a card at your station.',
      '<strong>Your whole book.</strong> Walk-ins, phone clients, reschedules, no-shows, private notes.',
      '<strong>A free month that starts when you are ready</strong>, not the day you signed up.'
    ],
    close: 'Over the next few weeks we will send one of these at a time, so nothing gets lost. Start wherever you like.',
    cta: 'Open the app',
    ctaHref: APP,
    signoff: 'Your talent was already there. We just make sure clients can find it.'
  },
  {
    file: '02-gallery-is-how-you-get-found',
    subject: 'Did you know your gallery is a search engine?',
    preheader: 'Untagged photos are invisible. Tagging is two taps and it auto-saves.',
    eyebrow: 'Introducing new',
    headline: 'Your gallery is how you<br><em style="font-style:italic;color:#A2636C;">get found and booked.</em>',
    lede: 'Clients do not scroll MNC hoping to stumble on you. They filter. Shape, type, style. When they filter, only tagged photos come back, which means an untagged photo is a beautiful set that nobody will ever see.',
    panelLine: 'Tag five photos and you are in five searches you were not in before.',
    panelSub: 'Tags are the whole mechanic. There is no boosting and nothing to buy.',
    listLabel: 'How to catch up in one sitting',
    bullets: [
      'Open <strong>My Gallery</strong>. Untagged photos float to the top, so you never have to hunt for them.',
      'Tap <strong>Shape</strong>, <strong>Type</strong> and <strong>Style</strong> on each one. Your changes auto-save as you tap.',
      'New photos get tagged as you post, so you only ever do this once.',
      'Photos are free, up to 50 a month, on every plan. They never expire and nothing auto-deletes.',
      '<strong>Presence tracks your work, not your budget.</strong> Your share of the Gallery grows exactly with your photo count.'
    ],
    close: 'This is the single highest-return ten minutes in the whole app. Nobody can outspend you into invisibility here, but an untagged photo will do it for free.',
    cta: 'Tag my photos',
    ctaHref: APP,
    signoff: 'Instagram rents attention. Here, you own a billboard.'
  },
  {
    file: '03-fill-the-chair-today',
    subject: 'That empty two o’clock can still be a booking',
    preheader: 'Open today puts your work in front of the clients who need nails today.',
    eyebrow: 'Introducing new',
    headline: 'Had a cancellation?<br><em style="font-style:italic;color:#A2636C;">Fill it today.</em>',
    lede: 'A last-minute no-show used to just be money gone. Now it is a toggle. Flip <strong>Open today</strong> and your work glows in the Gallery right when the clients who need nails today are looking.',
    panelLine: 'Two seconds. No cost. On every plan, including the free one.',
    panelSub: 'There is also Open this week, for the slower gaps that are not quite an emergency.',
    listLabel: 'Why it works',
    bullets: [
      'Clients have their own <strong>Open today</strong> filter. They tap it when they want nails now and do not want to call around.',
      'Flipping it moves you into that view immediately. No waiting, no approval, no fee.',
      'Your gallery goes with you, so they are not booking a name, they are booking the set they just fell for.',
      'They can book you in the app, or call or text if you have added your number.',
      'Turn it off when you fill up. You are in control of it all day long.'
    ],
    close: 'The chair does not care why it is empty. This is the fastest thing in the app, and most techs have never touched it.',
    cta: 'Flip my availability',
    ctaHref: APP,
    signoff: 'An empty two o’clock is a two o’clock nobody knows about yet.'
  },
  {
    file: '04-standing-appointments',
    subject: 'Your every-three-weeks regular should not have to rebook every three weeks',
    preheader: 'Standing appointments book the whole series and top it up automatically.',
    eyebrow: 'Introducing new',
    headline: 'Standing appointments.<br><em style="font-style:italic;color:#A2636C;">Set once, then forget.</em>',
    lede: 'You know the ones. Same client, same slot, every three weeks, and somehow you are still texting back and forth about it every single time. Turn any appointment into a standing appointment and MNC books the whole series for you.',
    panelLine: 'Every 1 to 4 weeks, held automatically, topped up as it runs down.',
    panelSub: 'Your regulars stop slipping through the cracks, and you stop chasing them.',
    listLabel: 'What it does for you',
    bullets: [
      'Pick any existing appointment and make it standing. That is the whole setup.',
      'Choose the rhythm: <strong>every 1, 2, 3 or 4 weeks</strong>.',
      'The series is topped up as it runs down, so the chair is always held out in front of you.',
      'Your week fills itself in, and you can see the whole thing in your Tech Portal.',
      '<strong>This is the part the paid booking tools charge you monthly for.</strong>'
    ],
    close: 'Your book should hold your regulars without you holding it together. Set the ones you already know by heart and watch a month of gaps close.',
    cta: 'Set up a standing appointment',
    ctaHref: APP,
    signoff: 'The regulars are the business. Everything else is a bonus.'
  },
  {
    file: '05-your-whole-book',
    subject: 'Walk-ins, reschedules and the note only you can see',
    preheader: 'Your whole book lives in your pocket now, not in three different places.',
    eyebrow: 'Introducing new',
    headline: 'Your whole book,<br><em style="font-style:italic;color:#A2636C;">in your pocket.</em>',
    lede: 'Half your clients came through the app. The other half texted you, called you, or walked in. Your book should hold all of them in one place, and now it does.',
    panelLine: 'Did you know you can change an appointment without a single DM?',
    panelSub: 'Reschedule, mark a no-show or cancel, from either side, and everyone gets told.',
    listLabel: 'Everything your book now holds',
    bullets: [
      '<strong>Add Appointment.</strong> Walk-in or phone client, you add them yourself and they land on your calendar instantly.',
      '<strong>Reschedule, no-show, cancel.</strong> Wired on both sides, so a change is a tap instead of a thread.',
      '<strong>Private notes on any booking.</strong> Polish colours, allergies, no-show history. Only you can ever see them.',
      '<strong>Block someone quietly.</strong> They are never told.',
      '<strong>New requests and your next appointment greet you on your Tech Portal</strong>, in the app, not just a push you might swipe away.'
    ],
    close: 'One calendar, everyone on it, and the context you need sitting right on the booking where you left it.',
    cta: 'Open my book',
    ctaHref: APP,
    signoff: 'A book you can trust is a book you stop worrying about.'
  },
  {
    file: '06-your-own-link-and-qr',
    subject: 'Your booking link goes anywhere. So does the QR code.',
    preheader: 'Instagram bio, a story, a card at your station. And every install is counted.',
    eyebrow: 'Introducing new',
    headline: 'Your own link.<br><em style="font-style:italic;color:#A2636C;">Your own QR.</em>',
    lede: 'Tap <strong>Share My Profile</strong> in your Tech Portal and your personal booking link goes anywhere you want it: your Instagram bio, your stories, a text to a regular.',
    panelLine: 'Drop that same link into any free QR generator and print it for your station.',
    panelSub: 'One scan and a client lands on a page that is all you, with the app download right there.',
    listLabel: 'Where to put it this week',
    bullets: [
      '<strong>Your Instagram bio.</strong> The one place every client already looks for a way to book you.',
      '<strong>A story, once a week.</strong> Link sticker, three words, done.',
      '<strong>A card at your station.</strong> Print the QR and let clients scan it while their top coat cures.',
      '<strong>A text to your regulars.</strong> Better than explaining the app twice.',
      '<strong>It is measured.</strong> Every visit and every install your link brings home is counted.'
    ],
    close: 'Already book through Vagaro, GlossGenius or StyleSeat? Add that link to your profile and a Book Now button appears on you automatically. Every path still leads to you.',
    cta: 'Grab my link',
    ctaHref: APP,
    signoff: 'Your work does the convincing. The link just has to be reachable.'
  },
  {
    file: '07-what-it-costs',
    subject: 'What MNC costs, and the long list of what it does not',
    preheader: 'Free if you book elsewhere. Your free month starts when you turn booking on.',
    eyebrow: 'Introducing new',
    headline: 'Your free month starts<br><em style="font-style:italic;color:#A2636C;">when you are ready.</em>',
    lede: 'This is the change most techs have not heard yet. Your free month no longer starts ticking the day you signed up. It starts the moment you turn booking on, so nobody burns a trial while they were still setting up their gallery.',
    panelLine: 'And if you already book somewhere else, MNC is free.',
    panelSub: 'Your profile, your gallery, your place in the Gallery and your own booking link cost nothing, ever.',
    listLabel: 'The whole price list',
    bullets: [
      '<strong>Free, forever:</strong> your profile, your gallery, your place in the Gallery, your own booking link, Open today, and up to 50 photos a month.',
      '<strong>$10.99 a month</strong> is only for MNC’s own booking engine. No card to start.',
      '<strong>One flat price.</strong> Nothing that scales with how busy you get, and no tiers to compare.',
      '<strong>No commission. No per-booking fee.</strong> And never a charge to your clients.',
      '<strong>Cancel anytime.</strong> Your gallery and your calendar stay put either way.',
      '<strong>No slow-patch penalty.</strong> You are active until you take yourself down.'
    ],
    close: 'Nothing here is designed to catch you out. Turn booking on when your gallery is ready, and the month starts then.',
    cta: 'Turn booking on',
    ctaHref: APP,
    signoff: 'You should be able to read the price in one breath. That was the goal.'
  },
  {
    file: '08-your-work-stays-put',
    subject: 'The ombre you did last spring is still there next spring',
    preheader: 'Nothing autodeletes. Nothing scrolls into the void. It is your archive.',
    eyebrow: 'Introducing new',
    headline: 'Your work stays put.<br><em style="font-style:italic;color:#A2636C;">A portfolio that grows with you.</em>',
    lede: 'This is not a social feed. Nothing autodeletes, nothing scrolls into the void, and no algorithm decides today that your best set from March is finished being seen.',
    panelLine: 'Every photo you add is yours, and it is still there next year.',
    panelSub: 'Your portfolio, your archive, your show-and-tell.',
    listLabel: 'What that is worth',
    bullets: [
      '<strong>Photos never expire.</strong> The ombre you did last spring is still working for you next spring.',
      '<strong>Up to 50 looks a month, free.</strong> Almost nobody reaches it, and it refills every month.',
      '<strong>No pay-to-rank.</strong> Your share of the Gallery grows exactly with your photo count. No boosting, no mystery math.',
      '<strong>No slow-patch penalty.</strong> Quiet month? You stay active until you take yourself down.',
      '<strong>Mobile tech?</strong> Tag yourself Mobile and your street address is kept private automatically. Clients see your service area, not your home.'
    ],
    close: 'Post the whole portfolio. Not the highlights, the whole thing. It is the only place you have where adding work compounds instead of disappearing.',
    cta: 'Add to my gallery',
    ctaHref: APP,
    signoff: 'Instagram rents attention. Here, you own a billboard.'
  }
];

fs.mkdirSync(OUT, { recursive: true });
const index = [];
for (const e of EMAILS) {
  const file = e.file + '.html';
  fs.writeFileSync(path.join(OUT, file), render(e));
  index.push({ file, subject: e.subject, preheader: e.preheader });
}
fs.writeFileSync(path.join(OUT, 'subjects.json'), JSON.stringify(index, null, 2) + '\n');
console.log('wrote ' + EMAILS.length + ' emails to campaign/emails/');
for (const i of index) console.log('  ' + i.file + '  ' + i.subject);
