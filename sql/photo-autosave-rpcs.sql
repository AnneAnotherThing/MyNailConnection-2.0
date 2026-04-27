-- ========================================================================
-- MNC Photo Autosave RPCs  (2026-04-27)
-- ========================================================================
-- Two SECURITY DEFINER RPCs the client calls so each photo upload (and
-- each delete) persists immediately to public.techs.photos — no waiting
-- for the user to tap Save. Eliminates the "tech uploaded 8 photos, hit
-- back, lost everything" UX trap that just bit Anne.
--
-- Why RPCs instead of REST PATCH:
--   * Atomic JSONB array append/filter — no read-modify-write race when
--     two uploads complete near-simultaneously (which the bulk handler
--     does on every batch).
--   * Single trip — REST PATCH on a JSONB column requires the client
--     to first GET the current array, modify locally, then PATCH back.
--     Two round-trips per photo, with a race window in between.
--   * Email match is case-insensitive so this works regardless of the
--     casing-fix migration's deployment state.
--
-- Save button still has a job: bio / name / location / tag edits on
-- EXISTING photos all flow through saveTechEdit. Only the add-photo
-- and remove-photo paths go write-through.
-- ========================================================================


-- ────────────────────────────────────────────────────────────────────────
-- append_tech_photo — atomic JSONB array append.
-- Called after a storage upload returns the publicUrl. Idempotent on
-- duplicate URLs by checking before append (defensive — the upload-
-- and-append pair is short, but background uploads in the bulk handler
-- can race).
-- ────────────────────────────────────────────────────────────────────────

create or replace function public.append_tech_photo(p_email text, p_photo jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(p_email));
  v_url   text := p_photo ->> 'url';
begin
  if v_email is null or v_email = '' then
    raise exception 'append_tech_photo: email required';
  end if;
  if v_url is null or v_url = '' then
    raise exception 'append_tech_photo: photo.url required';
  end if;

  update public.techs
     set photos = coalesce(photos, '[]'::jsonb) || p_photo
   where lower(email) = v_email
     -- Defensive idempotency: skip if a photo with this exact URL
     -- already exists. The pre-Save flow could attempt re-append on
     -- network retries; this prevents duplicates without erroring.
     and not exists (
       select 1
         from jsonb_array_elements(coalesce(photos, '[]'::jsonb)) p
        where p ->> 'url' = v_url
     );
end;
$$;

grant execute on function public.append_tech_photo(text, jsonb) to authenticated;

comment on function public.append_tech_photo(text, jsonb) is
  'Atomic write-through append for tech portfolio uploads. Called by the client immediately after a storage upload returns its publicUrl, so photos persist without waiting for the Save button. Idempotent: duplicate URLs are silently skipped.';


-- ────────────────────────────────────────────────────────────────────────
-- remove_tech_photo_by_url — atomic JSONB array filter by URL.
-- Called from the in-modal "remove" button (removeTePhoto) so deletes
-- match the same write-through semantics as appends. Without this,
-- a tech could remove a photo locally, leave the modal, and find it
-- still in their portfolio next session.
-- ────────────────────────────────────────────────────────────────────────

create or replace function public.remove_tech_photo_by_url(p_email text, p_url text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text := lower(btrim(p_email));
  v_before  integer;
  v_after   integer;
begin
  if v_email is null or v_email = '' then
    raise exception 'remove_tech_photo_by_url: email required';
  end if;
  if p_url is null or p_url = '' then
    raise exception 'remove_tech_photo_by_url: url required';
  end if;

  select coalesce(jsonb_array_length(photos), 0)
    into v_before
    from public.techs
   where lower(email) = v_email;

  update public.techs
     set photos = coalesce((
       select jsonb_agg(p)
         from jsonb_array_elements(coalesce(photos, '[]'::jsonb)) p
        where p ->> 'url' <> p_url
     ), '[]'::jsonb)
   where lower(email) = v_email;

  select coalesce(jsonb_array_length(photos), 0)
    into v_after
    from public.techs
   where lower(email) = v_email;

  -- Returns count of photos removed (usually 1; 0 means "URL not in
  -- array", which is fine — the in-modal preview was the only state).
  return greatest(0, coalesce(v_before, 0) - coalesce(v_after, 0));
end;
$$;

grant execute on function public.remove_tech_photo_by_url(text, text) to authenticated;

comment on function public.remove_tech_photo_by_url(text, text) is
  'Atomic write-through delete for tech portfolio photos. Called by removeTePhoto so deletions persist without waiting for Save. Returns the number of photos removed (usually 1; 0 if the URL was not in the array, e.g., when the user deletes a still-uploading base64 preview).';
