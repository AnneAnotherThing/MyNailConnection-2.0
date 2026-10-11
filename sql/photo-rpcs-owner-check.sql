-- MNC: photo RPCs only touch the caller's own gallery (2026-10-11).
--
-- append_tech_photo and remove_tech_photo_by_url are SECURITY DEFINER, so
-- they run past RLS. Both found the tech row from the p_email argument alone
-- (email, or phone digits) and never asked who was calling. Any signed-in
-- user could POST /rest/v1/rpc/append_tech_photo or remove_tech_photo_by_url
-- with another tech's email or phone and add to or empty that tech's Gallery.
--
-- Now the row must also belong to the caller, the same test the techs RLS
-- owner policy uses (techs_update_self in phone-auth-stage-a-foundation.sql):
--   lower(email) = current_email()  or  phone_digits(phone) = current_phone()
-- Admins (is_admin(), by role or the users.admin flag) still pass. Anyone
-- else gets error 42501 (PostgREST answers 403) and nothing changes.
--
-- Bodies are otherwise the same as the latest sources:
--   append_tech_photo        sql/photo-dedupe-hash.sql (hash guard unchanged)
--   remove_tech_photo_by_url sql/phone-auth-stage-c-photo-rpcs.sql
-- Signatures and return types are unchanged, so the app needs no edit.
--
-- Also: execute is taken away from PUBLIC and anon. Postgres grants new
-- functions to PUBLIC by default, so a guest with the public key could reach
-- them too. Only signed-in users need them.
--
-- RUN ORDER: after sql/photo-dedupe-hash.sql. Re-running that file, or
-- phone-auth-stage-c-photo-rpcs.sql or photo-autosave-rpcs.sql, after this
-- one puts the hole back. This file is the latest definition of both.
--
-- Requires: current_email(), current_phone(), phone_digits(), is_admin().
-- Idempotent. Re-run freely.

begin;

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
  v_admin boolean := public.is_admin();
begin
  if v_email is null or v_email = '' then
    raise exception 'append_tech_photo: email required';
  end if;
  if v_url is null or v_url = '' then
    raise exception 'append_tech_photo: photo.url required';
  end if;

  -- Owner check (2026-10-11): the named row must be the caller's own.
  if not v_admin and not exists (
    select 1
      from public.techs t
     where (lower(t.email) = v_email
            or public.phone_digits(t.phone) = public.phone_digits(v_email))
       and (lower(t.email) = public.current_email()
            or public.phone_digits(t.phone) = public.current_phone())
  ) then
    raise exception 'append_tech_photo: not your gallery'
      using errcode = '42501';
  end if;

  update public.techs
     set photos = coalesce(photos, '[]'::jsonb) || p_photo
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email))
     and (v_admin
          or lower(email) = public.current_email()
          or public.phone_digits(phone) = public.current_phone())
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

create or replace function public.remove_tech_photo_by_url(p_email text, p_url text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text := lower(btrim(p_email));
  v_admin   boolean := public.is_admin();
  v_before  integer;
  v_after   integer;
begin
  if v_email is null or v_email = '' then
    raise exception 'remove_tech_photo_by_url: email required';
  end if;
  if p_url is null or p_url = '' then
    raise exception 'remove_tech_photo_by_url: url required';
  end if;

  -- Owner check (2026-10-11): the named row must be the caller's own.
  if not v_admin and not exists (
    select 1
      from public.techs t
     where (lower(t.email) = v_email
            or public.phone_digits(t.phone) = public.phone_digits(v_email))
       and (lower(t.email) = public.current_email()
            or public.phone_digits(t.phone) = public.current_phone())
  ) then
    raise exception 'remove_tech_photo_by_url: not your gallery'
      using errcode = '42501';
  end if;

  select coalesce(jsonb_array_length(photos), 0)
    into v_before
    from public.techs
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email))
     and (v_admin
          or lower(email) = public.current_email()
          or public.phone_digits(phone) = public.current_phone());

  update public.techs
     set photos = coalesce((
       select jsonb_agg(p)
         from jsonb_array_elements(coalesce(photos, '[]'::jsonb)) p
        where p ->> 'url' <> p_url
     ), '[]'::jsonb)
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email))
     and (v_admin
          or lower(email) = public.current_email()
          or public.phone_digits(phone) = public.current_phone());

  select coalesce(jsonb_array_length(photos), 0)
    into v_after
    from public.techs
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email))
     and (v_admin
          or lower(email) = public.current_email()
          or public.phone_digits(phone) = public.current_phone());

  -- Returns count of photos removed (usually 1; 0 means "URL not in
  -- array", which is fine, the in-modal preview was the only state).
  return greatest(0, coalesce(v_before, 0) - coalesce(v_after, 0));
end;
$$;

revoke execute on function public.append_tech_photo(text, jsonb) from public, anon;
revoke execute on function public.remove_tech_photo_by_url(text, text) from public, anon;
grant execute on function public.append_tech_photo(text, jsonb) to authenticated;
grant execute on function public.remove_tech_photo_by_url(text, text) to authenticated;

commit;

-- Check: both rows should show has_owner_check true, has_hash_guard true on
-- append, anon_can_run false, signed_in_can_run true.
select p.proname,
       position('not your gallery' in p.prosrc) > 0                 as has_owner_check,
       position('src_hash' in p.prosrc) > 0                         as has_hash_guard,
       has_function_privilege('anon', p.oid, 'execute')             as anon_can_run,
       has_function_privilege('authenticated', p.oid, 'execute')    as signed_in_can_run
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('append_tech_photo', 'remove_tech_photo_by_url')
 order by p.proname;
