-- ============================================================================
-- FIX: booking decline/cancel returns 400 "could not update, try again"
-- ----------------------------------------------------------------------------
-- Root cause (found 2026-07-17): the bookings status CHECK constraint on the
-- restored 3.0 database still uses the OLD 2.0 vocabulary
-- (pending / confirmed / cancelled / completed). The 3.0 app writes the
-- granular statuses 'declined', 'cancelled_by_tech', and 'cancelled_by_client'
-- (see BK_STATUS_CHIP / tbSetStatus in index.html), which the constraint
-- rejects with 23514 (check_violation) -> HTTP 400.
--
-- Verified live: PATCH {status:'declined'} -> 400; {status:'confirmed'} -> 204.
-- This breaks EVERY tech decline/cancel AND every client cancellation.
--
-- Run this once in the Supabase SQL editor (project nwqnakoongrorbwnrqzc).
-- ============================================================================

ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_status_check;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_status_check
  CHECK (status IN (
    'pending',
    'confirmed',
    'declined',
    'cancelled',            -- kept so any legacy 2.0 rows still validate
    'cancelled_by_tech',
    'cancelled_by_client',
    'completed',
    'no_show'
  ));

-- Sanity check after running:
--   SELECT DISTINCT status FROM public.bookings;   -- should all be in the list above
