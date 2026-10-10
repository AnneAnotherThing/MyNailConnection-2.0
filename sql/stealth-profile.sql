-- MNC: a stealth tech profile, seen by nobody but its owner.
-- Anne, 2026-10-10: her tech account gives her the tech experience, but her
-- test photos and bookings should not show to clients or other techs.
--
-- techs.stealth = true keeps the row out of the browse lane (techs_public),
-- so the Gallery, Near Me, search, Open today counts and share links never
-- show her. Her own session still sees her row through the owner policy, so
-- the Tech Portal, My Gallery, bookings and settings work as for any tech.
-- Admins still see the row on admin-stats (they read techs directly).
-- tech_contact() refuses her phone to anyone but herself.
--
-- Run AFTER sql/build0-guest-lane.sql (it redefines techs_public).
-- Idempotent. Re-run freely. Set stealth = false to come back into view.

begin;

alter table public.techs add column if not exists stealth boolean not null default false;
comment on column public.techs.stealth is 'True = hidden from every browse surface; only the owner (by phone or email) and admins see this tech. Set by hand in SQL.';

create or replace view public.techs_public
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
from public.techs t
where not coalesce(t.stealth, false)
   or (t.email is not null and lower(t.email) = public.current_email())
   or (length(coalesce(public.phone_digits(t.phone), '')) >= 10
       and length(coalesce(public.current_phone(), '')) >= 10
       and right(public.phone_digits(t.phone), 10) = right(public.current_phone(), 10));

grant select on public.techs_public to anon, authenticated;

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
    and auth.role() = 'authenticated'
    and (
      not coalesce(t.stealth, false)
      or public.is_admin()
      or (length(coalesce(public.phone_digits(t.phone), '')) >= 10
          and length(coalesce(public.current_phone(), '')) >= 10
          and right(public.phone_digits(t.phone), 10) = right(public.current_phone(), 10))
    );
$$;

-- Anne's account (480-440-2314 is both her admin and her tech identity since
-- 2026-10-10; the old 699-6166 tech account was deleted).
update public.techs set stealth = true
 where right(public.phone_digits(phone), 10) = '4804402314';

commit;

-- Check (as anyone else, or with the public key): Anne is absent.
--   select name from public.techs_public where name ilike 'anne%';   -- no rows unless you are Anne
--   select name, stealth from public.techs where stealth;             -- Anne Wilson, true
