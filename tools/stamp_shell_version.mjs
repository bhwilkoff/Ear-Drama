/* Stamp the assembled site's sw.js with a SHELL_VERSION computed from the shell it caches
 * (WEB-DESIGN §10.1). A hand-bumped version went 9 web commits unbumped (2026-11-16), so
 * returning visitors kept the old app. The hash covers sw.js and every SHELL file, never
 * the catalog data, so a daily catalog publish leaves the version alone.
 *
 *   node tools/stamp_shell_version.mjs <assembled site dir>
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const VERSION_RE = /const SHELL_VERSION = '[^']*';/;

export function shellPaths(swSource) {
  const m = swSource.match(/const SHELL = \[([\s\S]*?)\];/);
  if (!m) throw new Error('sw.js has no SHELL list');
  return [...m[1].matchAll(/'([^']*)'/g)].map(x => x[1]);
}

export function shellVersion(dir) {
  const sw = fs.readFileSync(path.join(dir, 'sw.js'), 'utf8');
  if (!VERSION_RE.test(sw)) throw new Error('sw.js has no SHELL_VERSION line');
  const h = crypto.createHash('sha256');
  h.update(sw.replace(VERSION_RE, ''));
  for (const p of shellPaths(sw)) {
    const rel = p === './' ? 'index.html' : p.endsWith('/') ? `${p}index.html` : p;
    h.update(`\0${p}\0`);
    h.update(fs.readFileSync(path.join(dir, rel)));
  }
  return `ed-shell-${h.digest('hex').slice(0, 12)}`;
}

export function stamp(dir) {
  const file = path.join(dir, 'sw.js');
  const version = shellVersion(dir);
  const sw = fs.readFileSync(file, 'utf8');
  fs.writeFileSync(file, sw.replace(VERSION_RE, `const SHELL_VERSION = '${version}';`));
  return version;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const dir = process.argv[2];
  if (!dir) { console.error('usage: node tools/stamp_shell_version.mjs <site dir>'); process.exit(2); }
  console.log(`[stamp] SHELL_VERSION = ${stamp(dir)}`);
}
