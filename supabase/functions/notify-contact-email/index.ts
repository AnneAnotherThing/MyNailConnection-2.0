// Supabase Edge Function: notify-contact-email
// Emails Anne the "Contact the developer" note a user submits in the app,
// so she doesn't have to be logged in anywhere or check a table. Replaces the
// old push-to-anne@mynailconnection.com path, which only worked if she was
// signed into that account with notifications on (she never was).
//
// The note is ALSO saved to public.contact_anne_messages by the app before
// this is called; this function is just the heads-up email on top.
//
// Deploy with:
//   supabase functions deploy notify-contact-email
//
// Set secrets:
//   supabase secrets set RESEND_API_KEY="re_..."          # from resend.com
//   supabase secrets set NOTIFY_TO="you@youremail.com"    # where you want notes
//   supabase secrets set NOTIFY_FROM="MNC <notes@mynailconnection.com>"
//        # FROM must be an address on a domain you've verified in Resend.
//        # For a quick test with no domain, use: "onboarding@resend.dev"

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || '';
const NOTIFY_TO      = Deno.env.get('NOTIFY_TO') || '';
const NOTIFY_FROM    = Deno.env.get('NOTIFY_FROM') || 'onboarding@resend.dev';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function esc(s: string): string {
  return String(s || '').replace(/[<>&]/g, (c) =>
    c === '<' ? '&lt;' : c === '>' ? '&gt;' : '&amp;');
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST')    return json({ error: 'POST only' }, 405);

  if (!RESEND_API_KEY || !NOTIFY_TO) {
    return json({ error: 'not_configured', detail: 'Set RESEND_API_KEY and NOTIFY_TO secrets.' }, 500);
  }

  let p: Record<string, string> = {};
  try { p = await req.json(); } catch (_) { return json({ error: 'bad_json' }, 400); }

  const note  = (p.note || p.body || '').toString().trim();
  const name  = (p.name || '').toString().trim();
  const phone = (p.phone || '').toString().trim();
  const email = (p.email || '').toString().trim();
  const role  = (p.role || '').toString().trim();
  if (!note) return json({ error: 'empty_note' }, 400);

  const who = [name, role && '(' + role + ')'].filter(Boolean).join(' ') || 'Someone';
  const contactBits = [
    phone && 'Phone: ' + phone,
    email && 'Email: ' + email,
  ].filter(Boolean).join('  ·  ');

  const subject = `MNC note from ${name || phone || 'a user'}`;
  const html =
    `<div style="font-family:'DM Sans',Arial,sans-serif;max-width:560px;margin:0 auto;color:#141317;">` +
    `<div style="font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:#A2636C;font-weight:700;">My Nail Connection</div>` +
    `<h2 style="font-family:Georgia,serif;font-weight:600;margin:6px 0 2px;">A note from ${esc(who)}</h2>` +
    (contactBits ? `<div style="font-size:13px;color:#7A6E78;margin-bottom:14px;">${esc(contactBits)}</div>` : '') +
    `<div style="background:#FAF7F2;border:1px solid #E4D9DA;border-radius:12px;padding:16px 18px;font-size:15px;line-height:1.6;white-space:pre-wrap;">${esc(note)}</div>` +
    (phone ? `<div style="margin-top:14px;"><a href="sms:${esc(phone.replace(/[^\\d+]/g, ''))}" style="display:inline-block;background:#141317;color:#fff;text-decoration:none;font-weight:700;padding:10px 18px;border-radius:100px;font-size:14px;">Text ${esc(name || 'them')} back</a></div>` : '') +
    `<div style="font-size:11px;color:#918C81;margin-top:18px;">Sent from the Contact-the-developer form. The full note is also saved in contact_anne_messages.</div>` +
    `</div>`;

  try {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + RESEND_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: NOTIFY_FROM,
        to: NOTIFY_TO.split(',').map((s) => s.trim()).filter(Boolean),
        reply_to: email || undefined,
        subject,
        html,
      }),
    });
    if (!r.ok) {
      const detail = await r.text().catch(() => '');
      return json({ error: 'resend_failed', status: r.status, detail }, 502);
    }
    return json({ ok: true });
  } catch (e) {
    return json({ error: 'send_error', detail: String(e) }, 500);
  }
});
