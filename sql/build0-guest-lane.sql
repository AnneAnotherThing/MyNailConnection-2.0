-- MNC Build 0, part 1 of 2: a safe public lane for browsing techs.
-- Handoff: vault punchlists/mnc-gallery-ad-and-feed-handoff.md (2026-10-09).
--
-- WHY. The techs table is readable with the app's public key, so a tech's
-- email, phone, home address, exact coordinates and account dates can be
-- read from outside the app, including addresses she set to hidden. This
-- file adds the pieces the app needs so that public read can be revoked:
--
--   1. is_admin() recognises the phone-only admin row as well as email.
--   2. techs_public: a view with only the columns browsing needs. Location
--      is rounded to two decimals (about a kilometre), so the map still
--      works but no pin lands on a house.
--   3. tech_contact(tech_id): phone, and the street address only when the
--      tech has not hidden it. Signed-in users only. Called at tap time.
--   4. tech_pop_by_id / tech_pop_counts_by_ids: favorites, hearts and the
--      joined date by tech id, so the app no longer needs a tech's email
--      or phone as the popularity key.
--   5. _booking_push sends the server key instead of the public key, so
--      send-push can refuse anonymous callers (see the function itself).
--
-- SAFE TO RUN NOW. Nothing here removes access; the current app keeps
-- working. The revoke is in build0-step4-revoke-public-techs.sql and runs
-- only after the store build that uses these pieces has reached phones.
--
-- Anne's one manual step before step 5 matters: create the server key.
--   select vault.create_secret('<a long random string>', 'mnc_push_server_key');
-- and set the same value as the edge function secret PUSH_SERVER_KEY
-- (supabase secrets set PUSH_SERVER_KEY=...). Until both exist, send-push
-- keeps accepting the public key, so nothing breaks in between.
--
-- Idempotent. Re-run freely.

-- ── 1. is_admin(): email OR phone, role compared without case ──────────────
create or replace function public.is_admin() returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where lower(coalesce(u.role, '')) = 'admin'
      and (
        (u.email is not null and lower(u.email) = public.current_email())
        or (length(coalesce(public.phone_digits(u.phone), '')) >= 10
            and length(coalesce(public.current_phone(), '')) >= 10
            and right(public.phone_digits(u.phone), 10) = right(public.current_phone(), 10))
      )
  );
$$;

-- ── 2. The public view ──────────────────────────────────────────────────────
-- Left out on purpose: email, phone, address, exact lat/lng, hours_available,
-- every reminder, billing, trial, credit, liability and password column.
drop view if exists public.techs_public;
create view public.techs_public
with (security_invoker = false)
as
select
  t.id,
  t.name,
  t.shop_name,
  t.initials,
  t.bg,
  t.color,
  t.image_url,
  t.bio,
  t.tags,
  t.services,
  t.photos,
  t.experience_level,
  t.city,
  t.state,
  t.zip,
  case when t.lat is null then null else round(t.lat::numeric, 2)::double precision end as lat,
  case when t.lng is null then null else round(t.lng::numeric, 2)::double precision end as lng,
  t.hide_address_public,
  t.contact_methods,
  t.is_available,
  t.is_same_day,
  t.accepting_new_clients,
  t.booking_enabled,
  t.booking_link,
  t.booking_timezone,
  t.booking_auto_confirm,
  t.booking_buffer_minutes,
  t.booking_min_notice_hours,
  t.listing_paused,
  t.paused_by_tech,
  t.joined,
  t.created_at,
  (t.subscription_tier = 'paid'
     and (t.subscription_expires_at is null or t.subscription_expires_at > now())) as is_subscriber,
  public.is_visible(t)  as is_visible,
  public.is_bookable(t) as is_bookable
from public.techs t;

comment on view public.techs_public is
  'Browse lane for the app. Safe columns only; location rounded to ~1 km. Replaces anon reads of public.techs (Build 0, 2026-10-09).';

grant select on public.techs_public to anon, authenticated;

-- ── 3. Contact details, signed-in users only, at tap time ───────────────────
create or replace function public.tech_contact(p_tech_id uuid)
returns table (phone text, address text, zip text)
language sql stable security definer
set search_path = public
as $$
  select
    t.phone,
    case when coalesce(t.hide_address_public, false) then null else t.address end as address,
    case when coalesce(t.hide_address_public, false) then null else t.zip end     as zip
  from public.techs t
  where t.id = p_tech_id
    and auth.role() = 'authenticated';
$$;

revoke all on function public.tech_contact(uuid) from public, anon;
grant execute on function public.tech_contact(uuid) to authenticated;

comment on function public.tech_contact(uuid) is
  'Phone for Call/Text, street address only when the tech shows it. Signed-in callers only. The app calls it when a profile opens, never for the list.';

-- ── 4. Popularity by tech id ────────────────────────────────────────────────
-- The old RPCs take an email-or-phone key. These wrap them by id so the app
-- never needs the key.
create or replace function public.tech_pop_by_id(p_tech_id uuid)
returns table (favs bigint, hearts bigint, joined timestamptz)
language sql stable security definer
set search_path = public
as $$
  select
    public.tech_fav_count(public.push_identity(t.email, t.phone))   as favs,
    public.tech_heart_count(public.push_identity(t.email, t.phone)) as hearts,
    (select u.joined from public.users u
      where (t.email is not null and lower(u.email) = lower(t.email))
         or (length(coalesce(public.phone_digits(t.phone), '')) >= 10
             and public.phone_digits(u.phone) = public.phone_digits(t.phone))
      limit 1) as joined
  from public.techs t
  where t.id = p_tech_id;
$$;

create or replace function public.tech_pop_counts_by_ids(p_ids uuid[])
returns table (tech_id uuid, favs bigint, hearts bigint)
language sql stable security definer
set search_path = public
as $$
  select
    t.id,
    public.tech_fav_count(public.push_identity(t.email, t.phone)),
    public.tech_heart_count(public.push_identity(t.email, t.phone))
  from public.techs t
  where t.id = any(p_ids);
$$;

grant execute on function public.tech_pop_by_id(uuid)        to anon, authenticated;
grant execute on function public.tech_pop_counts_by_ids(uuid[]) to anon, authenticated;

-- ── 5. _booking_push: server key, not the public key ────────────────────────
-- Same signature as sql/booking-reminders-observability.sql, so every cron
-- caller keeps working. The key comes from Vault; when it is not there yet
-- the function falls back to the public key and send-push keeps accepting
-- it until PUSH_SERVER_KEY is set on the function side. Both halves in
-- place = anonymous pushes refused.
create or replace function public._booking_push(
  p_user text, p_title text, p_body text, p_tag text, p_source text default 'unknown'
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  k_url  text := 'https://nwqnakoongrorbwnrqzc.supabase.co/functions/v1/send-push';
  k_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53cW5ha29vbmdyb3Jid25ycXpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzNzczMjUsImV4cCI6MjA5ODk1MzMyNX0.TFFMlg9VjB0cyJwbgmVbeatFYQFaF1Ri0nrH0GwhHJs';
  k_server text;
  v_request_id bigint;
begin
  if p_user is null or p_user = '' then
    insert into public.push_log (source, recipient, title, tag, request_id)
    values (p_source, '(no recipient)', p_title, p_tag, null);
    return;
  end if;

  begin
    select decrypted_secret into k_server
      from vault.decrypted_secrets
     where name = 'mnc_push_server_key'
     limit 1;
  exception when others then
    k_server := null;
  end;

  select net.http_post(
    url := k_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', k_anon,
      'Authorization', 'Bearer ' || k_anon,
      'x-mnc-server-key', coalesce(k_server, '')
    ),
    body := jsonb_build_object(
      'user_id', p_user, 'title', p_title, 'body', p_body,
      'url', '/app/', 'tag', p_tag, 'source', p_source
    )
  ) into v_request_id;

  insert into public.push_log (source, recipient, title, tag, request_id)
  values (p_source, p_user, p_title, p_tag, v_request_id);
end $$;

-- ── Check ───────────────────────────────────────────────────────────────────
-- select count(*) from public.techs_public;                        -- every tech
-- select * from public.techs_public limit 1;                        -- no email/phone/address columns
-- select public.is_admin();                                         -- true for an admin session
-- select * from public.tech_pop_counts_by_ids(array(select id from public.techs limit 3));
