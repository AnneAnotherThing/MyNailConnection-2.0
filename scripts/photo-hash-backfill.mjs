// Writes sql/photo-hash-backfill.sql: the SHA-256 of every stored gallery
// photo and feed image, so the duplicate guard (sql/photo-dedupe-hash.sql)
// also knows photos uploaded before it existed. Read only against the
// project: it downloads each public image and hashes it; Anne runs the SQL.
//
//   node scripts/photo-hash-backfill.mjs
//
// Re-run any time old installed builds (which do not hash) have added
// photos; the SQL only fills hashes that are missing.
// Reads techs with the anon key from index.html. Once anon loses select on
// techs (sql/build0-step4-revoke-public-techs.sql), set MNC_KEY in the shell
// to a key that can read techs. Never commit a key.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const URL_BASE = html.match(/SUPABASE_URL\s*=\s*['"]([^'"]+)/)[1];
const KEY = process.env.MNC_KEY || html.match(/SUPABASE_ANON_KEY\s*=\s*['"]([^'"]+)/)[1];
const H = { apikey: KEY, Authorization: 'Bearer ' + KEY };

async function rest(q) {
  const r = await fetch(URL_BASE + '/rest/v1/' + q, { headers: H });
  if (!r.ok) throw new Error(q + ' -> ' + r.status + ' ' + (await r.text()));
  return r.json();
}

const techs = await rest('techs?select=id,photos');
const posts = await rest('board_posts?select=id,image_url&image_url=not.is.null');
const urls = new Set();
for (const t of techs) for (const p of (t.photos || [])) {
  const u = typeof p === 'string' ? p : p && p.url;
  if (u && u.startsWith('http')) urls.add(u);
}
for (const p of posts) if (p.image_url.startsWith('http')) urls.add(p.image_url);

const list = [...urls], out = new Map(), errors = [];
let i = 0;
async function worker() {
  while (i < list.length) {
    const u = list[i++];
    try {
      const r = await fetch(u);
      if (!r.ok) { errors.push(r.status + ' ' + u); continue; }
      out.set(u, crypto.createHash('sha256').update(Buffer.from(await r.arrayBuffer())).digest('hex'));
    } catch (e) { errors.push(String(e) + ' ' + u); }
  }
}
await Promise.all(Array.from({ length: 6 }, worker));

const q = s => "'" + s.replace(/'/g, "''") + "'";
const rows = [...out].sort((a, b) => a[0].localeCompare(b[0])).map(([u, h]) => '  (' + q(u) + ', ' + q(h) + ')');
const stamp = new Date().toISOString();
const sql = `-- MNC: SHA-256 for every stored photo and feed image (duplicate guard backfill).
-- Generated ${stamp} by scripts/photo-hash-backfill.mjs from ${out.size} images
-- (${techs.length} techs, ${posts.length} feed posts with an image).
-- Run AFTER sql/photo-dedupe-hash.sql. Only fills hashes that are missing,
-- so re-running it, or a newer copy of it, is safe.

-- One statement, so it runs whole or not at all, in any SQL client (the
-- Supabase editor does not keep a temporary table between statements).
with h(url, hash) as (values
${rows.join(',\n')}
),
-- techs.photos: add "hash" to each photo object that lacks one, order kept.
t_up as (
  update public.techs t
     set photos = (
       select jsonb_agg(
                case when jsonb_typeof(e.p) = 'object' and coalesce(e.p ->> 'hash', '') = '' and hh.hash is not null
                     then e.p || jsonb_build_object('hash', hh.hash)
                     else e.p end
                order by e.o)
         from jsonb_array_elements(t.photos) with ordinality e(p, o)
         left join h hh on hh.url = e.p ->> 'url')
   where exists (
     select 1
       from jsonb_array_elements(coalesce(t.photos, '[]'::jsonb)) p
       join h hh on hh.url = p ->> 'url'
      where coalesce(p ->> 'hash', '') = '')
  returning 1
),
-- board_posts: image_hash from the same list.
b_up as (
  update public.board_posts b
     set image_hash = hh.hash
    from h hh
   where b.image_url = hh.url
     and b.image_hash is null
  returning 1
)
select (select count(*) from t_up) as techs_updated,
       (select count(*) from b_up) as posts_updated;

-- Check: photos and posts still without a hash (both should be 0, or only
-- images uploaded after this file was generated).
select
  (select count(*) from public.techs t, jsonb_array_elements(coalesce(t.photos, '[]'::jsonb)) p
    where coalesce(p ->> 'hash', '') = '') as photos_without_hash,
  (select count(*) from public.board_posts where image_url is not null and image_hash is null) as posts_without_hash;
`;
fs.writeFileSync(path.join(root, 'sql', 'photo-hash-backfill.sql'), sql);
console.log('wrote sql/photo-hash-backfill.sql:', out.size, 'images hashed,', errors.length, 'failed');
for (const e of errors) console.log('  failed', e);
