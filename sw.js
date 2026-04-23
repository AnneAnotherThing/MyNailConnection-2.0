// My Nail Connection — Service Worker
// Handles push notifications and basic caching

// IMPORTANT: bump this string every release so returning users get the
// new build instead of a stale cached copy. Old caches are deleted on activate.
const CACHE_NAME = 'mnc-v139';
const STATIC_ASSETS = ['/', '/index.html', '/manifest.json'];

// ── Install ───────────────────────────────────────────────────────────────────
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(STATIC_ASSETS)).catch(() => {})
  );
  self.skipWaiting();
});

// ── Activate ──────────────────────────────────────────────────────────────────
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// ── Fetch — network first, cache fallback ─────────────────────────────────────
self.addEventListener('fetch', event => {
  // Only cache same-origin GET requests
  if (event.request.method !== 'GET') return;
  if (!event.request.url.startsWith(self.location.origin)) return;

  event.respondWith(
    fetch(event.request)
      .then(res => {
        // Cache successful responses for static assets
        if (res.ok && res.type === 'basic') {
          const clone = res.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
        }
        return res;
      })
      .catch(() => caches.match(event.request))
  );
});

// ── Push notifications ────────────────────────────────────────────────────────
self.addEventListener('push', event => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: 'My Nail Connection', body: event.data ? event.data.text() : 'You have a new notification' };
  }

  const title = data.title || 'My Nail Connection';
  const options = {
    body: data.body || 'You have a new message',
    icon: '/images/mncLogo-192.webp',
    badge: '/images/mncLogo-64.webp',
    data: { url: data.url || '/' },
    vibrate: [100, 50, 100],
    tag: data.tag || 'mnc-notification',
    renotify: true,
    actions: data.actions || []
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// ── Notification click ────────────────────────────────────────────────────────
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = event.notification.data?.url || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
      // Focus existing window if open
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.focus();
          client.postMessage({ type: 'NOTIFICATION_CLICK', url });
          return;
        }
      }
      // Otherwise open new window
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});

// ── Push subscription change ──────────────────────────────────────────────────
self.addEventListener('pushsubscriptionchange', event => {
  // Re-subscribe if subscription expires
  event.waitUntil(
    self.registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: 'BINTHftWbkLsZZkNn0tafTXmhmgV6gvk46zmMeAC7wmJl5HWeUeWgGSoMDX9DRu7drBtS5XruZVPvduhoH4gSO4'
    }).then(subscription => {
      // Post new subscription to app
      return self.clients.matchAll().then(clients => {
        clients.forEach(c => c.postMessage({ type: 'PUSH_RESUBSCRIBED', subscription }));
      });
    }).catch(err => console.error('Re-subscribe failed:', err))
  );
});
