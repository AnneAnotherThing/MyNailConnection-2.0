-- ─────────────────────────────────────────────────────────────────────────
-- MNC, Client-contact tap analytics
--
-- Run once in Supabase → SQL Editor. Idempotent / safe to re-run.
--
-- What it does:
--   Logs one row every time a CLIENT taps a way to reach a tech from that
--   tech's public profile: Call, Text, Book (MNC's own booking), or Book
--   via the tech's external link. The tech then sees her own counts on the
--   Tech Portal ("Clients reaching you"). This is engagement the tech owns —
--   no client identity is stored, just which button, for which tech, when.
--
-- Privacy / RLS:
--   * anon + authenticated may INSERT (a browsing client isn't always the
--     tech, and may be signed in as a client). No client PII is written.
--   * A tech reads ONLY her own totals, via the SECURITY DEFINER summary
--     RPC below, which resolves the caller to her tech row by email or phone
--     (same identity helpers the rest of the app uses) before returning any
--     number. There is no row-level SELECT for non-owners.
-- ─────────────────────────────────────────────────────────────────────────

begin;

create table if not exists public.tech_taps (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  tech_id    uuid not null references public.techs(id) on delete cascade,
  kind       text not null check (kind in ('call','text','book','book_link')),
  session_id text                    -- browser-local random id, coarse de-dupe only
);

create index if not exists tech_taps_tech_created_idx
  on public.tech_taps (tech_id, created_at desc);
create index if not exists tech_taps_tech_kind_idx
  on public.tech_taps (tech_id, kind);

alter table public.tech_taps enable row level security;

drop policy if exists tech_taps_insert_anyone on public.tech_taps;
create policy tech_taps_insert_anyone
  on public.tech_taps
  as permissive
  for insert
  to anon, authenticated
  with check (true);

-- No SELECT policy on purpose: reads go through tech_tap_summary() only.

grant insert on public.tech_taps to anon, authenticated;
grant usage, select on sequence public.tech_taps_id_seq to anon, authenticated;


-- ── Owner-only summary ────────────────────────────────────────────────────
-- Returns counts by kind, all-time and last 30 days, but ONLY when the caller
-- owns p_tech_id (or is an admin). Mirrors the identity match used elsewhere:
-- techs.email = current_email(), or the phone digits line up, phone-auth safe.
create or replace function public.tech_tap_summary(p_tech_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owns boolean;
  v_all  jsonb;
  v_30   jsonb;
begin
  select exists (
    select 1 from public.techs t
     where t.id = p_tech_id
       and (
            public.is_admin()
         or lower(coalesce(t.email,'')) = public.current_email()
         or (public.current_phone() is not null
             and right(public.phone_digits(t.phone), 10) = right(public.current_phone(), 10))
       )
  ) into v_owns;

  if not v_owns then
    return jsonb_build_object('ok', false, 'reason', 'not owner');
  end if;

  select jsonb_object_agg(kind, c) into v_all from (
    select kind, count(*)::int c from public.tech_taps
     where tech_id = p_tech_id group by kind
  ) s;

  select jsonb_object_agg(kind, c) into v_30 from (
    select kind, count(*)::int c from public.tech_taps
     where tech_id = p_tech_id and created_at >= now() - interval '30 days'
     group by kind
  ) s;

  return jsonb_build_object(
    'ok', true,
    'all_time', coalesce(v_all, '{}'::jsonb),
    'last_30',  coalesce(v_30,  '{}'::jsonb)
  );
end $$;

grant execute on function public.tech_tap_summary(uuid) to authenticated;


-- ── Admin per-tech rollup (for admin-stats.html) ──────────────────────────
-- One row per tech that has at least one tap, newest-activity context included.
-- Admin-only: the is_admin() predicate means a non-admin caller simply gets
-- zero rows. Books folds MNC's own booking; book_links is the external-link
-- taps, kept separate so the dashboard can show or combine them.
create or replace function public.admin_tech_tap_counts()
returns table (
  tech_id    uuid,
  tech_name  text,
  calls      int,
  texts      int,
  books      int,
  book_links int,
  total      int,
  last_30    int,
  last_tap   timestamptz
)
language sql
security definer
set search_path = public
as $$
  select t.id, t.name,
         coalesce(sum((tp.kind = 'call')::int), 0)::int,
         coalesce(sum((tp.kind = 'text')::int), 0)::int,
         coalesce(sum((tp.kind = 'book')::int), 0)::int,
         coalesce(sum((tp.kind = 'book_link')::int), 0)::int,
         count(tp.*)::int,
         coalesce(sum((tp.created_at >= now() - interval '30 days')::int), 0)::int,
         max(tp.created_at)
    from public.techs t
    join public.tech_taps tp on tp.tech_id = t.id
   where public.is_admin()
   group by t.id, t.name
   order by count(tp.*) desc, max(tp.created_at) desc;
$$;

grant execute on function public.admin_tech_tap_counts() to authenticated;

commit;

-- ── Verify ────────────────────────────────────────────────────────────────
-- insert into public.tech_taps (tech_id, kind) values ('<a real tech id>','call');
-- select public.tech_tap_summary('<that tech id>');   -- as that tech: ok:true with counts
-- select policyname, cmd, roles from pg_policies where tablename='tech_taps';
