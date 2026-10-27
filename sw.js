// App shell cached for offline start; map tiles and fonts always come from the network.
const CACHE = "citycat-v4", MODELS = "citycat-models";
const SHELL = ["./", "index.html", "manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png",
  "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js", "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE && k !== MODELS).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  // The cat detector (about 18MB) downloads once and then works offline.
  if (e.request.method === "GET" && (url.host === "storage.googleapis.com" && url.pathname.startsWith("/tfjs-models/") || /@tensorflow/.test(url.pathname))) {
    e.respondWith(caches.open(MODELS).then(c => c.match(e.request).then(hit => hit || fetch(e.request).then(r => { if (r.ok) c.put(e.request, r.clone()); return r; }))));
    return;
  }
  if (e.request.method !== "GET" || /basemaps\.cartocdn|arcgisonline|googleapis|gstatic|tile\.|supabase\.co/.test(url.host)) return;
  if (url.pathname.endsWith("/config.js")) { e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r; }).catch(() => caches.match(e.request))); return; }
  if (e.request.mode === "navigate") { e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put("index.html", copy)); return r; }).catch(() => caches.match("index.html"))); return; }
  e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request)));
});
