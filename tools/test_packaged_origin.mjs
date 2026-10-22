/* Packaged-TV-app integrity checks (webOS .ipk / Tizen .wgt).
 *
 * A packaged app runs its document from file://, not https://. That single
 * difference silently broke an entire data plane once: PAGES_ROOT was
 * `new URL('.', location.href)`, which under file:// resolves every catalog fetch
 * to a local path that isn't in the package — the app would have launched to an
 * empty catalog on every LG and Samsung TV.
 *
 * These assertions run the REAL expression out of js/app.js (not a copy) so they
 * follow the source if it is edited. Every check that does not apply to this app
 * yet prints a SKIP saying why — never silence, never a pass.
 *
 * Usage: node tools/test_packaged_origin.mjs      (from any directory)
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');
const appSrc = read('js/app.js');

let pass = 0, fail = 0, skip = 0;
const ok = (name, got, want) => {
  const good = String(got) === String(want);
  console.log(`${good ? 'PASS' : 'FAIL'}  ${name}  (got ${got}, want ${want})`);
  good ? pass++ : fail++;
};
const truthy = (name, got, why = '') => {
  console.log(`${got ? 'PASS' : 'FAIL'}  ${name}${!got && why ? `  (${why})` : ''}`);
  got ? pass++ : fail++;
};
const skipped = (msg) => { console.log(`SKIP  ${msg}`); skip++; };

/* ---- 1. PAGES_ROOT resolution, from the real source ---- */

const m = appSrc.match(/const CANONICAL_ROOT = [\s\S]*?const PAGES_ROOT = [\s\S]*?;\n/);
if (!m) {
  skipped('js/app.js has no CANONICAL_ROOT / PAGES_ROOT block — this app fetches no '
        + 'remote data plane yet. When it does, resolve data URLs through '
        + '`const CANONICAL_ROOT = new URL("https://<your-site>/"); const PAGES_ROOT = '
        + '/^https?:$/.test(location.protocol) ? new URL(".", location.href) : CANONICAL_ROOT;` '
        + 'so a packaged (file://) TV app still reaches the network, and this test will check it.');
} else {
  const block = m[0];
  const resolveRootFor = (href) => {
    const location = { href, protocol: new URL(href).protocol };
    // eslint-disable-next-line no-new-func
    return Function('location', 'URL', `${block}; return PAGES_ROOT.href;`)(location, URL);
  };
  const canonical = resolveRootFor('file:///opt/usr/apps/App/res/wgt/index.html');
  ok('localhost dev server stays same-origin',
     resolveRootFor('http://localhost:8123/index.html'), 'http://localhost:8123/');
  ok('an https deep path keeps its directory',
     resolveRootFor('https://example.com/index.html?tv=1'), 'https://example.com/');
  ok('webOS package (file://) falls back to the canonical root',
     resolveRootFor('file:///media/developer/apps/usr/palm/applications/com.example.app/index.html'),
     canonical);
  /* A file:// root that did NOT fall back produces a local path — the exact
     failure the fallback exists to prevent. */
  truthy('packaged data URL is remote, not a local file',
         new URL('data.json', canonical).protocol === 'https:');
}

/* ---- 2. The staged packages carry the CURRENT shared app ---- */

// The list tv/build-tv-packages.sh stages (APP_FILES + APP_JS + APP_CSS). Staged
// css lands at css/<name>, the same relative path as the source.
const SHARED = ['index.html', 'tv.js', 'tv.css', 'js/api.js', 'js/app.js', 'css/styles.css']
  .filter((f) => fs.existsSync(path.join(ROOT, f)));
const html = read('index.html');
const pageScripts = [...html.matchAll(/src="(js\/[A-Za-z0-9._-]+\.js)"/g)].map((x) => x[1]);

for (const pkg of ['webos', 'tizen']) {
  const dir = path.join(ROOT, 'tv', pkg, 'app');
  if (!fs.existsSync(dir)) {
    skipped(`${pkg} not staged (run tv/build-tv-packages.sh ${pkg})`);
    continue;
  }
  // A STALE stage is not a defect: the builder `rm -rf`s before every build, so an
  // old local copy can never reach a package (and tv/<pkg>/app is not shipped from
  // git). Failing on it is a red X for a non-failure — it cried wolf for five weeks
  // once. Only a CURRENT stage that still differs means staging is broken.
  const stale = SHARED
    .filter((f) => fs.existsSync(path.join(dir, f)))
    .filter((f) => fs.statSync(path.join(ROOT, f)).mtimeMs > fs.statSync(path.join(dir, f)).mtimeMs);
  if (stale.length) {
    skipped(`${pkg} staged before ${stale.join(', ')} changed (run tv/build-tv-packages.sh ${pkg})`);
    continue;
  }
  for (const f of SHARED) {
    const a = fs.readFileSync(path.join(ROOT, f));
    const b = fs.existsSync(path.join(dir, f)) ? fs.readFileSync(path.join(dir, f)) : null;
    truthy(`${pkg}/${f} matches the shared source`, b && a.equals(b), b ? 'differs' : 'missing');
  }
  /* EVERY SCRIPT index.html LOADS MUST BE IN THE PACKAGE. A hand-kept staged list
     went stale the moment two sync scripts were added to the page: every TV launch
     then made two requests that 404'd, nothing threw (they were called as
     `window.X?.init()`), and nobody saw it. A store's QA does look at failed loads. */
  const missing = pageScripts.filter((f) => !fs.existsSync(path.join(dir, f)));
  truthy(`${pkg} packages every js/ script index.html loads`, missing.length === 0, missing.join(', '));
  // A service worker inside a package would shadow the packaged files with a stale
  // cache, and is deliberately stripped.
  truthy(`${pkg} has no packaged service worker`, !fs.existsSync(path.join(dir, 'sw.js')));
  // If the staged app registers a SW, registration must be guarded by protocol so a
  // packaged (file://) launch never calls register() and fails on every launch.
  const stagedApp = path.join(dir, 'js/app.js');
  if (fs.existsSync(stagedApp) && /serviceWorker\s*\.\s*register/.test(fs.readFileSync(stagedApp, 'utf8'))) {
    truthy(`${pkg} js/app.js guards SW registration by protocol`,
           /\/\^https\?:\$\/\.test\(location\.protocol\)/.test(fs.readFileSync(stagedApp, 'utf8')));
  } else {
    skipped(`${pkg} js/app.js registers no service worker — nothing to guard`);
  }
}

/* ---- 3. Things that break ONLY at a file:// origin ---- */

const jsFiles = fs.readdirSync(path.join(ROOT, 'js')).filter((f) => f.endsWith('.js'))
  .map((f) => `js/${f}`);
const sources = [['index.html', html], ...jsFiles.map((f) => [f, read(f)])];

/* THE CAST SENDER SDK MUST NOT BE A STATIC TAG. Google's script, once running,
   fetches its framework PROTOCOL-RELATIVE (//www.gstatic.com/…), which at a
   packaged widget's file:// origin resolves to file://www.gstatic.com/… and fails
   on every launch. It cannot be fixed from inside our code, so the sdk is INJECTED
   and skipped on a packaged TV — which costs nothing: a TV is never a Cast SENDER. */
{
  truthy('the Cast sender sdk is not loaded by a static <script> tag',
         !/<script[^>]+src=["'](?:https?:)?\/\/www\.gstatic\.com[^"']*cast_sender/i.test(html));
  const injectors = sources.filter(([, s]) => s.includes('cast_sender.js'));
  if (!injectors.length) {
    skipped('nothing references cast_sender.js — the Cast sdk is not loaded yet');
  } else {
    for (const [f, s] of injectors) {
      truthy(`${f}: the Cast sdk injector skips a file:// origin`,
             /location\.protocol\s*===?\s*['"]file:['"]/.test(s) || /\^https\?:\$/.test(s));
      truthy(`${f}: the Cast sdk injector skips the TV user agents`, /Tizen/.test(s) && /Web0S|webOS/.test(s));
    }
  }
}

/* BEACONS ARE GATED ON http(s). A packaged file:// app that fires an analytics /
   telemetry beacon broke a privacy promise once — the store listing said the TV
   app sent nothing. Any sendBeacon must sit behind a protocol check. */
{
  const beacons = sources.filter(([, s]) => /navigator\.sendBeacon/.test(s));
  if (!beacons.length) {
    skipped('no navigator.sendBeacon in the app — nothing to gate');
  } else {
    for (const [f, s] of beacons) {
      truthy(`${f}: sendBeacon is gated on an http(s) protocol check`,
             /\^https\?:\$\/\.test\(location\.protocol\)|location\.protocol\s*!==?\s*['"]file:['"]/.test(s));
    }
  }
}

console.log(`\n${pass} passed, ${fail} failed, ${skip} skipped`);
process.exit(fail ? 1 : 0);
