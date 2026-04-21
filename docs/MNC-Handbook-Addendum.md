# MNC Co-Admin Handbook — Addendum v2

*For Leslie · by Anne · April 2026 (post-launch-push)*

---

Hey Les — the original handbook from April is still the canon reference for how MNC fundamentally works. Nothing in it is wrong. But we made a bunch of changes in the last round of work that sharpen (and in a few places, simplify) what you see in the admin console and how techs experience the app. This addendum is what to read on top of the original. Stick it in front of the printed handbook or tuck it in at chapter 6 — it mostly touches what's there.

---

## What changed in the admin console

If you haven't signed in since launch week, you'll notice the tab bar at the top has grown and the Stats tab's layout got tightened up.

### The tab bar: six tabs now

**Stats · Techs · Clients · Inbox · 📢 Push · Settings**

Two new tabs:

- **Inbox** — where "Nudge support" messages from techs land.
- **📢 Push** — where you broadcast a push notification to all / techs / clients / admins.

Same three tabs as before (Techs, Clients, Settings) sit in the same spots, with Inbox + Push slipped in between Clients and Settings.

### Stats tab — what's there now

Cleaner, fewer widgets, everything in one panel:

1. **Four headline cards** — Clients (total) · This Week (new clients in 7d) · Techs · Photos (total across every tech's portfolio)
2. **Pulse strip** — a two-tile row showing:
   - **Live Now** — how many techs have "Available now" toggled on right this minute
   - **Techs to invite** — techs whose password hasn't been set yet (haven't completed their invite flow). This one auto-hides when it's zero — so the day all 17 are in, you won't see it.
3. **Signups sparkline** — 14-day trend of new client signups, rendered as a little chart
4. **Waitlist** — single card showing the number of people on the pre-launch waitlist
5. **Refresh** button at the bottom

**What I removed from this tab:**

- The duplicate stat-strip that used to live in the admin header. Stats only live in the Stats tab now — less duplication.
- The per-source breakdown chart ("where signups came from"). Too granular for day-to-day. If we need source data we can pull it straight from Supabase.
- The detailed waitlist email list. Too noisy. If you need emails, pull them from Supabase SQL Editor:
  ```sql
  select email, source, created_at from public.launch_waitlist order by created_at desc;
  ```
- The "Dig Deeper" link box (Google Analytics / Supabase / etc.). Open those from bookmarks.

### Inbox tab — "Nudge support" messages

Every time a tech or client taps the **"App acting up? Nudge support"** link (see below), their note lands in the Inbox as a card showing:

- Who sent it (name + email + role)
- Their phone number (captured at send time)
- A timestamp
- The body of their message
- Three buttons: **📱 Text back** (opens your phone's SMS app with their number and a "Hi [name], this is MNC support —" greeting pre-filled), **Mark read** (tints the card green, drops the "unread" badge), and **Delete** (with a confirm).

A small red badge on the Inbox tab shows the unread count without you having to open it. You'll see it from any tab.

**Why I built it:** the old "Contact Anne" flow fired a push notification at my phone and that was it — no record, no delegation path. If my phone was off, the message evaporated. Now every message persists in the DB. You and I both see the full queue regardless of who responds.

**Who sees the Inbox:** any account with `role='admin'` in `public.users`. That's you and me today. If we add another admin later, they'll see it automatically.

### 📢 Push tab — broadcasting

A new form for blasting out a push notification:

- **Audience** picker — Everyone, Techs only, Clients only, or Admins only
- **Title** (60 char max)
- **Body** (180 char max)
- **Open URL** — optional, where tapping the push opens in the app (default `/`)
- A confirmation prompt before it fires (no undo on a sent push)
- A status message showing "Delivered to N device(s)" after

**When to use it:**

- Announcing a new feature to all techs
- "The app will be briefly offline tonight for maintenance"
- Shoutout to clients about a seasonal promo

**What it won't do:** go to users who haven't subscribed to push notifications. If someone never granted notification permission on their device, they aren't reachable this way. The broadcast returns "Delivered to N device(s)" where N is however many subscriptions exist for the chosen audience.

### Settings tab — trimmed

Pre-launch cleanup tools are gone:
- **Data Cleanup** (remove techs with no data)
- **Database** (Supabase connection status + link)
- **Geocode** (bulk-geocode techs missing lat/lng)

…removed. We don't need them post-launch and they were surface area for an accidental click. What stays:
- **Admins** list + "add admin by email"
- **Search** defaults (default + max radius settings)
- **Help** — Admin Tutorial replay button

---

## What changed for techs

You probably won't field many questions about these, but it helps to know them so you can nod knowingly when a tech mentions one.

### Staying signed in

Before: close the browser tab, come back, sign in again. Every single time.

After: sign-ins now persist. A tech who signs in once stays signed in across reloads, tab closures, even restarts — until they explicitly sign out or 30 days pass. Token refreshes automatically in the background.

If a tech tells you "I can't sign in" — first ask if they've tried refreshing. The old behavior was weirdly aggressive about kicking people out.

### The invite flow works end-to-end

When I invite a new tech from Supabase Dashboard → Authentication → Users → Add user → Send invitation:

1. They get an email
2. Click the link
3. Set a password on a branded welcome screen
4. Redirect to the app — **already signed in** (no second sign-in step)
5. Land on their tech dashboard

Same for clients going through the signup confirm flow.

### "App acting up? Nudge support" link

Bottom of the tech home dashboard, as a subtle italicized link. Tap it → modal opens → they type what's broken → Send. Message lands in your/my Inbox.

Copy used to say "Contact Anne" — now says "Nudge support" and references "an admin" because both of us handle them.

### Home feed of recent tech posts

The client home screen now has a live-updating feed at the bottom:

- Shows the 100 most recent board posts (what techs put in the "Post an Update" flow)
- Filters to techs within the client's chosen radius (25 / 50 / 100 mi / Anywhere)
- Auto-scrolls slowly, pauses when touched, resumes after 4s idle
- New posts appear at the top in real-time (polls every 15s)

This replaces the old "Your Faves" shortcut cards that were on home. The Faves are still accessible via the Profile tab in the bottom nav.

### Tech posts now have a rate limit

**One post per hour per tech.** Stops accidental double-posts + casual spamming. If a tech tries to post again within the hour, they get a friendly "try again in X min" message.

### Other small polish

- **Profile screen's Portfolio tab** now actually shows the tech's existing photos (before it was upload-only, which was confusing)
- **Tag My Photos** — tapping tags no longer collapses the photo card; you can tag multiple in a row without it slamming shut
- **Map** removed from the bottom nav (clients can still get to the map via "Browse by Location" on home)
- **Availability section** on profile + tech home is compact now, with a "What do these mean?" link that expands full descriptions
- **Edit Profile modal** on profile screen now actually opens (structural bug fix — modal was trapped inside a hidden screen)

---

## New admin mechanics you might need

### Adding an admin

SQL (preferred — not in the UI):

```sql
-- Replace public.is_admin() with an allowlist update
create or replace function public.is_admin() returns boolean
language sql stable security definer as $$
  select coalesce(
    lower(btrim((auth.jwt() ->> 'email'))) in (
      'annewilson1021@gmail.com',
      'anne@mynailconnection.com',
      'leslie@mynailconnection.com'
      -- add more admin emails here, comma-separated
    ),
    false
  );
$$;
```

Run that in Supabase → SQL Editor. Takes effect on the new admin's next sign-in. Also update `public.users.role='admin'` for their row.

### Deleting a tech who actually needs to be gone

Use Supabase Dashboard → Authentication → Users → click their row → Delete user. That removes their auth account. Then clean up the public tables:

```sql
delete from public.techs  where lower(email) = '<their_email>';
delete from public.users  where lower(email) = '<their_email>';
delete from public.board_posts where lower(tech_id) = '<their_email>';
```

Do the board_posts delete LAST so you're not staring at orphan posts in the feed while you work through the other two.

### Getting the waitlist emails

```sql
select email, source, created_at from public.launch_waitlist order by created_at desc;
```

Copy the results; that's your launch-day email blast list.

---

## Things I removed to reduce friction

### The "How do you want to shop?" modal

Used to fire on first sign-in for new clients: a modal asking "Look / Availability / Distance" and routing them to the matching browse screen. Removed. Clients now land on home and see the same options as tappable cards, AND the live feed. The modal was stealing attention from the feed.

### The dev login bar

The sign-in screen used to show three "Sign in as X" bypass buttons in dev mode. Removed entirely — all testing now goes through real Supabase auth. No more test-state weirdness where dev login skipped the session-persistence code path.

### The `window.__MNC_DEV__` flag survives

…but only gates a few console logs. No auth backdoors.

---

## Known sharp edges (things to flag if a tech asks)

These are on the punch-list but not launch-blocking:

1. **"Open this week" filter → map view drops the filter.** If a client taps "Open this week" on home, they land on the map but see ALL techs, not just the ones with open slots. The filter state gets lost in transit. Fix is small, not done yet.
2. **Top-level push notifications only reach my phone by default.** The "Nudge support" flow writes to the Inbox (reliable) but the push alert goes to my auth.user UUID only. For you to get pinged too, we'd need to add your user_id to the send-push target list. Easy fix when you tell me you're ready to take pings.
3. **Emails from Supabase still say "noreply@supabase.co".** Branded SMTP + custom templates are queued but not done.
4. **Android build isn't published yet.** The Capacitor shell exists and works but we haven't submitted to the Play Store.

---

## Questions I want you to ask me

- "How do I see a tech's full post history?" — Currently: SQL. The app doesn't expose it in the admin UI yet. If you find yourself needing this often, tell me and I'll add it to the Techs tab.
- "How do I know a tech hasn't completed their invite yet?" — Stats tab → "Techs to invite" card shows the count. For individual names: `select name, email from public.techs where last_password_change is null;`
- "What happens if I delete a message from the Inbox?" — Gone forever. There's no soft-delete / archive. If you think you might want to refer back to it, copy the body first.
- "Can I test Push without spamming everyone?" — Pick audience "Admins only" when you're experimenting. Goes to you + me only.

---

*Last updated: April 19, 2026 — reflects the launch-prep work session.*
