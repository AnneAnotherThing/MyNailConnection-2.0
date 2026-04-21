// Supabase Edge Function: admin-reset-passwords
// Bulk-resets every user's password to match their email.
// Only callable by verified admins (checked via the caller's JWT, not a
// pasted service_role key).
//
// Deploy with:
//   supabase functions deploy admin-reset-passwords
//
// No extra secrets needed — SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
// are auto-populated by the Supabase runtime.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Mirror the admin list from public.is_admin() in your SQL policies.
const ADMIN_EMAILS = new Set<string>([
  'annewilson1021@gmail.com',
]);

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST')    return json({ error: 'POST only' }, 405);

  try {
    // ── Step 1: extract caller's JWT ─────────────────────────────────────
    const auth = req.headers.get('Authorization') || '';
    const token = auth.replace(/^Bearer\s+/i, '');
    if (!token) return json({ error: 'missing auth token' }, 401);

    // ── Step 2: verify it with anon key and extract email ────────────────
    const anon = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: `Bearer ${token}` } } }
    );
    const { data: userRes, error: userErr } = await anon.auth.getUser(token);
    if (userErr || !userRes?.user?.email) {
      return json({ error: 'invalid token' }, 401);
    }
    const callerEmail = userRes.user.email.toLowerCase();
    if (!ADMIN_EMAILS.has(callerEmail)) {
      return json({ error: 'not an admin' }, 403);
    }

    // ── Step 3: admin client with service role, do the reset ─────────────
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const body = await req.json().catch(() => ({}));
    const dryRun: boolean = !!body.dryRun;

    // Fetch all emails from techs + users
    const [techsRes, usersRes] = await Promise.all([
      admin.from('techs').select('email').order('name', { ascending: true }),
      admin.from('users').select('email').order('name', { ascending: true }),
    ]);
    const emails = new Set<string>();
    for (const t of (techsRes.data || [])) if (t.email) emails.add(t.email.toLowerCase());
    for (const u of (usersRes.data || [])) if (u.email) emails.add(u.email.toLowerCase());

    if (dryRun) {
      return json({ dryRun: true, count: emails.size, emails: [...emails] });
    }

    // List auth users (paginate in case > 1000)
    const authUsers: Array<{ id: string; email?: string }> = [];
    let page = 1;
    while (true) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) break;
      authUsers.push(...data.users);
      if (data.users.length < 1000) break;
      page++;
    }

    let done = 0, failed = 0;
    const failures: string[] = [];
    for (const email of emails) {
      const u = authUsers.find(x => (x.email || '').toLowerCase() === email);
      if (!u) { failed++; failures.push(email); continue; }
      const { error } = await admin.auth.admin.updateUserById(u.id, { password: email });
      if (error) { failed++; failures.push(email); } else { done++; }
    }

    return json({ done, failed, failures });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}
