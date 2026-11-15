/**
 * The studio inside the reader (PLAYS-DESIGN §2.9, WEB-DESIGN §4.16 item 14; Decision 076 S3), run
 * against the SHIPPED js/studio-core.js over the shipped RecordingSession and take model with fakes
 * that play and record nothing: the current line and how each mode moves it, the take state each of
 * my lines shows, choosing a take, deleting one (never the chosen one), Delete unused takes for one
 * part only, Record again keeping every older take, the line the studio opens at, and the production
 * the reader's Record continues.
 *   node js/studio.test.js
 *
 * Seen to fail, 2026-11-14: before js/studio-core.js existed (every case), and against mutated
 * copies: keep() in Step leaving the current line where it was (the Step case); deleteTake without
 * the chosen-take refusal (the delete case); discardUnused ignoring its line list (the part-scoped
 * case); addTake replacing the line's takes instead of adding one (the Record again case).
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

for (const f of ['plays-core.js', 'plays-store.js', 'voice-cast.js', 'plays-voice.js', 'plays-session.js', 'studio-core.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
}
const C = vm.runInThisContext('PlaysCore');
const PlayStore = vm.runInThisContext('PlayStore');
const RecordingSession = vm.runInThisContext('RecordingSession');
const SC = vm.runInThisContext('StudioCore');

let passes = 0, failures = 0;
const results = [];
const test = (name, fn) => results.push([name, fn]);
function eq(a, b, msg) {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}: got ${x}, want ${y}`);
}
function ok(v, msg) { if (!v) throw new Error(msg); }

/* ---- Fixtures (the plays suite's script: MOLLY 5 lines, FIBBER 3, DOC 1) ---- */

function line(id, role, kind = 'speech', text = 'words') {
  return kind === 'speech' ? { id, kind, role, parts: [{ say: text }] } : { id, kind, source: text };
}
function fixtureScript() {
  const lines = [
    line('L0001', null, 'direction', '(A kitchen.)'),
    line('L0002', 'FIBBER', 'speech', 'Well, Molly.'),
    line('L0003', 'MOLLY', 'speech', 'Yes, dearie?'),
    line('L0004', null, 'sound', 'SOUND: DOOR OPENS'),
    line('L0005', 'DOC', 'speech', 'Anybody home?'),
    line('L0006', 'MOLLY', 'speech', 'Come in.'),
    line('L0007', 'MOLLY', 'speech', 'Sit down.'),
    line('L0008', 'FIBBER', 'speech', 'Doc!'),
    line('L0009', 'MOLLY', 'speech', 'Tea?'),
    line('L0010', 'FIBBER', 'speech', 'Not for me.'),
    line('L0011', 'MOLLY', 'speech', 'Good night.'),
  ];
  const roles = ['MOLLY', 'FIBBER', 'DOC'].map(name => ({ name, lines: lines.filter(l => l.role === name).length, words: 2 }));
  return { id: 'gut-0', revision: 'r1', kind: 'radio', title: 'Good Grammar', authors: [],
           source: { name: 'Fixture', url: 'https://example.org' },
           rights: { bucket: 'script_source_cleared', evidence: [] }, roles, lines };
}
const MOLLY = C.role('MOLLY');
const FIBBER = C.role('FIBBER');

const zeros = (n) => new Float32Array(n);
function tone(seconds) {
  const out = new Float32Array(Math.round(seconds * 48000));
  for (let i = 0; i < out.length; i++) out[i] = 0.3 * Math.sin(2 * Math.PI * 160 * i / 48000);
  return out;
}
function join(...parts) {
  const out = new Float32Array(parts.reduce((s, p) => s + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}
/** Plays nothing, records nothing: room tone first, then a spoken line and silence each capture. */
function fakeAudio() {
  let captures = 0;
  let captured = zeros(0);
  return {
    sampleRate: 48000, capture: 'direct',
    async start() {}, stop() {},
    beginCapture(onChunk) {
      captures += 1;
      captured = captures === 1 ? Float32Array.from({ length: 48000 }, () => (Math.random() - 0.5) * 0.001)
        : join(zeros(9600), tone(0.6), zeros(60000));
      for (let s = 0; s < captured.length; s += 960) onChunk(captured.subarray(s, Math.min(s + 960, captured.length)));
    },
    endCapture() { const c = captured; captured = zeros(0); return { samples: c, sampleRate: 48000 }; },
    startMeter() {}, stopMeter() { return 0; },
    async playTake() {}, stopPlayback() {},
    async toTakeRate(c) { return c; },
  };
}
/** A device voice that reads nothing aloud: it only notes the words. */
function silentVoice() {
  const read = [];
  return { read, async speak(text) { read.push(text); return true; }, cancel() {}, reads: () => false };
}

async function studio(part = MOLLY, opts = {}) {
  const script = fixtureScript();
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  let p = await store.create(script);
  p = C.take(p, script, part, '');
  await store.save(p);
  const s = RecordingSession.create({ production: p, script, part, store, audio: fakeAudio(), voice: silentVoice(), sleep: async () => {} });
  await s.begin();
  const st = SC.create({ session: s, script, part, store, line: opts.line || null });
  return { st, s, store, backend, script };
}

/* ---- The current line and the take states ---- */

test('the studio opens at the part\'s first line with no take, or at the line asked for', async () => {
  const script = fixtureScript();
  let p = C.newProduction(script);
  eq(SC.startLine(p, script, MOLLY, null), 'L0003', 'no takes: the part\'s first line');
  p = C.addTake(p, { id: 'a', lineID: 'L0003', part: MOLLY, file: 'a.wav', frames: 1, sampleRate: 48000, bleed: false });
  eq(SC.startLine(p, script, MOLLY, null), 'L0006', 'the first line still without a take');
  eq(SC.startLine(p, script, MOLLY, 'L0009'), 'L0009', 'a line of the part that was asked for wins');
  eq(SC.startLine(p, script, MOLLY, 'L0002'), 'L0006', 'another part\'s line is not mine to record');
  for (const id of ['L0006', 'L0007', 'L0009', 'L0011']) p = C.addTake(p, { id: `t${id}`, lineID: id, part: MOLLY, file: 'x.wav', frames: 1, sampleRate: 48000, bleed: false });
  eq(SC.startLine(p, script, MOLLY, null), 'L0003', 'every line taken: the first line');
});

test('each of my lines shows none, its takes with the chosen one, or the flag', async () => {
  const script = fixtureScript();
  let p = C.newProduction(script);
  eq(SC.lineState(p, 'L0003'), { state: 'none', takes: 0, chosen: 0 }, 'no take');
  p = C.addTake(p, { id: 'a', lineID: 'L0003', part: MOLLY, file: 'a.wav', frames: 1, sampleRate: 48000, bleed: false });
  p = C.addTake(p, { id: 'b', lineID: 'L0003', part: MOLLY, file: 'b.wav', frames: 1, sampleRate: 48000, bleed: false });
  eq(SC.lineState(p, 'L0003'), { state: 'chosen', takes: 2, chosen: 2 }, 'the newest take is chosen');
  p = C.choose(p, 'a');
  eq(SC.lineState(p, 'L0003'), { state: 'chosen', takes: 2, chosen: 1 }, 'choosing an older take');
  p = C.addTake(p, { id: 'c', lineID: 'L0003', part: MOLLY, file: 'c.wav', frames: 1, sampleRate: 48000, bleed: true });
  eq(SC.lineState(p, 'L0003'), { state: 'flagged', takes: 3, chosen: 3 }, 'a flagged chosen take');
});

test('Next and Previous move by my lines only, from wherever the current line is', async () => {
  const { st, s } = await studio();
  eq(st.current, 'L0003', 'opens at the first line');
  st.move(1); eq(st.current, 'L0006', 'next of mine skips the others');
  st.move(1); st.move(1); st.move(1); eq(st.current, 'L0011', 'to the last');
  st.move(1); eq(st.current, 'L0011', 'stays on the last');
  st.move(-1); eq(st.current, 'L0009', 'previous');
  ok(!st.select('L0008'), 'another part\'s line cannot be current');
  eq(st.current, 'L0009', 'unchanged');
  ok(st.select('L0006'), 'a tap on one of my lines');
  eq(st.current, 'L0006', 'it is current');
  s.end();
});

/* ---- The three ways the reader moves ---- */

test('Step: a take opens its review; Keep makes my next line current and waits', async () => {
  const { st, s } = await studio();
  s.setMode('step');
  await st.primary();
  eq(s.phase.kind, 'review', 'the take\'s review');
  eq(st.current, 'L0003', 'still on the line just taken');
  st.keep();
  eq(st.current, 'L0006', 'Keep moves to my next line');
  eq(s.phase.kind, 'idle', 'and waits for a tap');
  eq(st.lineState('L0006').state, 'none', 'it did not record the next line');
  s.end();
});

test('Line by line: after a take the line stays current, ready to record again', async () => {
  const { st, s } = await studio();
  s.setMode('lines');
  st.select('L0007');
  await st.primary();
  eq(s.phase.kind, 'idle', 'ready');
  eq(st.current, 'L0007', 'the same line');
  eq(st.lineState('L0007').takes, 1, 'one take');
  s.end();
});

test('Run through: the current line follows the run through my lines, which record as they come', async () => {
  const { st, s } = await studio();
  s.setMode('run');
  st.select('L0006');
  const seen = [];
  st.onFollow = (id) => seen.push(id);
  await st.primary();
  eq(s.phase.kind, 'runReview', 'the run ends on its review');
  eq(s.runTakes().map(t => t.lineID), ['L0006', 'L0007', 'L0009', 'L0011'], 'every line of mine from the current one');
  ok(seen.includes('L0005') && seen.includes('L0008'), 'the reader followed the other parts\' lines as they were heard');
  eq(st.current, 'L0011', 'the current line followed to my last line');
  st.keep();
  eq(s.run, null, 'Keep keeps the run');
  s.end();
});

/* ---- Takes: choose, delete, delete unused, record again ---- */

test('Record again keeps every older take and chooses the new one', async () => {
  const { st, s, store } = await studio();
  s.setMode('lines');
  await st.primary();
  const first = st.takes('L0003').map(t => t.id);
  await st.again();
  const takes = st.takes('L0003');
  eq(takes.length, 2, 'two takes');
  eq(takes[0].id, first[0], 'the first take is still there');
  eq(store.production(s.production.id).chosen.L0003, takes[1].id, 'the new take is chosen');
  s.end();
});

test('choosing a take never deletes; only an unchosen take can be deleted, by the person', async () => {
  const { st, s, store, backend } = await studio();
  s.setMode('lines');
  await st.primary();
  await st.again();
  const [a, b] = st.takes('L0003');
  st.choose(a);
  eq(store.production(s.production.id).chosen.L0003, a.id, 'chosen');
  eq(st.takes('L0003').length, 2, 'choosing deleted nothing');
  ok(!(await st.deleteTake(a)), 'the chosen take is refused');
  eq(st.takes('L0003').length, 2, 'still two');
  ok(await st.deleteTake(b), 'an unchosen take goes');
  eq(st.takes('L0003').map(t => t.id), [a.id], 'one left');
  ok(!(await backend.keys(`${s.production.id}/takes/`)).some(k => k.endsWith(b.file)), 'its file is gone');
  eq(s.production.takes.length, 1, 'the session reads the record without it');
  s.end();
});

test('Delete unused takes removes only this part\'s unchosen takes', async () => {
  const { st, s, store } = await studio();
  let p = store.production(s.production.id);
  p = C.addTake(p, { id: 'f1', lineID: 'L0010', part: FIBBER, file: 'f1.wav', frames: 1, sampleRate: 48000, bleed: false });
  p = C.addTake(p, { id: 'f2', lineID: 'L0010', part: FIBBER, file: 'f2.wav', frames: 1, sampleRate: 48000, bleed: false });
  await store.save(p);
  s.production = p;
  s.setMode('lines');
  await st.primary();
  await st.again();
  st.move(1);
  await st.primary();
  eq(st.unused().length, 1, 'one unused take of mine');
  const gone = await st.deleteUnused();
  eq(gone, 1, 'one deleted');
  const after = store.production(s.production.id);
  eq(after.takes.filter(t => t.part === FIBBER).map(t => t.id), ['f1', 'f2'], 'another part\'s unused take stays');
  eq(st.takes('L0003').length, 1, 'my line keeps its chosen take');
  eq(st.takes('L0006').length, 1, 'and the other');
  s.end();
});

test('PlaysCore.deleteTake refuses the chosen take and discardUnused takes a line list', async () => {
  const script = fixtureScript();
  let p = C.newProduction(script);
  p = C.addTake(p, { id: 'a', lineID: 'L0003', part: MOLLY, file: 'a.wav', frames: 1, sampleRate: 48000, bleed: false });
  p = C.addTake(p, { id: 'b', lineID: 'L0003', part: MOLLY, file: 'b.wav', frames: 1, sampleRate: 48000, bleed: false });
  p = C.addTake(p, { id: 'c', lineID: 'L0002', part: FIBBER, file: 'c.wav', frames: 1, sampleRate: 48000, bleed: false });
  p = C.addTake(p, { id: 'd', lineID: 'L0002', part: FIBBER, file: 'd.wav', frames: 1, sampleRate: 48000, bleed: false });
  eq(C.deleteTake(p, 'b').gone, [], 'the chosen take stays');
  const r = C.deleteTake(p, 'a');
  eq(r.gone.map(t => t.id), ['a'], 'an unchosen take goes');
  eq(r.production.takes.map(t => t.id), ['b', 'c', 'd'], 'the rest stay');
  const u = C.discardUnused(p, ['L0003']);
  eq(u.gone.map(t => t.id), ['a'], 'only the lines named');
  eq(C.discardUnused(p).gone.map(t => t.id), ['a', 'c'], 'no list: every line, as the cast sheet does');
});

/* ---- Where the reader's Record records ---- */

test('the reader\'s Record continues the part, else takes it where it is open, else makes a production', async () => {
  const script = fixtureScript();
  const mk = (id, created, parts = {}) => ({ ...C.newProduction(script), id, created, parts });
  const notShared = () => false;
  eq(SC.productionFor([], notShared, script, MOLLY), { make: true }, 'nothing yet: a new production');
  const open = mk('p1', 1);
  eq(SC.productionFor([open], notShared, script, MOLLY), { id: 'p1', take: true }, 'an open part is taken');
  const busy = mk('p2', 2, { [FIBBER]: { status: 'recording' } });
  eq(SC.productionFor([busy, open], notShared, script, MOLLY), { id: 'p1', take: true }, 'not where another part records');
  const mine = mk('p3', 0, { [MOLLY]: { status: 'recording' } });
  eq(SC.productionFor([busy, open, mine], notShared, script, MOLLY), { id: 'p3', take: false }, 'the part already recording wins');
  eq(SC.productionFor([busy, open, mine], (id) => id === 'p3', script, MOLLY), { id: 'p1', take: true }, 'never a shared production');
  const other = { ...mk('p4', 9), scriptID: 'gut-9' };
  eq(SC.productionFor([other], notShared, script, MOLLY), { make: true }, 'never another play\'s');
  const done = mk('p5', 9, { [MOLLY]: { status: 'done' } });
  eq(SC.productionFor([done], notShared, script, MOLLY), { make: true }, 'a part already done is not reopened from the reader');
});

test('the cast shows the performer of a part someone else holds, never mine, open or silent ones', () => {
  const rec = {
    parts: { a: { status: 'recording', performer: 'Ada', user_id: 'u2' }, b: { status: 'done', user_id: 'u3' },
             c: { status: 'recording', performer: 'Me', user_id: 'u1' }, d: { status: 'open' }, e: { status: 'silent', user_id: 'u2' } },
    members: [{ user_id: 'u1', display_name: 'Me' }, { user_id: 'u2', display_name: 'A. L.' }, { user_id: 'u3', display_name: 'Grace H' }],
  };
  eq(SC.heldBy(rec, 'u1'), { a: 'Ada', b: 'Grace H' }, 'their chosen name, else their member name');
  eq(SC.heldBy(null, 'u1'), {}, 'no record, no names');
});

(async () => {
  for (const [name, fn] of results) {
    try { await fn(); passes += 1; console.log(`  ok    ${name}`); }
    catch (e) { failures += 1; console.log(`  FAIL  ${name}\n        ${e.message}`); }
  }
  console.log(`${failures ? 'FAIL' : 'PASS'}: ${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
