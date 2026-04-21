-- ────────────────────────────────────────────────────────────────────────
-- Liability acknowledgment columns
-- ────────────────────────────────────────────────────────────────────────
-- Adds the two columns the signup flow writes when a user ticks the
-- liability checkbox. Without these columns, PostgREST silently drops
-- the fields from the INSERT (so signups still work, but the audit
-- trail is lost).
--
-- liability_version       — which version of the agreement they accepted
--                           ('tech-v1' for techs, 'client-v1' for clients).
--                           Lets you know which wording was in effect when
--                           they agreed, in case you revise later.
-- liability_accepted_at   — exact UTC timestamp they ticked the box.
--                           Immutable audit record.
--
-- Safe to re-run. Nullable so existing rows (the 17 techs + admins) remain
-- valid. New signups will always populate both.
-- ────────────────────────────────────────────────────────────────────────

alter table public.users
  add column if not exists liability_version text,
  add column if not exists liability_accepted_at timestamptz;

alter table public.techs
  add column if not exists liability_version text,
  add column if not exists liability_accepted_at timestamptz;

-- Optional: index them if you'll later query "show me all users who
-- haven't accepted the latest version" when you revise the agreement.
-- create index if not exists users_liability_version_idx on public.users (liability_version);
-- create index if not exists techs_liability_version_idx on public.techs (liability_version);
