-- MNC Build 1: partner ad tiles in the Gallery.
-- Handoff: vault punchlists/mnc-gallery-ad-and-feed-handoff.md (2026-10-09).
--
-- A partner ad is a square that sits in the Gallery among the nail photos,
-- labelled "Sponsored", and opens the partner's website when tapped. Ads are
-- entered on admin-stats.html (image upload, link, on or off); taps are
-- counted the way tech_taps counts Call, Text and Book.
--
--   partner_ads          the ads. Anyone can read the active ones, admins
--                        read all; writes go through the admin RPCs below.
--   partner_ad_taps      one row per tap. Anyone can insert, nobody can
--                        read except through admin_partner_ad_counts().
--   admin_save_partner_ad / admin_delete_partner_ad / admin_partner_ad_counts
--   storage bucket partner-ads (public read, admin write) for the images.
--
-- Safe to run any time; nothing in the app shows an ad until a row is on.
-- Idempotent. Re-run freely.

begin;

-- ── Ads ─────────────────────────────────────────────────────────────────────
create table if not exists public.partner_ads (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  title       text not null default '',
  image_url   text not null,
  href        text not null,
  active      boolean not null default true,
  sort        int not null default 0
);

alter table public.partner_ads enable row level security;

drop policy if exists partner_ads_read on public.partner_ads;
create policy partner_ads_read on public.partner_ads
  for select to anon, authenticated
  using (active or public.is_admin());

grant select on public.partner_ads to anon, authenticated;

create or replace function public.admin_save_partner_ad(
  p_id uuid, p_title text, p_image_url text, p_href text, p_active boolean, p_sort int
) returns public.partner_ads
language plpgsql security definer
set search_path = public
as $$
declare
  v_row public.partner_ads;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if coalesce(btrim(p_image_url), '') = '' or coalesce(btrim(p_href), '') = '' then
    raise exception 'image and link are required' using errcode = '22023';
  end if;
  if p_href !~* '^https?://' then
    raise exception 'link must start with http:// or https://' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.partner_ads (title, image_url, href, active, sort)
    values (coalesce(p_title, ''), btrim(p_image_url), btrim(p_href), coalesce(p_active, true), coalesce(p_sort, 0))
    returning * into v_row;
  else
    update public.partner_ads
       set title = coalesce(p_title, title),
           image_url = btrim(p_image_url),
           href = btrim(p_href),
           active = coalesce(p_active, active),
           sort = coalesce(p_sort, sort),
           updated_at = now()
     where id = p_id
     returning * into v_row;
    if v_row.id is null then
      raise exception 'ad not found' using errcode = 'P0002';
    end if;
  end if;
  return v_row;
end $$;

create or replace function public.admin_set_partner_ad(p_id uuid, p_active boolean)
returns public.partner_ads
language plpgsql security definer
set search_path = public
as $$
declare
  v_row public.partner_ads;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  update public.partner_ads set active = p_active, updated_at = now()
   where id = p_id returning * into v_row;
  return v_row;
end $$;

create or replace function public.admin_delete_partner_ad(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  delete from public.partner_ads where id = p_id;
end $$;

revoke all on function public.admin_save_partner_ad(uuid, text, text, text, boolean, int) from public, anon;
revoke all on function public.admin_set_partner_ad(uuid, boolean) from public, anon;
revoke all on function public.admin_delete_partner_ad(uuid) from public, anon;
grant execute on function public.admin_save_partner_ad(uuid, text, text, text, boolean, int) to authenticated;
grant execute on function public.admin_set_partner_ad(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_partner_ad(uuid) to authenticated;

-- ── Taps ────────────────────────────────────────────────────────────────────
create table if not exists public.partner_ad_taps (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  ad_id      uuid not null references public.partner_ads(id) on delete cascade,
  session_id text
);

create index if not exists partner_ad_taps_ad_created_idx
  on public.partner_ad_taps (ad_id, created_at desc);

alter table public.partner_ad_taps enable row level security;

drop policy if exists partner_ad_taps_insert_anyone on public.partner_ad_taps;
create policy partner_ad_taps_insert_anyone on public.partner_ad_taps
  for insert to anon, authenticated
  with check (true);

grant insert on public.partner_ad_taps to anon, authenticated;
grant usage, select on sequence public.partner_ad_taps_id_seq to anon, authenticated;

create or replace function public.admin_partner_ad_counts()
returns table (ad_id uuid, total int, last_30 int, last_tap timestamptz)
language sql security definer
set search_path = public
as $$
  select a.id,
         count(t.*)::int,
         coalesce(sum((t.created_at >= now() - interval '30 days')::int), 0)::int,
         max(t.created_at)
    from public.partner_ads a
    left join public.partner_ad_taps t on t.ad_id = a.id
   where public.is_admin()
   group by a.id;
$$;

revoke all on function public.admin_partner_ad_counts() from public, anon;
grant execute on function public.admin_partner_ad_counts() to authenticated;

-- ── Images: a public bucket admins can write to ─────────────────────────────
insert into storage.buckets (id, name, public)
values ('partner-ads', 'partner-ads', true)
on conflict (id) do update set public = true;

drop policy if exists partner_ads_public_read on storage.objects;
create policy partner_ads_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'partner-ads');

drop policy if exists partner_ads_admin_write on storage.objects;
create policy partner_ads_admin_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'partner-ads' and public.is_admin());

drop policy if exists partner_ads_admin_update on storage.objects;
create policy partner_ads_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'partner-ads' and public.is_admin());

drop policy if exists partner_ads_admin_delete on storage.objects;
create policy partner_ads_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'partner-ads' and public.is_admin());

commit;

-- Check:
--   select id, title, active from public.partner_ads;
--   select * from public.admin_partner_ad_counts();   -- as an admin session
