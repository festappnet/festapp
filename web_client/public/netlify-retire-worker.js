'use strict';

const FESTAPP_LEGACY_ORIGIN_RETIREMENT = true;
const CANONICAL_ORIGIN = 'https://clovekavira.festapp.net';
const FESTAPP_CACHE_PREFIX = 'festapp-app-shell-';

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames
      .filter((name) => name.startsWith(FESTAPP_CACHE_PREFIX))
      .map((name) => caches.delete(name)));

    await self.clients.claim();
    const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    await Promise.all(clients.map((client) => {
      const legacyUrl = new URL(client.url);
      if (legacyUrl.origin !== self.location.origin) return undefined;
      return client.navigate(CANONICAL_ORIGIN + legacyUrl.pathname + legacyUrl.search + legacyUrl.hash);
    }));
    await self.registration.unregister();
  })());
});

self.addEventListener('fetch', (event) => {
  if (event.request.mode !== 'navigate') return;
  const legacyUrl = new URL(event.request.url);
  event.respondWith(Response.redirect(
    CANONICAL_ORIGIN + legacyUrl.pathname + legacyUrl.search + legacyUrl.hash,
    301,
  ));
});
