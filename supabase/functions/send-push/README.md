# MNC Push Notifications Setup

## 1. Deploy the Edge Function

```bash
supabase functions deploy send-push
```

## 2. Set Secrets in Supabase

In Supabase Dashboard → Settings → Edge Functions → Secrets, add:

| Secret | Value |
|--------|-------|
| VAPID_PUBLIC_KEY | BINTHftWbkLsZZkNn0tafTXmhmgV6gvk46zmMeAC7wmJl5HWeUeWgGSoMDX9DRu7drBtS5XruZVPvduhoH4gSO4 |
| VAPID_PRIVATE_KEY | (the private key PEM from key generation — keep this secret!) |
| VAPID_SUBJECT | mailto:admin@mynailconnection.com |

## 3. Create push_subscriptions table in Supabase

Run this SQL in the Supabase SQL editor:

```sql
create table if not exists push_subscriptions (
  id uuid default gen_random_uuid() primary key,
  user_id text not null,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  updated_at timestamptz default now()
);

-- Allow users to manage their own subscriptions
alter table push_subscriptions enable row level security;
create policy "Users can manage own subscriptions"
  on push_subscriptions for all
  using (true);  -- open for now, tighten later
```

## 4. How it works

- When a user logs in on https://, the app registers `sw.js` as a service worker
- On first visit to Messages, the app asks permission and saves a push subscription to Supabase
- When someone sends a message, the app calls the `send-push` Edge Function
- The Edge Function sends a Web Push to the recipient's device via the service worker
- The service worker shows the notification even when the app is closed

## Notes
- Push only works on https:// — NOT on localhost
- iOS Safari requires iOS 16.4+ and the app must be installed as a PWA (Add to Home Screen)
- The VAPID private key must stay secret — never put it in the HTML
