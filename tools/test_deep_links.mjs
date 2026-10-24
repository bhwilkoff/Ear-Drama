// The deep-link records agree (DEEP_LINKS.md, path-prefix discipline): the
// AASA's paths, the Android App Links filter's paths, and the 404 forwarder
// all name the same routes, and assetlinks.json carries Play's signing key.
// Broken controls, 2026-10-24, each seen to fail before the fix was kept:
//   /person/ dropped from the Android filter: the paths-agree check fails.
//   the Play SHA-256 one character off in assetlinks.json: the key check fails.
//   the forwarder's person line removed from 404.html: the forwarder check fails.
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
let failed = 0;
const check = (ok, name, detail = '') => {
  console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${name}${ok || !detail ? '' : ` (${detail})`}`);
  if (!ok) failed += 1;
};

// The AASA: one app, components only, every pattern an app route.
const aasa = JSON.parse(read('.well-known/apple-app-site-association'));
const details = aasa.applinks.details;
check(details.length === 1 && JSON.stringify(details[0].appIDs) === '["L2G756LY8N.app.eardrama"]',
  'AASA names L2G756LY8N.app.eardrama only');
const toRule = (pattern) => pattern.endsWith('/?*') ? `prefix ${pattern.slice(0, -2)}` : `path ${pattern}`;
const aasaRules = details[0].components.map((c) => toRule(c['/'])).sort();

// Android's https filter, the one with autoVerify.
const manifest = read('android/app/src/main/AndroidManifest.xml').replace(/<!--[\s\S]*?-->/g, '');
const filter = manifest.match(/<intent-filter android:autoVerify="true">([\s\S]*?)<\/intent-filter>/);
check(!!filter, 'Android App Links filter is on');
const datas = filter ? [...filter[1].matchAll(/<data ([^>]*)\/>/g)].map((m) => m[1]) : [];
const androidRules = datas.flatMap((d) => {
  const prefix = d.match(/android:pathPrefix="([^"]+)"/);
  const exact = d.match(/android:path="([^"]+)"/);
  return prefix ? [`prefix ${prefix[1]}`] : exact ? [`path ${exact[1]}`] : [];
}).sort();
check(JSON.stringify(aasaRules) === JSON.stringify(androidRules), 'AASA and Android filter paths agree',
  `AASA ${aasaRules.join(', ')} / Android ${androidRules.join(', ')}`);
check(datas.some((d) => d.includes('android:host="eardrama.org"')) && datas.some((d) => d.includes('android:scheme="https"')),
  'Android filter is https://eardrama.org');
check(/<data android:scheme="eardrama"\/>/.test(manifest), 'Android eardrama:// filter is on');

// assetlinks.json: Play's app signing key, as DEEP_LINKS.md records it.
const play = read('DEEP_LINKS.md').match(/SHA-256\s+`([0-9A-F:]{95})`/)?.[1];
const links = JSON.parse(read('.well-known/assetlinks.json'));
const keysFor = (pkg) => links.find((l) => l.target.package_name === pkg)?.target.sha256_cert_fingerprints ?? [];
check(!!play && keysFor('app.eardrama').includes(play), "assetlinks carries Play's signing key for app.eardrama");
check(links.every((l) => l.relation.includes('delegate_permission/common.handle_all_urls')), 'assetlinks relations');
check(keysFor('app.eardrama.debug').length === 1, 'assetlinks carries the debug key for app.eardrama.debug');

// The 404 forwarder sends every declared path into the web app.
const script = read('404.html').match(/<script>([\s\S]*?)<\/script>/)[1];
const forward = (pathname, search = '', hash = '') => {
  let to = null;
  vm.runInNewContext(script, {
    URLSearchParams, decodeURIComponent,
    location: { pathname, search, hash, replace: (u) => { to = u; } },
  });
  return to;
};
const token = 'A'.repeat(43);
const cases = [
  ['/series/suspense', '', '', '/?series=suspense'],
  ['/episode/sus%7C1943', '', '', '/?item=sus%7C1943'],
  ['/person/agnes-moorehead', '', '', '/?person=agnes-moorehead'],
  ['/search', '?q=sorry', '', '/?view=search&q=sorry'],
  ['/library', '', '', '/?view=library'],
  ['/library/', '', '', '/?view=library'],
  ['/invite', '', `#${token}`, `/?view=library&tab=dramas#invite=${token}`],
  ['/invite/', '', `#${token}`, `/?view=library&tab=dramas#invite=${token}`],
];
for (const [p, s, h, want] of cases) {
  const got = forward(p, s, h);
  check(got === want, `404 forwards ${p}${h ? '#…' : s}`, `got ${got}`);
}
const covered = new Set(cases.map(([p]) => toRule(p.replace(/^(\/\w+\/).+$/, '$1?*'))));
check(aasaRules.every((r) => covered.has(r)), 'every AASA path has a forwarder case');

// The site build refuses to ship without the records.
const assemble = read('tools/assemble_site.sh');
check(['.well-known/apple-app-site-association', '.well-known/assetlinks.json'].every((f) => assemble.includes(f)),
  'assemble_site.sh requires both records');

console.log(failed ? `FAIL ${failed} deep-link checks` : 'deep links: all checks pass');
process.exit(failed ? 1 : 0);
