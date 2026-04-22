-- ============================================================================
-- MNC Photo Pause-on-Cancel Migration (2026-04-21)
-- ============================================================================
-- Adds "paused, not deleted" mechanics so a Glow Up cancellation preserves
-- a tech's portfolio but hides everything beyond the free limit from public
-- view. When the tech re-subscribes, paused photos are restored.
--
-- This exists to close the "$9 upload-everything-cancel-immediately" abuse
-- vector: without it, a tech could pay once, upload hundreds of photos, and
-- cancel, leaving a permanent unlimited portfolio for $9.
--
-- Data model:
--   public.techs.photos         — active photos (publicly visible)
--   public.techs.paused_photos  — photos hidden on cancellation (new column)
--
--   A photo object is shaped { url, tags, [paused_at] }. The paused_at
--   timestamp is stamped when an item is moved from photos → paused_photos
--   and stripped when restored. Legacy bare-string entries are normalized
--   into objects on first pause.
--
-- Safe to re-run (IF NOT EXISTS + CREATE OR REPLACE).
-- ============================================================================


-- ── BLOCK 1 — Schema ────────────────────────────────────────────────────────
alter table public.techs
  add column if not exists paused_photos jsonb not null default '[]'::jsonb;


-- ── BLOCK 2 — Pause photos beyond free limit ────────────────────────────────
-- Moves photos[free_limit..end] from public.techs.photos into
-- public.techs.paused_photos for every tech matching the given
-- stripe_customer_id. Stamps paused_at on newly paused items. Normalizes
-- legacy bare-string URL entries into {url, tags, paused_at} objects.
-- Safe to call when there's nothing to pause (no-op).
create or replace function public.pause_photos_beyond_free_limit(
  p_customer_id text,
  p_free_limit  int default 5
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_tech_id        uuid;
  v_photos         jsonb;
  v_existing_pause jsonb;
  v_keep           jsonb;
  v_pause          jsonb;
  v_now_text       text := (now() at time zone 'utc')::text;
  v_updated        int  := 0;
begin
  if p_customer_id is null or btrim(p_customer_id) = '' then
    return jsonb_build_object('ok', false, 'code', 'bad_customer_id');
  end if;

  for v_tech_id, v_photos, v_existing_pause in
    select id,
           coalesce(photos, '[]'::jsonb),
           coalesce(paused_photos, '[]'::jsonb)
      from public.techs
      where stripe_customer_id = p_customer_id
  loop
    if jsonb_array_length(v_photos) <= p_free_limit then
      continue;
    end if;

    -- Keep first N (upload-order); free-tier highlight reel
    select coalesce(jsonb_agg(elem order by idx), '[]'::jsonb) into v_keep
      from jsonb_array_elements(v_photos) with ordinality as t(elem, idx)
      where idx <= p_free_limit;

    -- Pause the rest; normalize bare-string legacy entries, stamp paused_at
    select coalesce(jsonb_agg(
      case
        when jsonb_typeof(elem) = 'string' then
          jsonb_build_object(
            'url', elem,
            'tags', '[]'::jsonb,
            'paused_at', to_jsonb(v_now_text)
          )
        when elem ? 'paused_at' then elem
        else elem || jsonb_build_object('paused_at', to_jsonb(v_now_text))
      end
      order by idx
    ), '[]'::jsonb) into v_pause
      from jsonb_array_elements(v_photos) with ordinality as t(elem, idx)
      where idx > p_free_limit;

    update public.techs
      set photos        = v_keep,
          paused_photos = v_existing_pause || v_pause
      where id = v_tech_id;

    v_updated := v_updated + 1;
  end loop;

  return jsonb_build_object('ok', true, 'updated', v_updated);
end;
$$;


-- ── BLOCK 3 — Restore paused photos ─────────────────────────────────────────
-- Appends all paused_photos back into photos (in the order they were paused)
-- and clears paused_photos. Strips paused_at from each restored item. Safe
-- no-op if nothing paused.
create or replace function public.resume_paused_photos(
  p_customer_id text
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_tech_id uuid;
  v_photos  jsonb;
  v_paused  jsonb;
  v_restore jsonb;
  v_updated int := 0;
begin
  if p_customer_id is null or btrim(p_customer_id) = '' then
    return jsonb_build_object('ok', false, 'code', 'bad_customer_id');
  end if;

  for v_tech_id, v_photos, v_paused in
    select id,
           coalesce(photos, '[]'::jsonb),
           coalesce(paused_photos, '[]'::jsonb)
      from public.techs
      where stripe_customer_id = p_customer_id
  loop
    if jsonb_array_length(v_paused) = 0 then
      continue;
    end if;

    select coalesce(jsonb_agg(
      case when jsonb_typeof(elem) = 'object' then elem - 'paused_at'
           else elem
      end
      order by idx
    ), '[]'::jsonb) into v_restore
      from jsonb_array_elements(v_paused) with ordinality as t(elem, idx);

    update public.techs
      set photos        = v_photos || v_restore,
          paused_photos = '[]'::jsonb
      where id = v_tech_id;

    v_updated := v_updated + 1;
  end loop;

  return jsonb_build_object('ok', true, 'updated', v_updated);
end;
$$;


-- ── BLOCK 4 — Grants ────────────────────────────────────────────────────────
-- The edge function hits these via the service role, which bypasses RLS.
-- Lock EXECUTE so anon/authenticated can't call them directly.
revoke all on function public.pause_photos_beyond_free_limit(text, int) from public;
revoke all on function public.resume_paused_photos(text)                 from public;

grant execute on function public.pause_photos_beyond_free_limit(text, int) to service_role;
grant execute on function public.resume_paused_photos(text)                to service_role;
