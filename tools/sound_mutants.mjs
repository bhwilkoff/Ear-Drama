// The sound-in-the-mix negative controls (B32 K2): each rule broken in a copy of js/, and js/plays.test.js (or the
// suite a mutant names) run on the copy. A mutant the suite passes is a rule nothing checks.  node tools/sound_mutants.mjs
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MUTANTS = [
  ['plays-core.js', 'attackMs: 120,', 'attackMs: 121,', 'the attack 1 ms longer'],
  ['plays-core.js', 'releaseMs: 600,', 'releaseMs: 500,', 'a shorter release'],
  ['plays-core.js', 'if (last && v[0] - last[1] < hold)', 'if (last && v[0] - last[1] < 0)', 'the duck pumps between lines'],
  ['plays-core.js', "      for (const e of mine.filter(x => x.s.at === 'before')) {\n        const s = Math.max(0, nominal() + startOf(e));\n        place(e, s, e.info.frames);\n        cursor = Math.max(cursor, s + e.info.frames);",
    "      for (const e of mine.filter(x => x.s.at === 'before')) {\n        const s = Math.max(0, nominal() + startOf(e));\n        place(e, s, e.info.frames);", 'the line does not wait for a Before cue'],
  ['plays-core.js', "      for (const e of mine.filter(x => x.s.at === 'after')) {\n        const s = Math.max(0, nominal() + startOf(e));\n        place(e, s, e.info.frames);\n        cursor = Math.max(cursor, s + e.info.frames);",
    "      for (const e of mine.filter(x => x.s.at === 'after')) {\n        const s = Math.max(0, nominal() + startOf(e));\n        place(e, s, e.info.frames);", 'the next line does not wait for an After cue'],
  ['plays-core.js', 'db = f1 === f0 ? d1 : d0 + ((d1 - d0) * (f - f0)) / (f1 - f0);', 'db = d1;', 'the duck jumps instead of ramping'],
  ['plays-core.js', 'if (x.fadeOut > 0 && x.frames - k < x.fadeOut) g *= (x.frames - k) / x.fadeOut;', '', 'no fade out'],
  ['plays-core.js', 'const src = x.inFrame + (x.loop ? k % span : k);', 'const src = x.inFrame + k;', 'a bed does not loop'],
  ['plays-core.js', '      scalar = mixScalar(peak);', '', 'the mix is not held under -1 dBFS'],
  ['plays-core.js', 'effectsLufs: -19, musicLufs: -20,', 'effectsLufs: -19, musicLufs: -19,', 'music plays at the effects level'],
  ['plays-core.js', "const duck = typeof e.s.duckDb === 'number' ? e.s.duckDb : (", 'const duck = (', "a cue's own duck is ignored"],
  ['plays-core.js', 'const until = endAt.has(e.s.until) ? endAt.get(e.s.until) : anchor[1];', 'const until = anchor[1];', 'a bed stops at its first line'],
  ['plays-core.js', "if (linePart(line) !== SOUND) voice.push([start, cursor]);", 'voice.push([start, cursor]);', 'a sound line ducks the sound'],
  ['plays-core.js', "return hasSound(p) ? `${takes}|sound=${stableStringify(p.sound)}` : takes;", 'return takes;', 'a moved sound leaves the mix current'],
  ['plays-core.js', 'const keep = new Set([...Object.values(p.chosen), ...soundTakeIDs(p)]);', 'const keep = new Set(Object.values(p.chosen));', 'a performed cue is discarded as unused'],
  ['plays-core.js', "if (left.length && !withoutMissing) throw new MixFailure('missingSounds', left);", '', 'a missing sound is dropped silently'],
  ['plays-core.js', 'if (!sound) return { sampleRate, placements, totalFrames: cursor };', 'if (!sound) return { sampleRate, placements, totalFrames: cursor, sounds: [] };', 'a play with no sound gets another timeline'],
  ['export.js', '...(p.sound ? { sound: JSON.parse(JSON.stringify(p.sound)) } : {}),', '', 'the export has no sound', 'export'],
];
let failures = 0;
for (const [file, from, to, what, suite = 'plays'] of MUTANTS) {
  const src = readFileSync(join(ROOT, 'js', file), 'utf8');
  if (src.split(from).length !== 2) { failures++; console.log(`FAIL  ${file}: the text to break is not there once: ${from}`); continue; }
  const dir = mkdtempSync(join(tmpdir(), 'sound-mutant-'));
  cpSync(join(ROOT, 'js'), dir, { recursive: true });
  writeFileSync(join(dir, file), src.replace(from, () => to));
  const target = suite === 'plays' ? join(ROOT, 'js', 'plays.test.js') : join(dir, `${suite}.test.js`);
  const run = spawnSync('node', [target], { env: { ...process.env, PLAYS_JS_DIR: dir }, encoding: 'utf8', timeout: 120000 });
  rmSync(dir, { recursive: true, force: true });
  const caught = run.status !== 0;
  if (!caught) failures++;
  console.log(`${caught ? 'ok   ' : 'FAIL '} ${what}${caught ? `  (${((run.stdout + run.stderr).match(/FAIL .*|AssertionError.*/) || [''])[0].slice(0, 90)})` : ''}`);
}
console.log(failures ? `FAIL: ${failures}` : `ok: ${MUTANTS.length} mutants`);
process.exit(failures ? 1 : 0);
