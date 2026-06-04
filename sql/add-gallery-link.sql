-- Add per-tech gallery/social link + ensure booking_link exists.
-- Run in the Supabase SQL editor (project ktiztunuifzbzwzyqrrq).
--
-- gallery_link: tech's Instagram / TikTok / social or external gallery URL.
--   Rendered as a secondary "View on Instagram / View Gallery" button on the
--   tech-detail profile, beneath the booking button.
-- booking_link: added defensively with IF NOT EXISTS. The column is already
--   read throughout the app; this is a no-op if it already exists.

alter table public.techs add column if not exists gallery_link text;
alter table public.techs add column if not exists booking_link text;
