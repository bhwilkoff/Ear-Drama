/**
 * The library's castable manifest (R4-0, docs/WORKER.md "Castable only"): the rows the Worker reads,
 * built from the library being published (worker/tools/castable-manifest.mjs), and the check that
 * says so when they lag it. Fixture libraries in a temporary folder; nothing here reads the live
 * catalog or the network.
 *
 *   node tools/test_castable_manifest.mjs
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TOOL = path.join(ROOT, 'worker', 'tools', 'castable-manifest.mjs');
const { CASTABLE_BUCKETS, validRow } = await import(path.join(ROOT, 'worker', 'src', 'plays-manifest.js'));
const { castHash } = await import(path.join(ROOT, 'worker', 'src', 'plays-manifest.js'));

let passes = 0, failures = 0;
const ok = (cond, name) => { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } };
const eq = (a, b, name) => ok(JSON.stringify(a) === JSON.stringify(b), `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);

const work = fs.mkdtempSync(path.join(os.tmpdir(), 'castable-'));
process.on('exit', () => fs.rmSync(work, { recursive: true, force: true }));
let n = 0;
const play = (id, revision = 'abcdef012345', over = {}) => ({
  id, revision, title: `Play ${id}`, source: { name: 'Fixture', url: 'https://example.org/1' },
  rights: { bucket: 'script_source_cleared', evidence: [{ claim: 'Public domain in the USA.', src: 'https://example.org/1.rdf' }] },
  lines: [{ id: 'L0001', kind: 'direction', source: 'A room.' }, { id: 'L0002', kind: 'speech', role: 'ANNA' }, { id: 'L0003', kind: 'block', source: 'a bell' }],
  ...over,
});
/** A library folder as the site serves it: index.json and scripts/<id>.json. */
function library(plays) {
  const dir = path.join(work, `lib${n++}`);
  fs.mkdirSync(path.join(dir, 'scripts'), { recursive: true });
  writePlays(dir, plays);
  return dir;
}
function writePlays(dir, plays) {
  fs.writeFileSync(path.join(dir, 'index.json'), JSON.stringify({ format: 1, count: plays.length, plays: plays.map(s => ({ id: s.id, revision: s.revision, path: `scripts/${s.id}.json` })) }));
  for (const s of plays) fs.writeFileSync(path.join(dir, 'scripts', `${s.id}.json`), JSON.stringify({ format: 1, scripts: [s] }));
}
function run(...args) {
  try { return { code: 0, out: execFileSync('node', [TOOL, ...args], { encoding: 'utf8', stdio: 'pipe' }) }; }
  catch (e) { return { code: e.status, out: e.stdout + e.stderr }; }
}
const row = (dir, id) => JSON.parse(fs.readFileSync(path.join(dir, 'castable', `${id}.json`), 'utf8'));

// The rows: one a play, whole, and the Worker's own check takes each.
{
  const dir = library([play('gut-1'), play('gut-4269-18', '0123456789ab'), play('grw-A1')]);
  const r = run('--library', dir);
  eq(r.code, 0, `the build passes: ${r.out}`);
  eq(fs.readdirSync(path.join(dir, 'castable')).sort(), ['grw-A1.json', 'gut-1.json', 'gut-4269-18.json'], 'one row a play');
  const got = row(dir, 'gut-1');
  eq(got, validRow(got, 'gut-1'), 'a row is exactly what the Worker keeps of it');
  eq(got.cast, await castHash([['L0001', 'directions'], ['L0002', 'role:ANNA'], ['L0003', 'sound']]), 'its cast sheet is the script\'s');
  eq([got.revision, got.lines, got.publishable], ['abcdef012345', 3, true], 'revision, lines, publishable');
  ok(fs.statSync(path.join(dir, 'castable', 'gut-1.json')).size < 2048, 'a row is small');
  eq(run('--check', dir).code, 0, 'the check passes on a fresh build');

  // A refresh: one play re-parsed, one added, one gone. The old manifest is caught, by name, in one line.
  writePlays(dir, [play('gut-1', 'fedcba543210', { lines: [{ id: 'L0001', kind: 'speech', role: 'BEN' }] }), play('gut-4269-18', '0123456789ab'), play('gut-9')]);
  const lag = run('--check', dir);
  eq(lag.code, 1, 'a lagging manifest fails the check');
  ok(/^the castable manifest lags the play library: of 3 plays, 1 without a row \(gut-9\); 1 whose row is not the script's \(gut-1\); 1 rows for plays the library does not hold \(grw-A1\)\./.test(lag.out), `the line names them: ${lag.out}`);
  ok(/Rebuild: node worker\/tools\/castable-manifest\.mjs --library /.test(lag.out) && lag.out.trim().split('\n').length === 1, 'and says what to run, on one line');
  eq(run('--library', dir).code, 0, 'the rebuild');
  eq(fs.readdirSync(path.join(dir, 'castable')).sort(), ['gut-1.json', 'gut-4269-18.json', 'gut-9.json'], 'a play that left leaves no row');

  // Each single difference is caught alone, the same revision with another cast sheet most of all.
  const broken = {
    'a cast hash': { cast: '0'.repeat(64) }, 'a revision': { revision: '000000000000' }, 'a title': { title: 'Other' },
    'publishable': { publishable: false }, 'a right': { rights: { bucket: 'own', evidence: [] } }, 'an extra field': { more: 1 },
  };
  for (const [what, over] of Object.entries(broken)) {
    const good = row(dir, 'gut-9');
    fs.writeFileSync(path.join(dir, 'castable', 'gut-9.json'), JSON.stringify({ ...good, ...over }));
    const b = run('--check', dir);
    ok(b.code === 1 && b.out.includes('(gut-9)'), `${what} that differs is caught`);
    fs.writeFileSync(path.join(dir, 'castable', 'gut-9.json'), JSON.stringify(good));
  }
  fs.writeFileSync(path.join(dir, 'castable', 'gut-9.json'), '{');
  eq(run('--check', dir).code, 1, 'a row that is not JSON is caught');
  fs.rmSync(path.join(dir, 'castable'), { recursive: true });
  ok(/3 without a row/.test(run('--check', dir).out), 'no manifest at all is caught');
}

// A library the Worker could not serve stops the build, and names the play.
for (const [what, plays, says] of [
  ['an own script\'s id', [play('own-1')], 'own-1'],
  ['an id a URL could misread', [play('gut-1%2f')], 'gut-1%2f'],
  ['a row without evidence', [play('gut-1', 'abcdef012345', { rights: { bucket: 'script_source_cleared', evidence: [{ claim: 'x', src: null }] } })], 'gut-1'],
  ['a revision the Worker would refuse', [play('gut-1', 'R2')], 'gut-1'],
]) {
  const r = run('--library', library(plays));
  ok(r.code === 1 && r.out.includes(says), `${what} stops the build: ${r.out}`);
}
{
  const dir = library([play('gut-1')]);
  fs.writeFileSync(path.join(dir, 'index.json'), JSON.stringify({ plays: [{ id: 'gut-1', revision: '999999999999' }] }));
  ok(/gut-1: the index says 999999999999, its script abcdef012345/.test(run('--library', dir).out), 'an index that disagrees with its script stops the build');
}
eq(run('--nonsense').code, 2, 'an unknown option is refused');

// A play whose rights bucket is not castable is never publishable.
{
  const dir = library([play('gut-1', 'abcdef012345', { rights: { bucket: 'script_no_evidence', evidence: [] } })]);
  eq(run('--library', dir).code, 0, 'built');
  eq(row(dir, 'gut-1').publishable, false, 'not publishable');
}

// Run through a symlinked path, as a CI checkout may be, the tool still does its work.
{
  const link = path.join(work, 'link');
  fs.symlinkSync(ROOT, link);
  const dir = library([play('gut-1')]);
  execFileSync('node', [path.join(link, 'worker', 'tools', 'castable-manifest.mjs'), '--library', dir], { stdio: 'pipe' });
  ok(fs.existsSync(path.join(dir, 'castable', 'gut-1.json')), 'built through a symlink');
}

// The castable buckets are script_rights.py's (one rule in two languages), with a control.
{
  const py = fs.readFileSync(path.join(ROOT, 'catalog', 'tools', 'script_rights.py'), 'utf8');
  const buckets = (src) => [...src.slice(src.indexOf('\nSTATE = {')).split('}')[0].matchAll(/"(\w+)":\s*"castable"/g)].map(m => m[1]).sort();
  eq(buckets(py), [...CASTABLE_BUCKETS].sort(), 'CASTABLE_BUCKETS is script_rights.py STATE\'s castable buckets');
  ok(JSON.stringify(buckets(py.replace('"script_no_evidence": "not_castable"', '"script_no_evidence": "castable"'))) !== JSON.stringify([...CASTABLE_BUCKETS].sort()), 'control: a bucket made castable there is noticed here');
}

// Nobody has to remember it: the site build makes the manifest from the library it is deploying, and a refresh
// tries it before it uploads.
{
  const site = fs.readFileSync(path.join(ROOT, 'tools', 'assemble_site.sh'), 'utf8');
  const copied = site.indexOf('cp -R catalog/out/plays-library/. "$out/data/plays/library/"');
  const built = site.indexOf('node worker/tools/castable-manifest.mjs --library "$out/data/plays/library"');
  ok(copied > 0 && built > copied && /^set -euo pipefail$/m.test(site), 'assemble_site.sh builds it after the library is in place, and a failure stops the deploy');
  const refresh = fs.readFileSync(path.join(ROOT, 'tools', 'refresh_play_library.sh'), 'utf8');
  const tried = refresh.indexOf('worker/tools/castable-manifest.mjs" --library "$work/check" || die');
  ok(tried > 0 && tried < refresh.indexOf('gh release upload "$TAG"'), 'refresh_play_library.sh refuses a library whose manifest does not build');
}

console.log(`${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
