// The own-script suite's negative controls: each rule broken in a copy of js/, and js/own.test.js run on
// the copy. A mutant the suite passes is a rule nothing checks.  node tools/own_mutants.mjs
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MUTANTS = [
  ['plays-store.js', 'if (from < 2) db.createObjectStore(\'scripts\');', '', 'the migration adds no store'],
  ['plays-store.js', 'if (from < 1) db.createObjectStore(\'files\');', 'db.createObjectStore(\'files\');', 'the migration makes a store twice'],
  ['plays-store.js', 'd.onversionchange = () => { gone(); d.close(); };', '', 'a page holds a newer one out'],
  ['plays-store.js', 'if (refused) { d.close(); return; }', '', 'a refused connection stays open'],
  ['plays-store.js', 'for (const t of p.takes || []) out.add(t.lineID);', 'for (const t of p.takes || []) if ((p.chosen || {})[t.lineID] === t.id) out.add(t.lineID);', 'an unchosen take locks nothing'],
  ['plays-store.js', 'if (shares.has(found.id)) continue;', '', 'a shared production takes a change'],
  ['plays-store.js', 'if (ids(was) !== ids(script)) { next.listenedThrough = false; delete next.mixedFrom; }', '', 'new lines leave a play finished'],
  ['plays-store.js', 'title: script.title, scriptRevision: script.revision }', 'title: script.title }', 'the revision does not follow'],
  ['plays-store.js', 'scripts.delete(p.id);\n          productions', 'productions', 'the production reads its old lines'],
  ['own-store.js', 'await backend.putAll([[`${folder(snap.id)}doc.json`', 'await backend.put(`${folder(snap.id)}row.json`, JSON.stringify(row)); await backend.putAll([[`${folder(snap.id)}doc.json`', 'a full disk leaves half a change'],
  ['own-store.js', 'const w = before.catch(() => {}).then(() => write(snap));', 'const w = write(snap);', 'writes overtake each other'],
  ['own-store.js', 'if (!refusal) {', 'if (true) {', 'a script no one can cast is sealed'],
  ['own-store.js', 'script.edits = editsOf(await store.script(snap.id), script, taken);', '', 'no words changed is ever known'],
  ['own-store.js', 'past.find(e => take.created < e.until)', 'past.find(() => true)', 'a take of the new words reads Words changed'],
  ['own-store.js', 'return !!line && O.wordsChanged(said.text, textOf(line));', 'return !!line;', 'a comma reads Words changed'],
  ['own-store.js', 'if (b.includes(0)) return { refusal: \'not_text\' };', '', 'a binary is read as text'],
  ['own-store.js', 'if (b.length > 2 * O.MAX_BYTES + 2) return { refusal: \'too_long\' };', '', 'a file is read before its bytes are counted'],
  ['own-store.js', 'a.d - b.d || a.up - b.up', 'a.d - b.d || b.up - a.up', 'the line below is nearer than the one above'],
  ['own-store.js', 'await backend.removePrefix(folder(id));', 'await backend.removePrefix(\'scripts/\');', 'deleting one deletes all'],
  ['api.js', "if (typeof id === 'string' && id.startsWith('own-')) return", "if (false) return", 'an own id is asked of the catalog'],
  ['export.js', 'scripts: scripts.map(s => ({ ...s })),', '', 'the export has no scripts'],
  ['plays-ui.js', 'isOwn(script) ? null : shareBox(', 'shareBox(', 'a production of one offers Share'],
  ['cast-ui.js', '(h && spoken ?', '(h ?', 'a Kokoro voice is offered with no phonemes'],
];
let failures = 0;
for (const [file, from, to, what] of MUTANTS) {
  const src = readFileSync(join(ROOT, 'js', file), 'utf8');
  if (src.split(from).length !== 2) { failures++; console.log(`FAIL  ${file}: the text to break is not there once: ${from}`); continue; }
  const dir = mkdtempSync(join(tmpdir(), 'own-mutant-'));
  cpSync(join(ROOT, 'js'), dir, { recursive: true });
  writeFileSync(join(dir, file), src.replace(from, () => to));
  const run = spawnSync('node', [join(ROOT, 'js', 'own.test.js')], { env: { ...process.env, OWN_JS_DIR: dir }, encoding: 'utf8', timeout: 60000 });
  rmSync(dir, { recursive: true, force: true });
  const caught = run.status !== 0;
  if (!caught) failures++;
  console.log(`${caught ? 'ok   ' : 'FAIL '} ${what}${caught ? `  (${(run.stdout.match(/FAIL .*/) || [''])[0].slice(0, 90)})` : ''}`);
}
console.log(failures ? `FAIL: ${failures}` : `ok: ${MUTANTS.length} mutants`);
process.exit(failures ? 1 : 0);
