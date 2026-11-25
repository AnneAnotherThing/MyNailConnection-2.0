/* Visit counter for the answer pages and the tech gallery (2026-11-24).
   Same rules as the homepage tracker in marketing-v3.html: one row per
   browser per page per 30 minutes into public.marketing_hits, bots skipped,
   the same session id and the same "how did they get here" channel, so the
   admin page can count visits and visits from Google search.
   Usage: <script src="/visit.js" data-page="answer:nails-today" defer></script> */
(function () {
  try {
    var me = document.currentScript || document.querySelector('script[src*="visit.js"]');
    var PAGE = (me && me.getAttribute('data-page')) || 'other';
    var URL_ = 'https://nwqnakoongrorbwnrqzc.supabase.co';
    var KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53cW5ha29vbmdyb3Jid25ycXpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzNzczMjUsImV4cCI6MjA5ODk1MzMyNX0.TFFMlg9VjB0cyJwbgmVbeatFYQFaF1Ri0nrH0GwhHJs';
    var host = location.hostname;
    if (host !== 'mynailconnection.com' && host !== 'www.mynailconnection.com') return;
    var ua = navigator.userAgent || '';
    if (/bot|crawl|spider|scrape|preview|prerender|monitor|lighthouse|headlesschrome/i.test(ua)) return;
    var ls = null; try { ls = window.localStorage; } catch (_) {}
    var lastKey = 'mnc_mh_last:' + PAGE;
    if (ls) { var last = parseInt(ls.getItem(lastKey) || '0', 10); if (last && Date.now() - last < 30 * 60 * 1000) return; }
    var sid = ls && ls.getItem('mnc_anon_sid');
    if (!sid) {
      sid = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2);
      if (ls) try { ls.setItem('mnc_anon_sid', sid); } catch (_) {}
    }
    var q = {}; try { new URLSearchParams(location.search).forEach(function (v, k) { q[k] = v; }); } catch (_) {}
    var ref = document.referrer || '', rhost = '';
    try { rhost = ref ? new URL(ref).hostname.replace(/^www\./, '').toLowerCase() : ''; } catch (_) {}
    var src = (q.src || q.utm_source || '').toLowerCase(), med = (q.utm_medium || '').toLowerCase();
    var ch = 'direct';
    if (/qr/.test(src) || /qr/.test(med)) ch = 'qr';
    else if (/(facebook|instagram|tiktok|pinterest|snapchat|twitter|linkedin|youtube|\bfb\b|\big\b)/.test(src) || /social/.test(med)) ch = 'social';
    else if (src || med) ch = 'campaign';
    else if (/(google|bing|duckduckgo|yahoo|ecosia|brave|baidu|yandex)\./.test(rhost)) ch = 'search';
    else if (/(facebook|instagram|t\.co|tiktok|pinterest|lnkd\.in|youtube|reddit)/.test(rhost)) ch = 'social';
    else if (rhost && rhost !== host.replace(/^www\./, '')) ch = 'referral';
    var mobile = /Mobi|Android|iPhone|iPad|iPod/i.test(ua);
    fetch(URL_ + '/rest/v1/marketing_hits', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY, Prefer: 'return=minimal' },
      body: JSON.stringify({ session_id: sid, page: PAGE, referrer: ref.slice(0, 500) || null, device_type: mobile ? 'mobile' : 'desktop',
        entry_channel: ch, user_agent: ua.slice(0, 500), utm_source: q.utm_source || q.src || null, utm_medium: q.utm_medium || null, utm_campaign: q.utm_campaign || null }),
      keepalive: true
    }).then(function (r) { if (r && r.ok && ls) try { ls.setItem(lastKey, String(Date.now())); } catch (_) {} }).catch(function () {});
  } catch (_) {}
})();
