# Founders Communication — MNC 2.0 launch

**Audience:** the 17 OG techs who were on My Nail Connection 1.0, plus Leslie.
**Primary deliverable:** [`founders-email.html`](./founders-email.html) — branded HTML email.
**This file:** plain-text fallback + sequencing notes.

---

## Subject line

`Welcome back — your Glow Up is on us` ✨

---

## Plain-text version (for clients that strip HTML)

Hi {{first_name}},

You were here for MNC 1.0 — bugs and all — and that's not nothing. As a thank-you, your Glow Up subscription is on us. Forever.

That's 40 photos a month, every upload landing in the live feed, plus a gold ✨ Glow Up badge on your profile so clients know you've been here from the start.

Sign in to see it: https://mynailconnection.com/app/
(Forgot your password? Tap "Forgot password?" — fresh link in seconds.)

Welcome back.

— Anne
My Nail Connection

---

## Sequencing — SQL order in Supabase

1. `sql/email-casing-fix.sql` — patches the signup RPC + backfills mixed-case emails. Independent prerequisite.
2. `sql/free-upload-counter-fix.sql` — adds `lifetime_free_used` counter, creates `tech_comps` table, patches both upload RPCs, installs the comps→techs sync trigger. Required before step 3.
3. `sql/founders-comp-grant.sql` — INSERTs the founder list into `tech_comps`. The trigger from step 2 immediately propagates `subscription_tier='paid'` + `subscription_expires_at=NULL` onto each founder's techs row, so the gold ✨ Glow Up badge shows up the moment they sign in.

**Then:**

1. **Test with one person first** (yourself, or Leslie). Confirm the badge actually shows on their profile + tech cards.
2. **Send the rest.** 18 emails in a single batch is fine; no batching needed at this size.

**Adding/removing founders later:** see the bottom of `sql/founders-comp-grant.sql` for one-row INSERT / DELETE / UPDATE recipes — no migration required.
