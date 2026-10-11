-- MNC: a taken-down Interested reply no longer reads as "You said you're
-- interested" (2026-10-11, found while testing the take-back). wh_feed's
-- replied flag ignores rows an admin removed, and a new reply_removed flag
-- lets the card say the reply was taken down instead. Same function as in
-- sql/build2-whats-happening.sql, copied here so it runs on its own.
--
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query.
-- Proof this is the new copy: the function below contains reply_removed.

begin;

create or replace function public.wh_feed(p_city text default null, p_state text default null, p_kind text default null)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  me     text := public.wh_me_key();
  v_city text := lower(btrim(coalesce(p_city, '')));
  v_st   text := lower(btrim(coalesce(p_state, '')));
  v_out  jsonb;
begin
  if me is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if v_st = '' then
    select lower(public.wh_state(u.state, u.zip)) into v_st
      from public.users u where public.wh_key(u.phone) = me
     order by u.created_at desc nulls last limit 1;
    v_st := coalesce(v_st, '');
  end if;

  with items as (
    select 'request'::text as kind, r.id::text as id, r.created_at as at,
           r.city, r.state, r.body, r.photo_url as photo,
           split_part(btrim(r.author_name), ' ', 1) as name, r.author_image as image,
           null::uuid as tech_id, r.need_by, r.expires_at as ends_at,
           (r.author_key = me) as mine,
           (select count(*) from public.wh_replies x where x.request_id = r.id and not x.removed
              and not public.wh_blocked(r.author_key, x.tech_key))::int as replies,
           exists (select 1 from public.wh_replies x
                    where x.request_id = r.id and x.tech_key = me and not x.removed) as replied,
           exists (select 1 from public.wh_replies x
                    where x.request_id = r.id and x.tech_key = me and x.removed) as reply_removed
      -- Never the whole table: her own open requests, then the newest in her
      -- city, in her state and everywhere, each an indexed slice of 150.
      from (
        (select x.* from public.wh_requests x
          where x.author_key = me and x.status = 'open' and x.expires_at > now())
        union
        (select x.* from public.wh_requests x
          where v_city <> '' and x.status = 'open' and x.expires_at > now()
            and (v_st = '' or lower(btrim(x.state)) = v_st) and lower(btrim(x.city)) = v_city
          order by x.created_at desc limit 150)
        union
        (select x.* from public.wh_requests x
          where v_st <> '' and x.status = 'open' and x.expires_at > now()
            and lower(btrim(x.state)) = v_st
          order by x.created_at desc limit 150)
        union
        (select x.* from public.wh_requests x
          where x.status = 'open' and x.expires_at > now()
          order by x.created_at desc limit 150)
      ) r
     where (p_kind is null or p_kind = 'request')
       and not public.wh_blocked(me, r.author_key)
    union all
    -- Every tech with Open today on, however she turned it on (this
    -- screen, the chip on an older build, the morning prompt). A post from
    -- this screen adds her note and end time.
    select 'available', t.id::text, coalesce(a.created_at, t.avail_set_at, now()),
           t.city, public.wh_state(t.state, t.zip), coalesce(a.note, ''), null,
           t.name, t.image_url,
           t.id, null::date, a.until,
           (public.wh_key(t.phone) = me), 0, false, false
      from public.techs t
      left join public.wh_available a on a.tech_id = t.id
     where (p_kind is null or p_kind = 'available')
       and t.is_available
       and (a.tech_id is null or (not a.removed and a.until > now()))
       and public.wh_tech_in_view(t)
       and not public.wh_blocked(me, public.wh_key(t.phone))
    union all
    select 'photo', b.id::text, b.publish_at,
           t.city, public.wh_state(t.state, t.zip), b.body, b.image_url,
           t.name, t.image_url,
           t.id, null::date, null::timestamptz,
           (public.wh_key(t.phone) = me), 0, false, false
      from (select b0.*, row_number() over (partition by b0.tech_uuid order by b0.publish_at desc) as rn
              from (select b1.* from public.board_posts b1
                     where b1.image_url is not null
                       and b1.publish_at <= now() and b1.publish_at > now() - interval '60 days'
                     order by b1.publish_at desc limit 400) b0) b
      join public.techs t on t.id = b.tech_uuid
     where (p_kind is null or p_kind = 'photo')
       and b.rn <= 2
       and public.wh_tech_in_view(t)
       and not public.wh_blocked(me, public.wh_key(t.phone))
  ), ranked as (
    select i.*,
           case when v_city <> '' and lower(btrim(i.city)) = v_city
                     and (v_st = '' or lower(btrim(i.state)) = v_st) then 0
                when v_st <> '' and lower(btrim(i.state)) = v_st then 1
                else 2 end as near
      from items i
     order by near, at desc
     limit 100
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', kind, 'id', id, 'at', at, 'city', city, 'state', state,
           'body', body, 'photo', photo, 'name', name, 'image', image,
           'tech_id', tech_id, 'need_by', need_by, 'ends_at', ends_at,
           'mine', mine, 'replies', replies, 'replied', replied, 'reply_removed', reply_removed, 'near', near
         ) order by near, at desc), '[]'::jsonb)
    into v_out
    from ranked;
  return v_out;
end $$;

commit;

-- Check, signed in as 2314: select public.wh_feed(null, null, 'request');
--   a request whose reply was taken down comes back with "reply_removed": true and "replied": false
