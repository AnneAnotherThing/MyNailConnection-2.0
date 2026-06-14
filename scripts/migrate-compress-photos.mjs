#!/usr/bin/env node
/**
 * One-time migration: re-compress existing oversized photos in the
 * `tech-photos` Supabase Storage bucket.
 *
 * WHY: photos were historically uploaded as full-resolution phone
 * originals (3–8MB). The app now compresses on upload, but photos that
 * were already in storage stay huge until re-processed. Since the MNC
 * Supabase project is NOT on the Pro plan, the on-the-fly image-resize
 * endpoint isn't available, so the only way to speed up EXISTING photos
 * is to download, downscale, and overwrite them in place. That's what
 * this does.
 *
 * It overwrites objects via upsert (no DELETE, the bucket's
 * protect_delete() trigger blocks SQL deletes, but upsert upload is fine).
 * Public URLs are preserved exactly, so nothing in the DB needs to change.
 *
 * ── SETUP (run once, from this folder) ───────────────────────────────
 *   npm init -y
 *   npm install @supabase/supabase-js sharp
 *
 * ── RUN ──────────────────────────────────────────────────────────────
 *   # 1) DRY RUN first, reports what WOULD change, touches nothing:
 *   SUPABASE_URL="https://ktiztunuifzbzwzyqrrq.supabase.co" \
 *   SERVICE_ROLE_KEY="<service_role key from Supabase > Settings > API>" \
 *   node migrate-compress-photos.mjs
 *
 *   # 2) When the dry-run looks right, do it for real:
 *   APPLY=1 SUPABASE_URL="..." SERVICE_ROLE_KEY="..." \
 *   node migrate-compress-photos.mjs
 *
 * On Windows PowerShell, set env vars with $env:NAME="value" on separate
 * lines, then run `node migrate-compress-photos.mjs`.
 *
 * ── ORIGINALS BACKUP (on by default) ─────────────────────────────────
 * Before overwriting any photo, the full-size original is copied to an
 * `_originals/<same path>` folder inside the SAME bucket. So if you ever
 * want a photo back, the untouched original is at `_originals/<path>`.
 * Backups only happen during APPLY, only once per photo (re-runs skip
 * anything already compressed), and the `_originals/` folder itself is
 * never processed. To turn the backup OFF, set KEEP_ORIGINALS=0.
 *
 * Note: backups roughly double storage use for the migrated photos until
 * you delete `_originals/` (do that from the Supabase dashboard once
 * you're confident, SQL deletes are blocked by a bucket trigger).
 *
 * SAFETY: uses the SERVICE ROLE key (admin). Keep it out of git. The
 * script only ever re-uploads a SMALLER version of an existing image and
 * skips anything that wouldn't shrink. Start with the dry run.
 */

import { createClient } from '@supabase/supabase-js';
import sharp from 'sharp';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SERVICE_ROLE_KEY;
const APPLY = process.env.APPLY === '1';
const KEEP_ORIGINALS = process.env.KEEP_ORIGINALS !== '0'; // on unless set to 0

const BUCKET = 'tech-photos';
const BACKUP_PREFIX = '_originals'; // untouched originals copied here
const MAX_DIM = 1400;          // longest edge for gallery photos
const JPEG_QUALITY = 82;
const MIN_BYTES_TO_TOUCH = 350 * 1024; // skip anything already <350KB

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SERVICE_ROLE_KEY env vars. See header comment.');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const IMG_RE = /\.(jpe?g|png|webp|heic|heif)$/i;

// Recursively walk the bucket. Supabase list() is per-prefix; folders show
// up as entries with a null `id`.
async function listAll(prefix = '') {
  const out = [];
  let offset = 0;
  const PAGE = 100;
  for (;;) {
    const { data, error } = await sb.storage.from(BUCKET).list(prefix, {
      limit: PAGE, offset, sortBy: { column: 'name', order: 'asc' },
    });
    if (error) { console.error('list error at', prefix, error.message); break; }
    if (!data || data.length === 0) break;
    for (const entry of data) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null) {
        // folder, recurse
        const nested = await listAll(path);
        out.push(...nested);
      } else {
        out.push({ path, meta: entry.metadata || {} });
      }
    }
    if (data.length < PAGE) break;
    offset += PAGE;
  }
  return out;
}

async function run() {
  console.log(`Mode: ${APPLY ? 'APPLY (will overwrite)' : 'DRY RUN (no changes)'}`);
  console.log('Listing bucket objects…');
  const all = await listAll('');
  const images = all.filter(o =>
    IMG_RE.test(o.path) && !o.path.startsWith(BACKUP_PREFIX + '/')); // never touch backups
  console.log(`Found ${all.length} objects, ${images.length} images.`);
  console.log(`Originals backup: ${KEEP_ORIGINALS ? 'ON -> ' + BACKUP_PREFIX + '/' : 'OFF'}\n`);

  let touched = 0, skipped = 0, savedBytes = 0, failed = 0, backed = 0;

  for (const { path, meta } of images) {
    const origSize = Number(meta.size) || 0;
    if (origSize && origSize < MIN_BYTES_TO_TOUCH) { skipped++; continue; }

    try {
      const { data: blob, error: dlErr } = await sb.storage.from(BUCKET).download(path);
      if (dlErr || !blob) { console.warn('  download failed:', path, dlErr?.message); failed++; continue; }
      const inputBuf = Buffer.from(await blob.arrayBuffer());

      const out = await sharp(inputBuf, { failOn: 'none' })
        .rotate() // respect EXIF orientation
        .resize({ width: MAX_DIM, height: MAX_DIM, fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: JPEG_QUALITY, mozjpeg: true })
        .toBuffer();

      if (out.length >= inputBuf.length) { skipped++; continue; } // wouldn't shrink

      const save = inputBuf.length - out.length;
      const bkLabel = KEEP_ORIGINALS ? `  [backup -> ${BACKUP_PREFIX}/${path}]` : '';
      console.log(`  ${APPLY ? 'compress' : 'would'} ${path}: ${(inputBuf.length/1024).toFixed(0)}KB -> ${(out.length/1024).toFixed(0)}KB  (-${(save/1024).toFixed(0)}KB)${bkLabel}`);

      if (APPLY) {
        // Back up the untouched original FIRST. copy() duplicates the
        // current (still-original) bytes server-side. If a backup already
        // exists (prior run), copy errors, that's fine, we keep the
        // first/true original and don't clobber it.
        if (KEEP_ORIGINALS) {
          const { error: cpErr } = await sb.storage.from(BUCKET).copy(path, `${BACKUP_PREFIX}/${path}`);
          if (cpErr && !/exist|dupl/i.test(cpErr.message || '')) {
            console.warn('  backup failed, skipping overwrite:', path, cpErr.message);
            failed++; continue; // don't overwrite if we couldn't back up
          }
          if (!cpErr) backed++;
        }
        const { error: upErr } = await sb.storage.from(BUCKET).upload(path, out, {
          upsert: true, contentType: 'image/jpeg',
        });
        if (upErr) { console.warn('  upload failed:', path, upErr.message); failed++; continue; }
      }
      touched++; savedBytes += save;
    } catch (e) {
      console.warn('  error on', path, e.message); failed++;
    }
  }

  console.log('\n──────── summary ────────');
  console.log(`${APPLY ? 'Compressed' : 'Would compress'}: ${touched}`);
  if (KEEP_ORIGINALS) console.log(`Originals backed up: ${backed}${APPLY ? '' : ' (would back up during APPLY)'}`);
  console.log(`Skipped (small/no gain): ${skipped}`);
  console.log(`Failed: ${failed}`);
  console.log(`Total ${APPLY ? 'saved' : 'savings available'}: ${(savedBytes/1024/1024).toFixed(1)} MB`);
  if (!APPLY) console.log('\nThis was a DRY RUN. Re-run with APPLY=1 to write changes.');
}

run().catch(e => { console.error(e); process.exit(1); });
