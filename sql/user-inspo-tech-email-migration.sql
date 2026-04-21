-- ========================================================================
-- MNC user_inspo tech_email migration  (2026-04-21)
-- ========================================================================
-- Adds public.user_inspo.tech_email so aggregate heart-counts-per-tech
-- join on email (unique-enforced) instead of name (not unique — two techs
-- named "Sarah" would conflate their save counts). Backfills via
-- photo_url match because photo URLs are authoritative: each URL lives in
-- exactly one tech's photos[] array.
--
-- Paired with a client-side change in index.html's toggleInspoPhoto() to
-- write both tech_email (source of truth for aggregates) AND tech_name
-- (display convenience cache) on every new save going forward.
--
-- Safe to re-run — all blocks are idempotent.
-- ========================================================================


-- ========================================================================
-- BLOCK 1 — ADD COLUMN
-- Nullable for now; Block 2 fills it. Keeping it nullable permanently so
-- orphaned saves (photo deleted / tech deleted) don't block DELETEs on
-- the parent row.
-- ========================================================================

alter table public.user_inspo
  add column if not exists tech_email text;


-- ========================================================================
-- BLOCK 2 — BACKFILL
-- photo_url is the source of truth. Each URL appears in exactly one
-- tech's photos[] array, so this resolves ambiguity that name-matching
-- would create (two "Sarah" techs → impossible to disambiguate by name).
--
-- techs.photos is jsonb, and each element is an OBJECT of shape
-- {"url": "...", "tags": [...]} — not a plain string. So we use the
-- jsonb containment operator @> to ask "does any element in
-- t.photos contain at least {url: ui.photo_url}?" Extra fields like
-- `tags` in the stored objects don't disrupt the match.
--
-- Note: some legacy rows point to URLs from old data sources (e.g.
-- buildfire-proxy.imgix.net) that are not in any current tech's
-- photos[]. Those remain tech_email = null and are surfaced by
-- Block 4's 'orphaned' count — harmless, ignored by aggregate queries.
-- ========================================================================

update public.user_inspo ui
   set tech_email = t.email
  from public.techs t
 where ui.tech_email is null
   and t.photos @> jsonb_build_array(jsonb_build_object('url', ui.photo_url));


-- ========================================================================
-- BLOCK 3 — INDEX
-- Aggregate queries (count hearts per tech) scan by tech_email. Without
-- an index, that's a full-table scan on every tech-profile load.
-- ========================================================================

create index if not exists user_inspo_tech_email_idx
  on public.user_inspo (tech_email);


-- ========================================================================
-- BLOCK 4 — DIAGNOSTIC
-- Run this last to confirm the backfill worked. 'orphaned' rows are saves
-- pointing to photos no longer in any tech's portfolio (tech deleted,
-- photo replaced, etc.). Not fatal — aggregate queries ignore them.
-- ========================================================================

select
  count(*) filter (where tech_email is not null) as backfilled,
  count(*) filter (where tech_email is null)     as orphaned,
  count(*)                                       as total
  from public.user_inspo;
