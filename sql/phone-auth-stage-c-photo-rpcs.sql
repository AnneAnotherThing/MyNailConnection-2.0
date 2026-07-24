-- ============================================================================
-- PHONE-AUTH STAGE C: photo pipeline accepts phone identity  (2026-07-24)
-- ============================================================================
-- The photo path's four RPCs all found the tech by email only, so a
-- phone-identity tech could not add or remove a single photo:
--   consume_upload_slot      -> returned not_found, upload gate refused
--   peek_upload_slots        -> tier read as empty
--   append_tech_photo        -> update matched zero rows, photo vanished
--   remove_tech_photo_by_url -> same
-- Each lookup now matches email OR phone (phone_digits both sides).
-- tech_comps stays email-keyed on purpose: comps are email-era grants.
-- Function bodies are otherwise byte-identical to their sources
-- (free-upload-counter-fix.sql, photo-autosave-rpcs.sql).
--
-- Requires Stage A (public.phone_digits). Safe to re-run.
-- ============================================================================

create or replace function public.consume_upload_slot(p_email text)
returns table (
  ok                 boolean,
  slot_type          text,
  reason             text,
  remaining_weekly   integer,
  remaining_credits  integer,
  weekly_reset_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tech_id         uuid;
  v_tier            text;
  v_expires_at      timestamptz;
  v_credits         integer;
  v_period_count    integer;
  v_period_reset    timestamptz;
  v_free_used       integer;
  v_comp_limit      integer;     -- non-null when the email has a comp
  v_free_limit      integer := 5;
  v_period_cap      integer;     -- resolved from tier or comp
  v_is_subscriber   boolean;
  v_slot_type       text;
  v_ok              boolean := false;
  v_reason          text    := 'capped';
  v_email           text    := lower(btrim(p_email));
begin
  -- Lock the techs row so parallel uploads can't both slip past the cap.
  select t.id,
         t.subscription_tier,
         t.subscription_expires_at,
         coalesce(t.photo_credits, 0),
         coalesce(t.period_upload_count, 0),
         t.period_reset_at,
         coalesce(t.lifetime_free_used, 0)
    into v_tech_id, v_tier, v_expires_at, v_credits, v_period_count, v_period_reset, v_free_used
    from public.techs t
    where (lower(t.email) = v_email
           or public.phone_digits(t.phone) = public.phone_digits(v_email))
    for update;

  if not found then
    return query select false, null::text, 'not_found'::text, 0, 0, null::timestamptz;
    return;
  end if;

  -- Comp check: a row in tech_comps overrides Stripe state. Comped techs
  -- are subscribers, period, with their own monthly_limit (default 25).
  select monthly_limit into v_comp_limit
    from public.tech_comps
   where email = v_email
   limit 1;

  if v_comp_limit is not null then
    v_is_subscriber := true;
    v_period_cap    := v_comp_limit;
  else
    v_is_subscriber := (v_tier = 'paid')
                       and (v_expires_at is null or v_expires_at > now());
    v_period_cap    := 25;
  end if;

  -- Lazy reset: month rolled over → zero the counter, advance the
  -- marker by another month. Same logic for both Stripe-paid and comped
  -- subscribers, they both use period_upload_count / period_reset_at.
  if v_is_subscriber and (v_period_reset is null or v_period_reset <= now()) then
    v_period_count := 0;
    v_period_reset := now() + interval '1 month';
  end if;

  -- Slot sources in order: subscription → credits → free.
  if v_is_subscriber and v_period_count < v_period_cap then
    v_period_count := v_period_count + 1;
    update public.techs
       set period_upload_count = v_period_count,
           period_reset_at     = v_period_reset
     where id = v_tech_id;
    v_slot_type := 'weekly';   -- wire-compat label; feed-eligible
    v_ok := true;
    v_reason := null;
  elsif v_credits > 0 then
    v_credits := v_credits - 1;
    update public.techs
       set photo_credits   = v_credits,
           period_reset_at = v_period_reset
     where id = v_tech_id;
    v_slot_type := 'credit';
    v_ok := true;
    v_reason := null;
  elsif (not v_is_subscriber) and v_free_used < v_free_limit then
    -- Real counter on a real column.
    v_free_used := v_free_used + 1;
    update public.techs
       set lifetime_free_used = v_free_used
     where id = v_tech_id;
    v_slot_type := 'free';
    v_ok := true;
    v_reason := null;
  else
    v_ok := false;
  end if;

  return query select
    v_ok,
    v_slot_type,
    v_reason,
    case when v_is_subscriber then greatest(0, v_period_cap - v_period_count) else 0 end,
    v_credits,
    case when v_is_subscriber then v_period_reset else null end;
end;
$$;

create or replace function public.peek_upload_slots(p_email text)
returns table (
  tier               text,
  is_subscriber      boolean,
  remaining_weekly   integer,
  remaining_credits  integer,
  free_remaining     integer,
  period_reset_at    timestamptz
)
language sql
security definer
set search_path = public
as $$
  with t as (
    select tt.subscription_tier,
           tt.subscription_expires_at,
           coalesce(tt.photo_credits, 0)         as credits,
           coalesce(tt.period_upload_count, 0)   as period_count,
           tt.period_reset_at                    as period_reset,
           coalesce(tt.lifetime_free_used, 0)    as free_used
      from public.techs tt
     where (lower(tt.email) = lower(btrim(p_email))
            or public.phone_digits(tt.phone) = public.phone_digits(p_email))
     limit 1
  ),
  c as (
    select monthly_limit
      from public.tech_comps
     where email = lower(btrim(p_email))
     limit 1
  ),
  resolved as (
    select
      coalesce(t.subscription_tier, 'free')                                      as raw_tier,
      (c.monthly_limit is not null)
        or (t.subscription_tier = 'paid' and (t.subscription_expires_at is null or t.subscription_expires_at > now()))
        as is_sub,
      coalesce(c.monthly_limit, 25)                                              as cap,
      t.credits, t.period_count, t.period_reset, t.free_used
    from t left join c on true
  )
  select
    raw_tier,
    is_sub,
    case when is_sub then greatest(0, cap - period_count) else 0 end,
    credits,
    case when is_sub then 0 else greatest(0, 5 - free_used) end,
    case when is_sub then period_reset else null end
  from resolved;
$$;

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
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email))
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
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email));

  update public.techs
     set photos = coalesce((
       select jsonb_agg(p)
         from jsonb_array_elements(coalesce(photos, '[]'::jsonb)) p
        where p ->> 'url' <> p_url
     ), '[]'::jsonb)
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email));

  select coalesce(jsonb_array_length(photos), 0)
    into v_after
    from public.techs
   where (lower(email) = v_email
          or public.phone_digits(phone) = public.phone_digits(v_email));

  -- Returns count of photos removed (usually 1; 0 means "URL not in
  -- array", which is fine, the in-modal preview was the only state).
  return greatest(0, coalesce(v_before, 0) - coalesce(v_after, 0));
end;
$$;

grant execute on function public.consume_upload_slot(text) to authenticated;
grant execute on function public.peek_upload_slots(text) to authenticated;
grant execute on function public.append_tech_photo(text, jsonb) to authenticated;
grant execute on function public.remove_tech_photo_by_url(text, text) to authenticated;
