-- ============================================================================
-- MNC Signup RPC — Techs Stamp Fix  (2026-04-21)
-- ============================================================================
-- Patches public.create_signup_profile() to also stamp last_password_change
-- on public.techs when a new tech signs up.
--
-- The original migration (signup-profile-rpc-migration.sql) stamped
-- last_password_change = now() on the public.users INSERT but omitted it
-- from the public.techs INSERT. That meant fresh tech signups ended up with:
--
--   users.last_password_change  = now()  ✓
--   techs.last_password_change  = null   ✗
--
-- checkFirstLogin() in the app queries users first with the anon key. RLS on
-- public.users blocks anon reads, so the query returns empty and the function
-- falls through to the techs check — which is anon-readable (public
-- directory policy). It finds the null stamp and triggers the force-change
-- screen that was meant ONLY for temp-password recipients. So every brand-new
-- tech signup was getting unexpectedly force-changed.
--
-- Fix: include last_password_change in the techs INSERT. Safe to re-run.
-- ============================================================================

create or replace function public.create_signup_profile(
  p_email                 text,
  p_name                  text,
  p_role                  text,
  p_phone                 text default null,
  p_address               text default null,
  p_city                  text default null,
  p_state                 text default null,
  p_zip                   text default null,
  p_bio                   text default null,
  p_shop_name             text default null,
  p_hours_available       text default null,
  p_tags                  text[] default null,
  p_image_url             text default null,
  p_liability_version     text default null,
  p_liability_accepted_at timestamptz default null
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_now_date   date := (now() at time zone 'utc')::date;
  v_auth_id    uuid;
  v_created_at timestamptz;
begin
  if p_email is null or btrim(p_email) = '' then
    return jsonb_build_object('ok', false, 'code', 'bad_email', 'message', 'email is required');
  end if;
  if p_role not in ('client', 'tech') then
    return jsonb_build_object('ok', false, 'code', 'bad_role', 'message', 'role must be client or tech');
  end if;

  select id, created_at
    into v_auth_id, v_created_at
    from auth.users
   where lower(email) = lower(btrim(p_email))
     and created_at > now() - interval '5 minutes'
   order by created_at desc
   limit 1;

  if v_auth_id is null then
    return jsonb_build_object(
      'ok', false, 'code', 'no_recent_auth',
      'message', 'no auth.users row for this email created in the last 5 minutes'
    );
  end if;

  if not exists (select 1 from public.users where lower(email) = lower(btrim(p_email))) then
    begin
      insert into public.users (
        name, email, role, joined, phone, address, city, state, zip,
        bio, image_url, liability_version, liability_accepted_at,
        last_password_change
      ) values (
        p_name, p_email, p_role, v_now_date, p_phone, p_address, p_city, p_state, p_zip,
        p_bio, p_image_url, p_liability_version, p_liability_accepted_at,
        now()
      );
    exception when unique_violation then
      return jsonb_build_object('ok', false, 'code', '23505', 'message', sqlerrm,
                                'details', 'unique violation on public.users');
    end;
  end if;

  if p_role = 'tech' then
    if not exists (select 1 from public.techs where lower(email) = lower(btrim(p_email))) then
      begin
        -- FIX vs. original migration: include last_password_change = now()
        -- so fresh tech signups don't trip the first-login force-change flow.
        insert into public.techs (
          name, email, phone, address, city, state, zip, bio,
          shop_name, hours_available, tags, image_url,
          liability_version, liability_accepted_at,
          last_password_change
        ) values (
          p_name, p_email, p_phone, p_address, p_city, p_state, p_zip, p_bio,
          p_shop_name, p_hours_available, p_tags, p_image_url,
          p_liability_version, p_liability_accepted_at,
          now()
        );
      exception when unique_violation then
        return jsonb_build_object('ok', false, 'code', '23505', 'message', sqlerrm,
                                  'details', 'unique violation on public.techs');
      end;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'auth_id', v_auth_id);
end;
$$;


-- ── One-time backfill: stamp admin + test tech account ──────────────────────
-- Only run the line below that matches your current situation. Do NOT stamp
-- the 15 pre-populated techs whose auth_created is null — they'll get
-- stamped naturally when they go through the reset/invite flow to create
-- their Supabase login (reset-password.html stamps both tables).

update public.users
  set last_password_change = now()
  where email in ('anne@mynailconnection.com', 'leslie@mynailconnection.com')
    and last_password_change is null;

update public.techs
  set last_password_change = now()
  where email in ('leslie@mynailconnection.com', 'annewhite1021@gmail.com')
    and last_password_change is null;
