#!/usr/bin/env node
// ============================================================================
// generate-og-recovery-links.mjs
// ----------------------------------------------------------------------------
// For every email in public.tech_comps, generate a one-click sign-in URL via
// Supabase admin.generateLink. Output a CSV with email + first_name +
// recovery_link, ready to import into Resend as a contact list and merge into
// the OG launch letter ({{recovery_link}}).
//
// USAGE
//   1) Bump recovery token lifespan in Supabase first (Auth → Email Templates
//      → Recovery → token expiry, OR Auth Settings → mailer_otp_exp). Default
//      is 3600 (1h), set to 86400 (24h) or higher for launch so links don't
//      die between generation and tech click.
//
//   2) Set env vars and run:
//
//      export SUPABASE_URL='https://ktiztunuifzbzwzyqrrq.supabase.co'
//      export SUPABASE_SERVICE_ROLE='eyJ...'   # NEVER commit this
//      node scripts/generate-og-recovery-links.mjs > og-links.csv
//
//   3) Import og-links.csv into Resend as a contact list. The OG letter
//      uses {{first_name}} and {{recovery_link}} merge tags.
//
// REQUIREMENTS
//   - Node 18+ (uses native fetch via @supabase/supabase-js)
//   - npm install @supabase/supabase-js  (if not already in project)
//
// SECURITY
//   - Uses the service_role key. Never paste it in code, never commit it,
//     never share it. Run this script locally only.
//   - Each tech's recovery link gives one-time access to set a password on
//     their account. Treat the CSV like passwords until imported + sent.
// ============================================================================

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://ktiztunuifzbzwzyqrrq.supabase.co';
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE;

if (!SERVICE_ROLE) {
  console.error('✗ Missing SUPABASE_SERVICE_ROLE env var.');
  console.error('  Get it from: Supabase Dashboard → Project Settings → API → service_role secret');
  console.error('  Then: export SUPABASE_SERVICE_ROLE=\'eyJ...\'');
  process.exit(1);
}

// After clicking the link, Supabase redirects them here to set a password.
// reset-password.html already exists in the app deploy and is wired to handle this.
const REDIRECT_TO = 'https://mynailconnection.com/app/reset-password.html';

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { autoRefreshToken: false, persistSession: false }
});

// ── Pull every email in tech_comps (the OG cohort) ──────────────────────────
const { data: comps, error: compsErr } = await supabase
  .from('tech_comps')
  .select('email')
  .order('email');

if (compsErr) {
  console.error('✗ Failed to load tech_comps:', compsErr.message);
  process.exit(1);
}

if (!comps || comps.length === 0) {
  console.error('✗ tech_comps is empty. Did you run the prune SQL?');
  process.exit(1);
}

console.error(`Loaded ${comps.length} OG emails from tech_comps.`);

// ── Pull first_name (and email) from public.techs for the merge tag ─────────
const { data: techs, error: techsErr } = await supabase
  .from('techs')
  .select('email, first_name');

if (techsErr) {
  console.error('⚠ Could not load public.techs:', techsErr.message);
  console.error('  first_name column will be blank in CSV.');
}

const firstNameByEmail = new Map();
for (const t of techs || []) {
  if (t.email && t.first_name) {
    firstNameByEmail.set(t.email.toLowerCase(), t.first_name);
  }
}

// ── Generate links ──────────────────────────────────────────────────────────
console.log('email,first_name,recovery_link,note');

let success = 0;
let failed = 0;

for (const row of comps) {
  const email = (row.email || '').toLowerCase().trim();
  if (!email) continue;
  const first_name = firstNameByEmail.get(email) || '';

  let link = null;
  let note = '';

  // Try recovery first, works if the auth user already exists.
  const { data: rec, error: recErr } = await supabase.auth.admin.generateLink({
    type: 'recovery',
    email,
    options: { redirectTo: REDIRECT_TO }
  });

  if (rec?.properties?.action_link) {
    link = rec.properties.action_link;
    note = 'recovery';
  } else if (recErr && /not\s*found|user\s*not\s*found|no user/i.test(recErr.message || '')) {
    // Fallback: invite, creates the auth user AND returns the link in one call.
    const { data: inv, error: invErr } = await supabase.auth.admin.generateLink({
      type: 'invite',
      email,
      options: { redirectTo: REDIRECT_TO }
    });
    if (inv?.properties?.action_link) {
      link = inv.properties.action_link;
      note = 'invite (new auth user created)';
    } else {
      note = `error: invite also failed, ${invErr?.message || 'unknown'}`;
    }
  } else if (recErr) {
    note = `error: ${recErr.message}`;
  } else {
    note = 'error: no action_link returned';
  }

  // CSV-safe (escape commas in name)
  const safeName = (first_name || '').replace(/,/g, ' ');
  const safeLink = (link || '').replace(/,/g, '%2C');
  console.log(`${email},${safeName},${safeLink},${note}`);

  if (link) success++;
  else failed++;
}

console.error(`\n--- ${success} link${success === 1 ? '' : 's'} generated, ${failed} failed ---`);
if (failed > 0) {
  console.error('  Check the "note" column in the CSV to see why each failure happened.');
}
