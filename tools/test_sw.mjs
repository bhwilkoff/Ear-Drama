/* The service worker's routing, read out of the SHIPPED sw.js (WEB-DESIGN §7, §10.1).
 *
 * Runs sw.js in a VM with a stub `self`, then hands its fetch handler fake requests
 * and records which ones it answers. Also checks that every shell file exists (one
 * missing file fails install, and then no service worker ever runs) and that every
 * script and stylesheet the pages load is in the shell (or offline opens half an app).
 *
 *   node tools/test_sw.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SCOPE = 'https://eardrama.org/';
let failures = 0, passes = 0;
const ok = (name, cond, detail = '') => {
  if (cond) passes++; else { failures++; console.log(`FAIL ${name}${detail ? `: ${detail}` : ''}`); }
};

const src = fs.readFileSync(path.join(ROOT, 'sw.js'), 'utf8');
const handlers = {};
const ctx = {
  self: { addEventListener: (t, fn) => { handlers[t] = fn; }, registration: { scope: SCOPE },
          location: new URL(SCOPE), clients: { claim: () => Promise.resolve() }, skipWaiting: () => Promise.resolve() },
  caches: { open: async () => ({ match: async () => undefined, put: async () => {}, addAll: async () => {} }),
            keys: async () => [], delete: async () => true },
  fetch: async () => new Response('{}'), URL, Request, Response, Promise, setTimeout, console,
};
vm.runInNewContext(`${src}\n;globalThis.__sw = { SHELL, BYPASS, SHELL_VERSION, DATA_VERSION };`, ctx);
const { SHELL, BYPASS, SHELL_VERSION, DATA_VERSION } = ctx.__sw;

ok('cache names are versioned', /^ed-shell-v\d+$/.test(SHELL_VERSION) && /^ed-data-v\d+$/.test(DATA_VERSION));
ok('the ops pages are bypassed', BYPASS.includes('/pulse/') && BYPASS.includes('/cast/'));

for (const p of SHELL) {
  const f = p === './' ? 'index.html' : p.endsWith('/') ? `${p}index.html` : p;
  ok(`shell file exists: ${p}`, fs.existsSync(path.join(ROOT, f)));
}

const shellPaths = new Set(SHELL.map((p) => new URL(p, SCOPE).pathname));
for (const page of ['index.html', 'credits/index.html', 'privacy/index.html', 'takedown/index.html']) {
  const html = fs.readFileSync(path.join(ROOT, page), 'utf8');
  const refs = [...html.matchAll(/<(?:script|link)[^>]+(?:src|href)="([^"]+\.(?:js|css))"/g)].map((m) => m[1]);
  for (const r of refs) {
    const pathname = new URL(r, new URL(page, SCOPE)).pathname;
    ok(`${page} loads ${r} from the shell`, shellPaths.has(pathname));
  }
}

function answered(url, { destination = '', mode = 'no-cors', method = 'GET', headers = {} } = {}) {
  let responded = false;
  handlers.fetch({
    request: { url, destination, mode, method, headers: new Headers(headers) },
    respondWith: () => { responded = true; },
  });
  return responded;
}

ok('audio passes through', !answered('https://archive.org/download/x/y.mp3', { destination: 'audio' }));
ok('a ranged request passes through', !answered(`${SCOPE}data/x.json`, { headers: { range: 'bytes=0-' } }));
ok('/pulse/ passes through', !answered(`${SCOPE}pulse/data.json`));
ok('/pulse/ navigation passes through', !answered(`${SCOPE}pulse/`, { destination: 'document', mode: 'navigate' }));
ok('a POST passes through', !answered(`${SCOPE}data/manifest.json`, { method: 'POST' }));
ok('another origin\'s page passes through', !answered('https://archive.org/details/x', { destination: 'document', mode: 'navigate' }));
ok('catalog data is answered', answered(`${SCOPE}data/series/suspense.json`));
ok('catalog data on another host is answered', answered('https://data.example.org/web/manifest.json'));
ok('a navigation is answered', answered(`${SCOPE}?item=x`, { destination: 'document', mode: 'navigate' }));
ok('a site page is answered', answered(`${SCOPE}credits/`, { destination: 'document', mode: 'navigate' }));
ok('a shell script is answered', answered(`${SCOPE}js/app.js`, { destination: 'script' }));
ok('an unlisted same-origin file passes through', !answered(`${SCOPE}assets/unknown.png`, { destination: 'image' }));

console.log(`${failures ? 'FAIL' : 'ok'}: ${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
