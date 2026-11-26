/**
 * Ear Drama's service worker (WEB-DESIGN §7).
 *
 *  - The shell (pages, styles, scripts) is cache-first. The deploy stamps
 *    SHELL_VERSION from the shell's bytes (tools/stamp_shell_version.mjs, §10.1);
 *    the value here is only what a local server runs.
 *  - Catalog data (*.json read with fetch) is network-first with the last good
 *    copy as the fallback, so whatever a person has opened still opens offline.
 *    The castable plays (data/plays/castable-scripts.json) are data like the rest.
 *    A play's takes live in IndexedDB, never in these caches.
 *  - Audio is never cached here (downloads are a later step), and the ops pages
 *    (/pulse/, /cast/), the sign-in return pages (/auth/), and other origins' pages pass through untouched.
 *  - Caches are named by version; activate deletes every older Ear Drama cache.
 */
const SHELL_VERSION = 'ed-shell-v71';
const DATA_VERSION = 'ed-data-v1';
const KEEP = [SHELL_VERSION, DATA_VERSION];

const SHELL = [
  './',
  'index.html',
  '404.html',
  'manifest.json',
  'css/styles.css',
  'tv.css',
  'fonts/big-shoulders.woff2',
  'fonts/public-sans.woff2',
  'fonts/public-sans-italic.woff2',
  'js/compat.js',
  'js/config.js',
  'js/api.js',
  'js/store.js',
  'js/export.js',
  'js/sync.js',
  'js/account.js',
  'js/player.js',
  'js/remote-playback.js',
  'js/plays-core.js',
  'js/plays-store.js',
  'js/own-core.js',
  'js/own-store.js',
  'js/plays-share.js',
  'js/age-gate.js',
  'js/voice-cast.js',
  'js/plays-voice.js',
  'js/plays-audio.js',
  'js/plays-session.js',
  'js/voices.js',
  'js/cast-ui.js',
  'js/voice-settings.js',
  'js/voices-step.js',
  'js/plays-ui.js',
  'js/plays-worklet.js',
  'js/reader-core.js',
  'js/along.js',
  'js/reader.js',
  'js/read-core.js',
  'js/read-session.js',
  'js/read-record.js',
  'js/relay-core.js',
  'js/relay-watch.js',
  'js/parts-ui.js',
  'js/read-ui.js',
  'js/class-ui.js',
  'js/own-ui.js',
  'js/ear-core.js',
  'js/ear-ui.js',
  'js/marks-core.js',
  'js/marks.js',
  'js/studio-core.js',
  'js/studio.js',
  'js/together-core.js',
  'js/together.js',
  'js/together-ui.js',
  'js/label-core.js',
  'js/label.js',
  'js/find-core.js',
  'js/app.js',
  'js/site.js',
  'js/takedown.js',
  'tv.js',
  'credits/',
  'privacy/',
  'schools/',
  'security/',
  'takedown/',
  'delete-account/',
];

const BYPASS = ['/pulse/', '/cast/', '/auth/'];
const DATA_TIMEOUT_MS = 4000;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_VERSION)
      .then((cache) => cache.addAll(SHELL.map((p) => new Request(new URL(p, self.registration.scope), { cache: 'reload' }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('ed-') && !KEEP.includes(k)).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

function isMedia(request) {
  return request.destination === 'audio' || request.destination === 'video' || request.headers.has('range');
}

function isData(request, url) {
  return request.destination === '' && url.pathname.endsWith('.json');
}

/** Cache-first; a navigation that misses falls back to the cached page that forwards path links. */
async function shell(request) {
  const cache = await caches.open(SHELL_VERSION);
  const hit = await cache.match(request, { ignoreSearch: request.mode === 'navigate' });
  if (hit) return hit;
  try {
    return await fetch(request);
  } catch (err) {
    if (request.mode === 'navigate') {
      const forward = await cache.match(new URL('404.html', self.registration.scope));
      if (forward) return forward;
    }
    throw err;
  }
}

/** Network-first with the last good copy; a slow network yields to the copy and refreshes it behind. */
async function data(request) {
  const cache = await caches.open(DATA_VERSION);
  const network = fetch(request).then((resp) => {
    if (resp.ok) cache.put(request, resp.clone()).catch(() => {});
    return resp;
  });
  const cached = await cache.match(request);
  if (!cached) return network;
  network.catch(() => {});
  const timeout = new Promise((resolve) => setTimeout(() => resolve(null), DATA_TIMEOUT_MS));
  try {
    const first = await Promise.race([network, timeout]);
    if (first && first.ok) return first;
    if (first && !first.ok && first.status !== 404) return cached;
    return first || cached;
  } catch {
    return cached;
  }
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET' || isMedia(request)) return;
  const url = new URL(request.url);
  const sameOrigin = url.origin === self.location.origin;
  if (sameOrigin && BYPASS.some((p) => url.pathname.startsWith(p))) return;
  if (isData(request, url)) { event.respondWith(data(request)); return; }
  if (!sameOrigin) return;
  if (request.mode === 'navigate' || SHELL.some((p) => new URL(p, self.registration.scope).pathname === url.pathname)) {
    event.respondWith(shell(request));
  }
});
