-- MNC: a tech can take back an Interested reply (Anne, 2026-10-11:
-- "shouldn't I be able to uncheck that too?"). The reply row is deleted, so
-- the client's reply list drops it, the request's reply count drops, and the
-- tech can reply again later (the unique request_id + tech_id row is gone;
-- the daily cap still counts the first one). An admin-removed reply
-- (removed = true) is not hers to take back and stays put.
--
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query.
-- Proof this is the new copy: the function below is wh_withdraw_reply.

begin;

create or replace function public.wh_withdraw_reply(p_request_id uuid) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me text := public.wh_me_key();
  t  public.techs := public.wh_my_tech();
  n  int;
begin
  if me is null or t.id is null then return jsonb_build_object('ok', false, 'code', 'not_tech'); end if;
  delete from public.wh_replies
   where request_id = p_request_id and tech_id = t.id and not removed;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  perform public.wh_log('unreply', null, p_request_id::text, t.id);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.wh_withdraw_reply(uuid) from public, anon;
grant execute on function public.wh_withdraw_reply(uuid) to authenticated;

commit;

-- Check, signed in as 2314 after replying to a request:
--   select public.wh_withdraw_reply('<request uuid>');  -- {"ok": true}, then the card offers I'm interested again
