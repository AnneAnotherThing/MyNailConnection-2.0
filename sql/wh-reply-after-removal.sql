-- MNC: after an admin takes a reply down, the tech can reply again
-- (Anne, 2026-10-11: "it says my reply was taken down but I can't put it back
-- up"). Remove is about one post; the ban ("Remove and stop posting") is what
-- keeps a person off the board, and wh_reply still refuses banned people.
-- Same function as in sql/build2-whats-happening.sql, copied here to run alone.
--
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query.
-- Proof this is the new copy: the insert below says "on conflict (request_id, tech_id)".

begin;

create or replace function public.wh_reply(
  p_request_id uuid, p_note text default '',
  p_show_book boolean default true, p_show_call boolean default true, p_show_text boolean default true
) returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me    text := public.wh_me_key();
  t     public.techs := public.wh_my_tech();
  r     public.wh_requests;
  v_cap int := coalesce((public.wh_setting('reply_daily_cap'))::text::int, 10);
  v_tz  text;
begin
  if t.id is null then
    return jsonb_build_object('ok', false, 'code', 'not_tech');
  end if;
  if exists (select 1 from public.wh_bans where person_key = me) then
    return jsonb_build_object('ok', false, 'code', 'banned');
  end if;
  select * into r from public.wh_requests where id = p_request_id;
  if r.id is null or r.status <> 'open' or r.expires_at <= now() then
    return jsonb_build_object('ok', false, 'code', 'closed');
  end if;
  if r.author_key = me then
    return jsonb_build_object('ok', false, 'code', 'own_request');
  end if;
  if public.wh_blocked(me, r.author_key) then
    return jsonb_build_object('ok', false, 'code', 'closed');
  end if;
  if exists (select 1 from public.wh_replies where request_id = r.id and tech_id = t.id and not removed) then
    return jsonb_build_object('ok', false, 'code', 'already');
  end if;
  v_tz := coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix');
  if (select count(*) from public.wh_replies
       where tech_key = me
         and created_at > ((date_trunc('day', now() at time zone v_tz)) at time zone v_tz)) >= v_cap then
    return jsonb_build_object('ok', false, 'code', 'daily_cap');
  end if;
  if not (coalesce(p_show_book, false) or coalesce(p_show_call, false) or coalesce(p_show_text, false)) then
    return jsonb_build_object('ok', false, 'code', 'pick_one');
  end if;

  -- A reply an admin took down leaves its row (removed = true); replying
  -- again revives that row as a fresh reply. A ban is checked above.
  insert into public.wh_replies (request_id, tech_id, tech_key, note, show_book, show_call, show_text)
  values (r.id, t.id, me, left(btrim(coalesce(p_note, '')), 280),
          coalesce(p_show_book, false), coalesce(p_show_call, false), coalesce(p_show_text, false))
  on conflict (request_id, tech_id) do update
    set tech_key = excluded.tech_key, note = excluded.note,
        show_book = excluded.show_book, show_call = excluded.show_call, show_text = excluded.show_text,
        removed = false, created_at = now();

  if coalesce((select p.reply_alerts from public.wh_prefs p where p.person_key = r.author_key), true) then
    perform public._booking_push(
      r.author_key,
      coalesce(nullif(btrim(t.name), ''), 'A tech') || ' is interested',
      left(coalesce(nullif(btrim(p_note), ''), 'Tap to see her reply to your request.'), 140),
      'wh-reply-' || r.id,
      'wh-reply'
    );
    perform public.wh_log('push_reply', null, r.id::text, t.id);
  end if;

  perform public.wh_log('reply', concat_ws(',', case when p_show_book then 'book' end, case when p_show_call then 'call' end, case when p_show_text then 'text' end), r.id::text, t.id);
  return jsonb_build_object('ok', true);
end $$;

commit;

-- Check, signed in as 2314 on a request whose earlier reply was taken down:
--   select public.wh_reply('<request uuid>', 'again', false, false, true);  -- {"ok": true}
