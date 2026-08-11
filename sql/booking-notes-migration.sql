-- ============================================================================
-- booking_notes: tech-private per-booking notes (2026-08-11, Anne:
-- "please give us a notes section for each booking")
--
-- Deliberately a SEPARATE TABLE, not a bookings.tech_note column. RLS is
-- row-level, not column-level, and the client leg of the bookings policies
-- lets a client select their own booking row — a note like "always
-- reschedules twice" must never ride along in that payload. This table has
-- tech + admin legs only, so the client it's about can never read it.
--
-- One note per booking (booking_id is the PK); the app upserts via
-- POST ...?on_conflict=booking_id with Prefer: resolution=merge-duplicates,
-- and deletes the row when the note is cleared.
--
-- Requires phone-auth Stage A helpers (public.current_email,
-- public.current_phone, public.phone_digits) and public.is_admin(), all
-- long since live. Runs in the Supabase SQL editor. Safe to re-run.
-- ============================================================================

begin;

create table if not exists public.booking_notes (
  booking_id uuid primary key references public.bookings(id) on delete cascade,
  tech_id    uuid not null references public.techs(id) on delete cascade,
  note       text not null default '',
  updated_at timestamptz not null default now()
);

create index if not exists booking_notes_tech_idx on public.booking_notes (tech_id);

alter table public.booking_notes enable row level security;

drop policy if exists bkn_select_self on public.booking_notes;
create policy bkn_select_self on public.booking_notes
  for select to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists bkn_insert_self on public.booking_notes;
create policy bkn_insert_self on public.booking_notes
  for insert to authenticated
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists bkn_update_self on public.booking_notes;
create policy bkn_update_self on public.booking_notes
  for update to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  )
  with check (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

drop policy if exists bkn_delete_self on public.booking_notes;
create policy bkn_delete_self on public.booking_notes
  for delete to authenticated
  using (
    tech_id in (select id from public.techs
                 where lower(email) = public.current_email()
                    or public.phone_digits(phone) = public.current_phone())
    or public.is_admin()
  );

commit;
