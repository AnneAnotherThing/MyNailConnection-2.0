-- MNC: duplicate photo guard, database half (2026-10-11).
-- Every upload gets a fresh file name (gallery/<techSlug>/<ms>-<rand>.<ext>),
-- so nothing noticed the same photo going up twice: Julieth's Gallery held 3
-- extra copies of 7 and 3 of her 4 feed posts were one image.
--
-- The app now hashes each pick in the browser (SHA-256) before a slot is
-- spent and refuses a repeat. Each photo in techs.photos carries:
--   hash      SHA-256 of the bytes we store in the bucket
--   src_hash  SHA-256 of the file she picked (new uploads only)
-- This file:
--   1. board_posts.image_hash, filled by the Release Wizard on new posts.
--   2. append_tech_photo refuses a photo whose hash or src_hash is already in
--      that tech's gallery, as well as the same URL (unchanged), so a build
--      that skips the browser check still cannot double a photo.
--
-- Run order: this file, then sql/photo-hash-backfill.sql (hashes for every
-- existing photo and post), then sql/photo-dedupe-cleanup.sql (removes the
-- extra copies Anne approved and adds the one-image-per-tech feed index).
-- Run this BEFORE the app code ships: new feed posts send image_hash, and
-- PostgREST refuses the insert if the column is missing.
-- Idempotent. Re-run freely.

begin;

alter table public.board_posts add column if not exists image_hash text;
comment on column public.board_posts.image_hash is 'SHA-256 of the posted image bytes (same value as the photo''s hash in techs.photos). Used to keep one feed post per image per tech.';
create index if not exists board_posts_image_hash_idx on public.board_posts (image_hash) where image_hash is not null;

-- Same body as sql/phone-auth-stage-c-photo-rpcs.sql, plus the hash check.
create or replace function public.append_tech_photo(p_email text, p_photo jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(p_email));
  v_url   text := p_photo ->> 'url';
  v_hash  text := nullif(p_photo ->> 'hash', '');
  v_src   text := nullif(p_photo ->> 'src_hash', '');
begin
  if v_email is null or v_email = '' then
    raise exception 'append_tech_photo: email required';
  end if;
  if v_url is null or v_url = '' then
    raise exception 'append_tech_photo: photo.url required';
  end if;

  update public.techs
     set photos = coalesce(photos, '[]'::jsonb) || p_photo
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email))
     -- Idempotency: skip if a photo with this exact URL already exists
     -- (network retries), or the same image is already in the gallery
     -- under another name (2026-10-11).
     and not exists (
       select 1
         from jsonb_array_elements(coalesce(photos, '[]'::jsonb)) p
        where p ->> 'url' = v_url
           or (v_hash is not null and (p ->> 'hash' = v_hash or p ->> 'src_hash' = v_hash))
           or (v_src  is not null and (p ->> 'hash' = v_src  or p ->> 'src_hash' = v_src))
     );
end;
$$;

grant execute on function public.append_tech_photo(text, jsonb) to authenticated;

commit;

-- Check: should return one row, image_hash, type text.
select column_name, data_type from information_schema.columns
 where table_schema = 'public' and table_name = 'board_posts' and column_name = 'image_hash';
