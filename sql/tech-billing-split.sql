-- ============================================================================
-- tech-billing-split.sql  (2026-09-18)
--
-- Moves the four billing identifiers OFF public.techs into a service-role-only
-- table, because techs is readable with the app's public anon key (guest
-- browse uses select=* against it) and was handing back every tech's
-- stripe_customer_id, revenuecat_app_user_id, apple_original_transaction_id
-- and google_purchase_token to anyone who asked. Found on the waggle
-- 2026-09-17 (board item c-privacyhole).
--
-- Why a table split and not column-level REVOKE: the shipped native builds
-- (v3.0.4) browse with select=*, and Postgres fails a select=* outright when
-- the role is missing ANY column privilege. Dropping the columns from techs
-- instead means old builds keep working: the keys simply stop appearing in
-- responses, and no client code reads them (verified: zero references in
-- index.html).
--
-- RUN ORDER (matters, do not run both parts back to back):
--   1. Run PART A below.
--   2. Claude deploys the updated edge functions
--      (stripe-webhook, revenuecat-webhook, delete-account).
--   3. Run PART B. It re-copies anything the old function code wrote during
--      the window, then drops the columns from techs.
--
-- Read-only checks at the bottom. Re-runnable; each statement guards.
-- ============================================================================


-- ████ PART A, run FIRST ████████████████████████████████████████████████████

-- ── 1. The billing table, service-role only ────────────────────────────────
create table if not exists public.tech_billing (
  tech_id                       uuid primary key
                                references public.techs(id) on delete cascade,
  stripe_customer_id            text,
  revenuecat_app_user_id        text,
  apple_original_transaction_id text,
  google_purchase_token         text,
  updated_at                    timestamptz not null default now()
);

create index if not exists tech_billing_stripe_idx
  on public.tech_billing (stripe_customer_id);
create index if not exists tech_billing_rc_idx
  on public.tech_billing (revenuecat_app_user_id);

-- RLS on with NO policies: only the service role (which bypasses RLS) can
-- touch it. Belt and suspenders: revoke the table grants too, so even a
-- future permissive policy can't quietly reopen it to the public roles.
alter table public.tech_billing enable row level security;
revoke all on public.tech_billing from anon, authenticated;

comment on table public.tech_billing is
  'Billing identifiers split off public.techs 2026-09-18 because techs is anon-readable (guest browse). Service role only: RLS enabled with no policies, grants revoked. Written by stripe-webhook / revenuecat-webhook; read by those plus delete-account and the paused-photos RPCs.';

-- ── 2. Copy current values across ──────────────────────────────────────────
insert into public.tech_billing
  (tech_id, stripe_customer_id, revenuecat_app_user_id,
   apple_original_transaction_id, google_purchase_token)
select id, stripe_customer_id, revenuecat_app_user_id,
       apple_original_transaction_id, google_purchase_token
  from public.techs
 where stripe_customer_id is not null
    or revenuecat_app_user_id is not null
    or apple_original_transaction_id is not null
    or google_purchase_token is not null
on conflict (tech_id) do update set
  stripe_customer_id            = coalesce(excluded.stripe_customer_id,            tech_billing.stripe_customer_id),
  revenuecat_app_user_id        = coalesce(excluded.revenuecat_app_user_id,        tech_billing.revenuecat_app_user_id),
  apple_original_transaction_id = coalesce(excluded.apple_original_transaction_id, tech_billing.apple_original_transaction_id),
  google_purchase_token         = coalesce(excluded.google_purchase_token,         tech_billing.google_purchase_token),
  updated_at                    = now();

-- ── 3. Re-point the three DB functions that read techs.stripe_customer_id ──

-- 3a. resume_paused_photos: identical to photo-pause-migration.sql BLOCK 3,
--     except the tech lookup goes through tech_billing.
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
    select t.id,
           coalesce(t.photos, '[]'::jsonb),
           coalesce(t.paused_photos, '[]'::jsonb)
      from public.techs t
      join public.tech_billing b on b.tech_id = t.id
      where b.stripe_customer_id = p_customer_id
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

-- 3b. pause_photos_beyond_free_limit: retired from the live flow on
--     2026-07-05 (photos are permanent in the 3.0 model) but kept for
--     rollback, so it must keep compiling after the column drop. Same
--     lookup change as 3a.
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
    select t.id,
           coalesce(t.photos, '[]'::jsonb),
           coalesce(t.paused_photos, '[]'::jsonb)
      from public.techs t
      join public.tech_billing b on b.tech_id = t.id
      where b.stripe_customer_id = p_customer_id
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

-- 3c. sync_tech_comp_to_techs: the comps trigger's DELETE branch checked
--     stripe_customer_id is null before reverting to free. Same rule, new
--     home for the flag.
create or replace function public.sync_tech_comp_to_techs()
returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.techs
       set subscription_tier       = 'paid',
           subscription_expires_at = null,
           period_upload_count     = coalesce(period_upload_count, 0),
           period_reset_at         = coalesce(period_reset_at, now() + interval '1 month')
     where lower(email) = lower(new.email);
    return new;
  elsif tg_op = 'DELETE' then
    -- Revert to 'free' only if no Stripe subscription is backing the
    -- row. If a Stripe sub IS active, leave the tier alone, the webhook
    -- is the authority for that lifecycle.
    update public.techs t
       set subscription_tier       = 'free',
           subscription_expires_at = null
     where lower(t.email) = lower(old.email)
       and not exists (select 1 from public.tech_billing b
                        where b.tech_id = t.id
                          and b.stripe_customer_id is not null);
    return old;
  elsif tg_op = 'UPDATE' then
    -- Only matters if email changed (rare). Re-apply on the new email.
    if lower(new.email) <> lower(old.email) then
      update public.techs
         set subscription_tier       = 'paid',
             subscription_expires_at = null
       where lower(email) = lower(new.email);
    end if;
    return new;
  end if;
  return null;
end;
$$;

-- ── A verify ───────────────────────────────────────────────────────────────
-- select count(*) rows, count(stripe_customer_id) stripe, count(revenuecat_app_user_id) rc
--   from public.tech_billing;
-- Expect: rows >= number of techs that ever paid or hit a store; stripe >= 1.


-- ████ PART B, run ONLY after the edge functions are redeployed ████████████

-- ── 4. Re-copy anything old function code wrote during the window ─────────
-- insert into public.tech_billing
--   (tech_id, stripe_customer_id, revenuecat_app_user_id,
--    apple_original_transaction_id, google_purchase_token)
-- select id, stripe_customer_id, revenuecat_app_user_id,
--        apple_original_transaction_id, google_purchase_token
--   from public.techs
--  where stripe_customer_id is not null
--     or revenuecat_app_user_id is not null
--     or apple_original_transaction_id is not null
--     or google_purchase_token is not null
-- on conflict (tech_id) do update set
--   stripe_customer_id            = coalesce(excluded.stripe_customer_id,            tech_billing.stripe_customer_id),
--   revenuecat_app_user_id        = coalesce(excluded.revenuecat_app_user_id,        tech_billing.revenuecat_app_user_id),
--   apple_original_transaction_id = coalesce(excluded.apple_original_transaction_id, tech_billing.apple_original_transaction_id),
--   google_purchase_token         = coalesce(excluded.google_purchase_token,         tech_billing.google_purchase_token),
--   updated_at                    = now();

-- ── 5. Drop the exposed columns ────────────────────────────────────────────
-- alter table public.techs
--   drop column if exists stripe_customer_id,
--   drop column if exists revenuecat_app_user_id,
--   drop column if exists apple_original_transaction_id,
--   drop column if exists google_purchase_token;

-- ── B verify ───────────────────────────────────────────────────────────────
-- After the drop, this must return zero rows:
--   select column_name from information_schema.columns
--    where table_schema='public' and table_name='techs'
--      and column_name in ('stripe_customer_id','revenuecat_app_user_id',
--                          'apple_original_transaction_id','google_purchase_token');
-- And an anon-key GET of /rest/v1/techs?select=* must no longer contain any
-- of the four keys (Claude runs this probe from the session).
--
-- Part B statements ship commented out so a copy-paste of the whole file
-- can never drop columns early. Uncomment 4 and 5 when you run Part B.
