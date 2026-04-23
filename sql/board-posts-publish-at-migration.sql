-- Staggered feed release
--
-- Adds a `publish_at` column to board_posts so portfolio auto-posts can
-- be scheduled to release one per hour instead of all at the upload
-- moment. Gives techs 5+ hours of feed presence from a 5-photo batch
-- instead of 1. First photo still releases immediately for instant
-- gratification; the rest stagger. 2026-04-22 per Anne.
--
-- Feed query should filter `publish_at <= now()` to hide pending
-- releases from viewers, and the tech's own "Your Posts" list surfaces
-- pending items separately with their scheduled time.
--
-- Apply by pasting into Supabase → SQL Editor. Idempotent.

alter table public.board_posts
  add column if not exists publish_at timestamptz;

-- Backfill existing rows: they were all "immediate release" before, so
-- publish_at should equal created_at for anything pre-migration. Skips
-- rows that already have a value so re-running is safe.
update public.board_posts
   set publish_at = created_at
 where publish_at is null;

-- Lock in the default + not-null for new rows going forward. New posts
-- that don't specify publish_at behave the same as the old code path
-- (release immediately).
alter table public.board_posts
  alter column publish_at set default now(),
  alter column publish_at set not null;

-- The home-feed query scans board_posts filtered by publish_at <= now()
-- AND (optionally) expires_at > now(). Index publish_at for the left
-- side so the scan stays cheap even as the table grows.
create index if not exists board_posts_publish_at_idx
  on public.board_posts (publish_at);

comment on column public.board_posts.publish_at is
  'When this post becomes visible in the public feed. Defaults to now() so manual posts (announcements, etc.) behave as before. Bulk portfolio uploads use this to stagger: first photo = now, rest = now + N hours.';
