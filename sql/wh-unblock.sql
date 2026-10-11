-- MNC: unblock on What's happening (Build 2c follow-up, 2026-10-11).
-- A block was one way: wh_block() wrote the pair and nothing listed it or
-- undid it. The Alerts sheet behind the bell now shows "Blocked people"
-- with an Unblock button on each. Two RPCs, both scoped to the caller's
-- own rows through wh_me_key(); nobody can read or clear another person's
-- list. A block stays symmetric: if the other person also blocked you,
-- unblocking on your side alone does not bring their posts back.
--
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query.

begin;

-- The caller's own blocks, newest first, with a first name when one is
-- known (a tech's profile, else the client's user row).
create or replace function public.wh_my_blocks() returns jsonb
language sql stable security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'key',  b.blocked_key,
           'at',   b.created_at,
           'tech', exists (select 1 from public.techs t where public.wh_key(t.phone) = b.blocked_key),
           'name', coalesce(
             (select nullif(split_part(btrim(t.name), ' ', 1), '') from public.techs t
               where public.wh_key(t.phone) = b.blocked_key
               order by t.created_at desc limit 1),
             (select nullif(split_part(btrim(u.name), ' ', 1), '') from public.users u
               where public.wh_key(u.phone) = b.blocked_key
               order by u.created_at desc nulls last limit 1),
             '')
         ) order by b.created_at desc), '[]'::jsonb)
    from public.wh_blocks b
   where b.blocker_key = public.wh_me_key();
$$;

create or replace function public.wh_unblock(p_key text) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me text := public.wh_me_key();
  n  int;
begin
  if me is null then return jsonb_build_object('ok', false, 'code', 'sign_in'); end if;
  delete from public.wh_blocks where blocker_key = me and blocked_key = p_key;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  perform public.wh_log('unblock');
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.wh_my_blocks()      from public, anon;
revoke all on function public.wh_unblock(text)    from public, anon;
grant execute on function public.wh_my_blocks()   to authenticated;
grant execute on function public.wh_unblock(text) to authenticated;

commit;

-- Proof this is the new copy: the line below mentions wh_unblock.
-- Check, signed in as 2314: select public.wh_my_blocks();  -- [] until you block someone
