-- MNC: when did each tech last open the app? (Anne, 2026-10-13: "do we have
-- any metrics on whether techs are opening the app?" We did not. Sign-ins
-- persist for weeks, so auth.users.last_sign_in_at goes stale, and board
-- opens only count the board.)
--
-- What this adds:
--   1. techs.last_opened_at: stamped by the app once a day per device when a
--      signed-in tech lands on her portal.
--   2. tech_opened(): the caller-scoped RPC that stamps it. Finds her techs
--      row from the JWT (same rule as wh_my_tech), so a tech can only ever
--      touch her own row and the app never needs a techs UPDATE policy for it.
-- admin-stats.html reads the column into the "Every tech" roster as
-- "Last opened".
--
-- Idempotent. Re-run freely. Copy the whole file into a FRESH query. Proof
-- this is the new copy: the function is named tech_opened.

begin;

alter table public.techs add column if not exists last_opened_at timestamptz;
create index if not exists techs_last_opened_idx on public.techs (last_opened_at desc nulls last);

create or replace function public.tech_opened() returns boolean
language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid := (public.wh_my_tech()).id;
begin
  if v_id is null then return false; end if;
  update public.techs set last_opened_at = now() where id = v_id;
  return true;
end $$;

revoke all on function public.tech_opened() from public, anon;
grant execute on function public.tech_opened() to authenticated;

commit;

-- Checks (SQL editor, as the project owner):
--   select column_name from information_schema.columns
--    where table_name = 'techs' and column_name = 'last_opened_at';        -- one row
--   Then open the app as 2314 (Tech Portal) and:
--   select name, last_opened_at from public.techs where last_opened_at is not null;
--   Who has gone quiet, once a week or two of data is in:
--   select name, city, created_at::date as joined, last_opened_at::date as last_opened
--     from public.techs order by last_opened_at asc nulls first;
