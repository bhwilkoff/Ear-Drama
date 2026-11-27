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
  // The web board (B32 W): js/sound.test.js.
  ['plays-core.js', '    counts.set(SOUND, cueRows(script).length);\n', '', 'a script with no sound line has no Sound part', 'sound'],
  ['plays-core.js', "p.takes.filter(t => t.lineID === lineID && !t.cue)", "p.takes.filter(t => t.lineID === lineID)", "a performed cue shows in the actor's take list", 'sound'],
  ['sound-core.js', "n.takes.push({ ...C.clone(take), part: C.SOUND, cue: slotID });", "n.takes.push({ ...C.clone(take), part: C.SOUND, cue: slotID }); n.chosen[take.lineID] = take.id;", "a performed cue becomes the line's chosen take", 'sound'],
  ['sound-core.js', "if (!Object.prototype.hasOwnProperty.call(LICENSES, lic.id)) return `license ${lic.id || 'none'}`;", '', 'a CC-BY row passes the rights gate', 'sound'],
  ['sound-core.js', "if (!httpURL(lic.evidence)) return 'no evidence';", '', 'a row without evidence passes', 'sound'],
  ['sound-core.js', "if (typeof lic.checked !== 'string' || !/^\\d{4}-\\d{2}-\\d{2}/.test(lic.checked)) return 'no checked date';", '', 'a row without a checked date passes', 'sound'],
  ['sound-core.js', "if ([src.page, src.file, lic.evidence].some(u => u && refusedHost(u))) return `refused host ${host(src.page)}`;", '', 'a refused host passes', 'sound'],
  ['sound-core.js', "const gone = rec.filter(s => s.id !== keep && !s.silent && !(s.sounds || []).length);", "const gone = rec.filter(s => !s.silent && !(s.sounds || []).length);", 'the current added slot vanishes', 'sound'],
  ['sound-core.js', "    if (before >= total) return { at: 'after', share: 1 };\n", '', 'a cue after the words plays under them', 'sound'],
  ['sound-core.js', "    n.slots = (n.slots || []).map(s => ({ ...s, sounds: (s.sounds || []).filter(x => !(x.src && x.src.own)) }))", "    n.slots = (n.slots || []).map(s => ({ ...s, sounds: (s.sounds || []) }))", 'a published block keeps own sounds', 'sound'],
  ['sound-core.js', "          out[j].stop.push(x.id);", '', 'a bed never stops at its Until', 'sound'],
  ['sound-store.js', "if ((await devices.digest(got.bytes)) === cue.sha256) return got.bytes;", 'return got.bytes;', "a pack file is used without its checksum", 'sound'],
  ['sound-store.js', "for (let attempt = 0; attempt < 2; attempt++) {", "for (let attempt = 0; attempt < 1; attempt++) {", 'a bad file is not downloaded again once', 'sound'],
  ['sound-store.js', "if (!resolveSound(x.src)) missing.push(", "if (false) missing.push(", 'a missing own sound is not named', 'sound'],
  ['sound-store.js', "seconds: Math.round((r.frames / r.sampleRate) * 10) / 10, bytes: r.bytes, wav });", "seconds: Math.round((r.frames / r.sampleRate) * 10) / 10, bytes: r.bytes, wav: null });", 'Export my data drops the own sound itself', 'sound'],
  ['plays-session.js', "          for (const h of running) h.duck(true);\n", '', 'the live listen never ducks a bed', 'sound'],
  ['plays-ui.js', "'Your own sounds stay on this device. The published play leaves them out.')]", "'')]", 'Publish says nothing of own sounds', 'sound'],
];
let failures = 0;
for (const [file, from, to, what, suite = 'plays'] of MUTANTS) {
  const src = readFileSync(join(ROOT, 'js', file), 'utf8');
  if (src.split(from).length !== 2) { failures++; console.log(`FAIL  ${file}: the text to break is not there once: ${from}`); continue; }
  const dir = mkdtempSync(join(tmpdir(), 'sound-mutant-'));
  cpSync(join(ROOT, 'js'), dir, { recursive: true });
  writeFileSync(join(dir, file), src.replace(from, () => to));
  const target = ['plays', 'sound'].includes(suite) ? join(ROOT, 'js', `${suite}.test.js`) : join(dir, `${suite}.test.js`);
  const run = spawnSync('node', [target], { env: { ...process.env, PLAYS_JS_DIR: dir }, encoding: 'utf8', timeout: 120000 });
  rmSync(dir, { recursive: true, force: true });
  const caught = run.status !== 0;
  if (!caught) failures++;
  console.log(`${caught ? 'ok   ' : 'FAIL '} ${what}${caught ? `  (${((run.stdout + run.stderr).match(/FAIL .*|AssertionError.*/) || [''])[0].slice(0, 90)})` : ''}`);
}
console.log(failures ? `FAIL: ${failures}` : `ok: ${MUTANTS.length} mutants`);
process.exit(failures ? 1 : 0);
