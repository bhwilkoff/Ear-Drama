/**
 * No third-party code at runtime (Decision 084, R3d T1/T2): the website loads scripts only from its own
 * origin, except the sign-in scripts a person asks for (Apple, Google) and the Cast receiver framework on
 * the TV receiver page. A school's reviewer reads "no trackers"; this is the check that holds it.
 *
 *   node tools/test_no_third_party_code.mjs
 *
 * Reads every shipped page and script (never the tests), and runs itself once on a planted CDN line,
 * which must fail (a check that never fails proves nothing).
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const ALLOWED = [
  'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js',
  'https://accounts.google.com/gsi/client',
  'https://www.gstatic.com/cast/sdk/libs/caf_receiver/v3/cast_receiver_framework.js',
];
const CDN = /\b(cdn\.jsdelivr\.net|unpkg\.com|cdnjs\.cloudflare\.com|esm\.sh|cdn\.skypack\.dev|ajax\.googleapis\.com|googletagmanager\.com|google-analytics\.com|connect\.facebook\.net|plausible\.io|segment\.(com|io))\b/;

function shipped() {
  const files = [];
  for (const f of readdirSync(join(root, 'js'))) if (f.endsWith('.js') && !f.endsWith('.test.js')) files.push(`js/${f}`);
  for (const f of ['index.html', '404.html', 'sw.js', 'tv.js']) if (existsSync(join(root, f))) files.push(f);
  for (const d of readdirSync(root, { withFileTypes: true })) {
    if (d.isDirectory() && existsSync(join(root, d.name, 'index.html')) && !['docs', 'node_modules', 'worker', 'android', 'apple'].includes(d.name)) files.push(`${d.name}/index.html`);
  }
  return files.sort();
}

export function violations(name, text) {
  const out = [];
  if (CDN.test(text)) out.push(`${name}: names a third-party code host (${text.match(CDN)[0]})`);
  for (const m of text.matchAll(/<script[^>]*\bsrc="(https?:[^"]+)"/g)) if (!ALLOWED.includes(m[1])) out.push(`${name}: script from ${m[1]}`);
  for (const m of text.matchAll(/importScripts\(\s*['"`](https?:[^'"`]+)/g)) out.push(`${name}: importScripts from ${m[1]}`);
  for (const m of text.matchAll(/['"`](https:\/\/[^'"`\s]+\.m?js)['"`]/g)) if (!ALLOWED.includes(m[1])) out.push(`${name}: script URL ${m[1]}`);
  return out;
}

const found = shipped().flatMap((f) => violations(f, readFileSync(join(root, f), 'utf-8')));
const control = violations('control', "const ORT = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.31.1/dist/';");
const worker = readFileSync(join(root, 'js/kokoro-worker.js'), 'utf-8');
if (!/new URL\('\.\.\/vendor\/onnxruntime-web\/', self\.location\.href\)/.test(worker)) found.push('js/kokoro-worker.js: the ONNX Runtime is not loaded from /vendor/onnxruntime-web/');
if (!control.length) found.push('control: a planted jsDelivr line was not caught');
if (found.length) {
  console.error(found.join('\n'));
  console.log('no third-party code: FAIL');
  process.exit(1);
}
console.log(`no third-party code: PASS (${shipped().length} files)`);
