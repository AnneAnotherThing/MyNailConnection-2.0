-- MNC: "Open this week" retired (Anne, 2026-10-09: "now!").
-- Being visible already means a client can call, text or book a tech, so the
-- week chip only ever fed a home-screen count and a filter. Open today stays
-- and is the one real-time signal until Build 2's "Techs available now".
--
-- The column is_same_day stays in the table (installed builds still send it
-- on every availability save); it is simply false everywhere, defaults to
-- false, and nothing reads it. The reset cron keeps only its Open today half.
--
-- Run AFTER sql/avail-reset-cron.sql. Idempotent.

begin;

alter table public.techs alter column is_same_day set default false;
update public.techs set is_same_day = false where is_same_day;

-- The stamp trigger: Open today only.
create or replace function public.techs_stamp_avail()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(new.is_available, false) then new.avail_set_at := now(); end if;
  else
    if coalesce(new.is_available, false) and not coalesce(old.is_available, false) then new.avail_set_at := now(); end if;
  end if;
  new.is_same_day := false;   -- retired flag can never come back on
  return new;
end $$;

drop trigger if exists techs_stamp_avail_trg on public.techs;
create trigger techs_stamp_avail_trg
  before insert or update of is_available, is_same_day on public.techs
  for each row execute function public.techs_stamp_avail();

-- The reset: Open today only. Same name and signature so the cron job is untouched.
create or replace function public.process_avail_resets()
returns table (today_off int, week_off int)
language plpgsql security definer
set search_path = public
as $$
declare
  v_today int := 0;
begin
  with cand as (
    select t.id
      from public.techs t
     where t.is_available
       and t.avail_set_at is not null
       and (now() at time zone coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix'))::date
         > (t.avail_set_at at time zone coalesce(t.avail_reminder_tz, t.booking_timezone, 'America/Phoenix'))::date
  )
  update public.techs t
     set is_available = false, avail_set_at = null
    from cand
   where t.id = cand.id;
  get diagnostics v_today = row_count;
  return query select v_today, 0;
end $$;

alter table public.techs drop column if exists week_set_at;

commit;

-- Check:
--   select count(*) filter (where is_same_day) as still_on from public.techs;   -- 0
--   select column_default from information_schema.columns where table_name = 'techs' and column_name = 'is_same_day';   -- false
