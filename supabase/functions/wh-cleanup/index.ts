// Supabase Edge Function: wh-cleanup
// Deletes the photo from a What's happening request a week after the request
// ended (found, taken down, removed or ran out of time), then clears the
// request's photo_url. Called every night by public.wh_nightly() (pg_cron);
// safe to call by hand or more often, it only ever touches photos that are
// already due. Built 2026-10-11 so request photos never pile up in storage.
//
// Why an edge function: Supabase does not allow deleting storage files from
// SQL, only through the Storage API, which needs the service role.
//
// Deploy with:
//   supabase functions deploy wh-cleanup
//
// Secrets: none beyond the SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY every
// function already gets.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const BUCKET = 'wh-photos';
const MARKER = '/storage/v1/object/public/' + BUCKET + '/';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } },
  );

  let removed = 0;
  // Up to five batches of 500 per run; anything left waits for tomorrow.
  for (let round = 0; round < 5; round++) {
    const { data: due, error } = await sb.rpc('wh_photos_to_clean', { p_limit: 500 });
    if (error) return json({ ok: false, step: 'list', error: error.message, removed }, 500);
    const rows = (due ?? []) as { id: string; photo_url: string }[];
    if (!rows.length) break;

    const paths = rows
      .map((r) => {
        const at = (r.photo_url || '').indexOf(MARKER);
        return at >= 0 ? decodeURIComponent(r.photo_url.slice(at + MARKER.length)) : '';
      })
      .filter((p) => p.startsWith('requests/'));

    if (paths.length) {
      const { error: delErr } = await sb.storage.from(BUCKET).remove(paths);
      if (delErr) return json({ ok: false, step: 'delete', error: delErr.message, removed }, 500);
    }

    const { error: markErr } = await sb.rpc('wh_photos_cleaned', { p_ids: rows.map((r) => r.id) });
    if (markErr) return json({ ok: false, step: 'mark', error: markErr.message, removed }, 500);
    removed += paths.length;
    if (rows.length < 500) break;
  }

  return json({ ok: true, removed });
});
