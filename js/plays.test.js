/**
 * Plays phase 1 on the web (docs/PLAYS-DESIGN.md, WEB-DESIGN §4.10), run
 * against the SHIPPED js/plays-*.js on fixtures: the relay order, take
 * replacement, the timeline and its ripple, that a partial play is never
 * mixed, that the mix places each take where the timeline says, and that no
 * device voice ever reaches a stored file. Nothing here plays or records
 * sound: the microphone, the speaker, and the mix engine are fakes.
 *   node js/plays.test.js
 *
 * Broken controls, 2026-10-23, each against a mutated copy of js/plays-*.js:
 *   Relay take() without the "another part is recording" guard: the relay test fails.
 *   addTake() appending without moving `chosen`: the take-replacement test fails.
 *   buildTimeline() without the gap: the timeline test fails.
 *   The session keeping the whole capture (no lineWindow): the stand-in test fails on take length.
 *   The store writing takes with put() instead of add(): the never-overwritten check fails.
 *   usableTake() ignoring `bleed`: the flagged-take test fails (the play reads complete and mixes the device voice).
 * Broken control, 2026-10-24: ListenThrough writing the buffer its voice hands back as a take:
 *   the synthetic-buffer guard fails three ways (writes, new files, the source scan).
 * The stand-in scan carries its own control (leaky): when the microphone hears
 * the device voice, the scan must find it in a take and the meter must flag it.
 * The source scan carries its own controls (a writer in the voice file, an
 * encoder call in the UI, a recorder of the page's output anywhere).
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.resolve(__dirname, '..');
/** tools/sound_mutants.mjs points this at a broken copy of js/. */
const JS = process.env.PLAYS_JS_DIR || __dirname;
for (const f of ['plays-core.js', 'plays-store.js', 'voice-cast.js', 'plays-voice.js', 'plays-session.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(JS, f), 'utf8'), { filename: f });
}
const C = vm.runInThisContext('PlaysCore');
const PlayStore = vm.runInThisContext('PlayStore');
const StandInVoice = vm.runInThisContext('StandInVoice');
const RecordingSession = vm.runInThisContext('RecordingSession');
const ListenThrough = vm.runInThisContext('ListenThrough');

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const pass = JSON.stringify(a) === JSON.stringify(b);
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
function throwsKind(fn, kind, detail, name) {
  try { fn(); ok(false, `${name}: did not throw`); } catch (e) {
    eq({ kind: e.kind, detail: e.detail }, { kind, detail }, name);
  }
}
const test = (name, fn) => results.push([name, fn]);

/* ---- Fixtures ---- */

function line(id, role, kind = 'speech', text = 'words') {
  return kind === 'speech' ? { id, kind, role, parts: [{ say: text }] } : { id, kind, source: text };
}
/** MOLLY 5 lines, FIBBER 3, DOC 1, one sound cue, one direction (Apple's fixture). */
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

function tone(hz, seconds, amplitude = 0.3, rate = 48000) {
  const out = new Float32Array(Math.round(seconds * rate));
  for (let i = 0; i < out.length; i++) {
    const t = i / rate;
    out[i] = amplitude * hz.reduce((s, f) => s + Math.sin(2 * Math.PI * f * t), 0) / hz.length;
  }
  return out;
}
const zeros = (n) => new Float32Array(n);
function join(...parts) {
  const out = new Float32Array(parts.reduce((s, p) => s + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

function take(id, lineID, part, frames, loudness = -16, peak = 0.5) {
  return { id, lineID, part, file: `${id}.wav`, created: 0, frames, sampleRate: 48000, capture: 'direct',
           heard: {}, loudness, peak, bleed: false };
}
function complete(script, frames = 4800) {
  let p = C.newProduction(script);
  for (const l of script.lines) if (l.kind === 'speech') p = C.addTake(p, take(`t-${l.id}`, l.id, C.linePart(l), frames));
  return p;
}

/** The mix engine: an OfflineAudioContext that sums its sources, sample-placed as the browser's is. */
function fakeOffline(channels, length, rate) {
  const sources = [];
  return {
    destination: {},
    createBuffer(c, n) { const d = new Float32Array(n); return { length: n, getChannelData: () => d }; },
    createGain() { const g = { gain: { value: 1 }, connect() {} }; return g; },
    createBufferSource() {
      const s = { buffer: null, connect(g) { s.g = g; }, start(when = 0, offset = 0) { s.when = when; s.offset = offset; sources.push(s); } };
      return s;
    },
    async startRendering() {
      const out = new Float32Array(length);
      for (const s of sources) {
        const at = Math.round(s.when * rate), off = Math.round(s.offset * rate), d = s.buffer.getChannelData(0);
        for (let i = off; i < d.length && at + i - off < length; i++) out[at + i - off] += d[i] * s.g.gain.value;
      }
      return { getChannelData: () => out };
    },
  };
}

const rmsAround = (x, center, half = 2400) => C.rms(x.subarray(Math.max(0, center - half), Math.min(x.length, center + half)));

/* ---- The relay ---- */

test('the relay takes parts in any order, the largest suggested (C7)', () => {
  const script = fixtureScript();
  const R = (n) => C.role(n);
  eq(C.order(script), [R('MOLLY'), R('FIBBER'), R('DOC'), C.SOUND, C.DIRECTIONS], 'the order');
  let p = C.newProduction(script);
  eq(C.next(p, script), R('MOLLY'), 'the largest part is suggested');
  const doc = C.take(p, script, R('DOC'), '');
  eq(C.current(doc, script), R('DOC'), 'a smaller part can be taken first');
  const silent = C.leaveSilent(p, script, C.SOUND);
  eq(C.stateOf(silent, C.SOUND).status, 'silent', 'sound can be left silent before any voice');
  throwsKind(() => C.take(silent, script, C.SOUND), 'notOpen', C.SOUND, 'a part that is not open cannot be taken');
  p = C.take(p, script, R('MOLLY'), '  Ada ');
  eq(C.stateOf(p, R('MOLLY')), { status: 'recording', performer: 'Ada' }, 'the name is trimmed and kept');
  eq(C.next(p, script), null, 'nothing is offered while a part records');
  throwsKind(() => C.take(p, script, R('FIBBER')), 'anotherPartIsRecording', R('MOLLY'), 'one part at a time');

  const molly = C.linesFor(script, R('MOLLY')).map(l => l.id);
  throwsKind(() => C.finish(p, script, R('MOLLY')), 'linesMissing', molly, 'a part is done only with every line taken');
  for (const id of molly) p = C.addTake(p, take(`t-${id}`, id, R('MOLLY'), 100));
  p = C.finish(p, script, R('MOLLY'));
  eq(C.next(p, script), R('FIBBER'), 'the next largest open part is suggested');
  throwsKind(() => C.leaveSilent(p, script, R('FIBBER')), 'speakingPartCannotBeSilent', undefined, 'a speaking part needs a voice (C6)');
  for (const part of [R('FIBBER'), R('DOC')]) {
    p = C.take(p, script, part, '');
    eq(C.stateOf(p, part), { status: 'recording' }, 'no name, no performer field');
    for (const l of C.linesFor(script, part)) p = C.addTake(p, take(`t-${l.id}`, l.id, part, 100));
    p = C.finish(p, script, part);
  }
  ok(C.isComplete(p, script), 'every speaking line has a human take');
  eq(C.next(p, script), C.SOUND, 'sound comes after the speaking parts');
  p = C.leaveSilent(p, script, C.SOUND);
  eq(C.next(p, script), C.DIRECTIONS, 'then directions');
  p = C.reopen(p, script, R('DOC'));
  eq(C.current(p, script), R('DOC'), 'a finished part can be reopened');
  throwsKind(() => C.reopen(p, script, R('MOLLY')), 'anotherPartIsRecording', R('DOC'), 'but only while no part records');
  eq(C.refusalText(new C.Refusal('linesMissing', ['a', 'b'])), '2 lines still need a take.', 'refusals have their words');
});

test('the cue is the line before when someone else speaks it', () => {
  const script = fixtureScript();
  eq(C.cueLines(script, 'L0003').map(l => l.id), ['L0002'], 'the previous speech');
  eq(C.cueLines(script, 'L0007').map(l => l.id), [], 'my own line before: no cue');
  eq(C.cueLines(script, 'L0006').map(l => l.id), ['L0005'], 'the sound cue between is not voiced');
  eq(C.cueLines(script, 'L0007', true).map(l => l.id), ['L0005', 'L0006'], 'a run-up is the two before');
  eq(C.cueLines(script, 'L0002', true).map(l => l.id), [], 'the first speech has no cue');
});

test('the cast sheet lists parts largest first, with directions and sound as parts', () => {
  const parts = C.castParts(fixtureScript());
  eq(parts.map(p => [p.title, p.lineCount]),
    [['MOLLY', 5], ['FIBBER', 3], ['DOC', 1], ['Sound', 1], ['Stage directions', 1]], 'titles and counts');
  eq(C.displayName('Carlton, Henry Fisk'), 'Henry Fisk Carlton', 'a filed name reads in order');
  eq(C.displayName('Baker, 1832-1890'), 'Baker, 1832-1890', 'control: a date is not a first name');
});

/* ---- A first take without an account; empty productions (Decision 079, PLAYS-DESIGN §2.3) ---- */

test('signed out, a second production asks for an account; an empty one does not count', () => {
  const script = fixtureScript();
  const empty = C.newProduction(script);
  const taken = { ...C.newProduction(script), takes: [{ id: 't', lineID: 'L0003' }] };
  eq(C.secondProductionNeedsAccount([], false), false, 'the first production needs none');
  eq(C.secondProductionNeedsAccount([empty], false), false, 'a production with no take does not count');
  eq(C.secondProductionNeedsAccount([empty, taken], false), true, 'one with a take makes the next a second');
  eq(C.secondProductionNeedsAccount([taken], true), false, 'signed in, nothing is asked');
  eq([C.isEmptyProduction(empty), C.isEmptyProduction(taken)], [true, false], 'empty means no take');
});

test('Made here leads Home while there are one to five finished ear dramas (WEB-DESIGN §4.2 item 7a)', () => {
  eq([0, 1, 5, 6, 12].map(n => C.madeHereLeads(n, false)), [false, true, true, false, false], 'one to five lead');
  eq(C.madeHereLeads(3, true), false, 'a further page means more than a page, never fewer than six');
});

test('the store deletes a local production with no take when it loads; shared and taken ones stay', async () => {
  const script = fixtureScript();
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  const empty = await store.create(script);
  const shared = await store.create(script);
  await store.setShare(shared.id, { pid: 'pid-x' });
  const taken = await store.create(script);
  await store.save({ ...taken, takes: [{ id: 't', lineID: 'L0003', file: 'a.wav' }] });
  eq(store.productions.length, 3, 'a store already loaded keeps what it made');
  const next = PlayStore.open(backend);
  await next.load();
  eq(next.productions.map(p => p.id).sort(), [shared.id, taken.id].sort(), 'the empty one is gone on the next load');
  eq(await backend.keys(`${empty.id}/`), [], 'with its folder');
});

/* ---- Takes ---- */

test('a re-take is chosen, and the old take stays until discarded (§8 rule 5)', async () => {
  const script = fixtureScript();
  const backend = PlayStore.memoryBackend();
  const replaced = [];
  const spied = { ...backend, put: (k, v) => { if (/\/(takes|roomtone)\//.test(k)) replaced.push(k); return backend.put(k, v); } };
  const store = PlayStore.open(spied);
  await store.load();
  let p = await store.create(script);
  const capture = { samples: tone([200], 0.2), sampleRate: 48000 };
  const first = await store.writeTake(capture, p, 'L0003');
  const second = await store.writeTake(capture, p, 'L0003');
  ok(first !== second, 'a take file is never overwritten');
  let refused = false;
  try { await backend.add(`${p.id}/takes/${first}`, new ArrayBuffer(4)); } catch { refused = true; }
  ok(refused, 'the take writer refuses an existing path');
  await store.writeRoomTone(capture, p);
  eq(replaced, [], 'takes and room tone are written only by add(), which never replaces');

  const a = { ...take('a', 'L0003', C.role('MOLLY'), 9600, -20, 0.3), file: first, heard: { L0002: C.STANDIN } };
  const b = { ...take('b', 'L0003', C.role('MOLLY'), 9600, -20, 0.3), file: second, heard: { L0002: C.STANDIN } };
  p = C.addTake(C.addTake(p, a), b);
  eq(p.chosen.L0003, 'b', 'the re-take becomes the line\'s take');
  eq(C.takesFor(p, 'L0003').map(t => t.id), ['a', 'b'], 'choosing never deletes the old take');
  p = C.choose(p, 'a');
  eq(C.chosenTake(p, 'L0003').id, 'a', 'an older take can be chosen again');
  await store.save(p);

  await store.discardUnusedTakes(p.id);
  const kept = store.production(p.id);
  eq(kept.takes.map(t => t.id), ['a'], 'discard removes the unused take from the record');
  eq(await backend.keys(`${p.id}/takes/`), [`${p.id}/takes/${first}`], 'and only its file');

  const reloaded = PlayStore.open(backend);
  await reloaded.load();
  eq(C.stableStringify(reloaded.production(p.id)), C.stableStringify(kept), 'the record survives a reload');
  eq((await reloaded.script(kept)).lines.length, script.lines.length, 'the script as cast is stored with it');
  const record = JSON.parse(await backend.get(`${p.id}/production.json`));
  eq(Object.keys(record), Object.keys(record).slice().sort(), 'production.json is written with sorted keys');
  eq(Object.keys(record).sort(), ['chosen', 'created', 'format', 'id', 'listenedThrough', 'parts', 'roomTone', 'scriptID',
                                  'scriptRevision', 'takes', 'title'], 'the fields of Apple\'s production.json');
  eq(Object.keys(record.takes[0]).sort(), ['bleed', 'capture', 'created', 'file', 'frames', 'heard', 'id', 'lineID',
                                           'loudness', 'part', 'peak', 'sampleRate'], 'a take has Apple\'s fields');

  await reloaded.delete(p.id);
  eq(await backend.keys(`${p.id}/`), [], 'delete removes every file of the production');
  eq(reloaded.productions.length, 0, 'and its record');
});

test('a new take resets the listen-through, and a finished play needs a fresh mix', () => {
  const script = fixtureScript();
  let p = complete(script);
  p = { ...p, mixedFrom: C.fingerprint(p), listenedThrough: true };
  ok(C.isFinished(p), 'heard through and mixed from these takes');
  p = C.addTake(p, take('again', 'L0003', C.role('MOLLY'), 4800));
  ok(!C.isFinished(p), 'a re-take un-finishes it');
});

test('a take is the line window only (onset less 250 ms to end plus 250 ms)', () => {
  const rate = 48000;
  const capture = join(zeros(48000), tone([180], 0.5), zeros(72000));
  const d = new C.LineEndDetector(rate, 0.0005);
  const events = [];
  for (let s = 0; s < capture.length; s += 960) {
    const e = d.feed(capture.subarray(s, Math.min(s + 960, capture.length)));
    if (e) events.push(e.type);
  }
  eq(events, ['onset', 'end'], 'one onset, one end');
  const [from, to] = C.lineWindow(d.onset, d.end, capture.length, rate);
  ok(Math.abs(from - 36000) <= 960, `onset less 250 ms (${from})`);
  ok(Math.abs(to - 84000) <= 960, `end plus 250 ms (${to})`);
  eq(C.lineWindow(null, null, 500, rate), [0, 500], 'no onset keeps the whole capture');
  const at44 = new C.LineEndDetector(44100, 0);
  eq(at44.frameLength, 882, 'the detector reads 20 ms frames at any rate');
});

/* ---- The timeline ---- */

test('lines follow in script order with a gap, and a re-take ripples', () => {
  const script = fixtureScript();
  let p = complete(script, 4800);
  const gap = Math.floor(C.DEFAULT_GAP * 48000);
  const t = C.buildTimeline(script, p);
  eq(t.placements.map(x => x.lineID), C.speechLineIDs(script), 'silent cues are left out');
  eq(t.placements.map(x => x.start), [...Array(9).keys()].map(i => i * (4800 + gap)), 'each starts after a gap');
  eq(t.totalFrames, 9 * 4800 + 8 * gap, 'the total');
  p = C.addTake(p, take('long', 'L0003', C.role('MOLLY'), 4800 + 24000));
  const r = C.buildTimeline(script, p);
  eq(r.placements[0].start, 0, 'the first line stays');
  eq(r.placements[1].takeID, 'long', 'the re-take is placed');
  ok(t.placements.slice(2).every((x, i) => r.placements[i + 2].start - x.start === 24000), 'every later line moves by the difference');
  p = C.addTake(p, take('door', 'L0004', C.SOUND, 1000));
  ok(C.buildTimeline(script, p).placements.some(x => x.lineID === 'L0004'), 'a recorded sound cue is placed');
});

test('the gain reaches -16 LUFS, held under the -1 dBFS ceiling', () => {
  ok(Math.abs(C.gain(-26, 0.1) - Math.pow(10, 10 / 20)) < 1e-6, '+10 dB');
  ok(Math.abs(20 * Math.log10(C.gain(-26, 0.5) * 0.5) - -1) < 1e-6, 'the peak lands at -1 dBFS');
  eq(C.gain(null, 0.5), 1, 'unmeasured plays at unity');
});

test('a partial play has no timeline, no mix file, and no export (§5 rules 3 and 4)', async () => {
  const script = fixtureScript();
  const p0 = complete(script);
  const p = { ...p0, chosen: { ...p0.chosen } };
  delete p.chosen.L0005;
  throwsKind(() => C.buildTimeline(script, p), 'incomplete', ['L0005'], 'the missing line is named');
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  const made = await store.create(script);
  await store.save({ ...p, id: made.id });
  let kind = null;
  try { await store.renderMix(made.id, fakeOffline); } catch (e) { kind = e.kind; }
  eq(kind, 'incomplete', 'the store refuses to mix it');
  eq(await backend.get(`${made.id}/mix.wav`), null, 'and writes nothing');
  kind = null;
  try { await store.exportMix(made.id); } catch (e) { kind = e.kind; }
  eq(kind, 'unfinished', 'an unfinished play cannot be exported');
});

test('a flagged take leaves its line to re-take, and the mix refuses it (§5 rule 2, §8 rule 3)', async () => {
  const script = fixtureScript();
  const p0 = complete(script);
  let p = { ...p0, takes: p0.takes.filter(t => t.lineID !== 'L0005'), chosen: { ...p0.chosen } };
  delete p.chosen.L0005;
  p = C.addTake(p, { ...take('leaky', 'L0005', C.role('DOC'), 4800), bleed: true });
  eq(p.chosen.L0005, 'leaky', 'the flagged take is kept and chosen');
  ok(!C.isComplete(p, script), 'a flagged take does not complete its line');
  eq(C.missingSpeech(p, script), ['L0005'], 'the line still needs a voice');
  eq(C.needsRetake(p, script), ['L0005'], 'the line needs a re-take');
  eq(C.missingLines(p, script, C.role('DOC')), ['L0005'], 'the part is not done');
  throwsKind(() => C.buildTimeline(script, p), 'incomplete', ['L0005'], 'no timeline');

  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  const made = await store.create(script);
  await store.save({ ...p, id: made.id });
  let kind = null;
  try { await store.renderMix(made.id, fakeOffline); } catch (e) { kind = e.kind; }
  eq(kind, 'incomplete', 'the store refuses to mix it');
  eq(await backend.get(`${made.id}/mix.wav`), null, 'and writes nothing');

  const good = C.buildTimeline(script, complete(script));
  const leaky = { ...good, placements: good.placements.map((x, i) => (i === 0 ? { ...x, bleed: true } : x)) };
  let loaded = false;
  kind = null;
  try { await C.renderMix(leaky, async () => { loaded = true; return tone([440], 0.1); }, fakeOffline); } catch (e) { kind = e.kind; }
  eq(kind, 'bleed', 'the renderer refuses a flagged take');
  ok(!loaded, 'no take is read');

  p = C.addTake(p, take('clean', 'L0005', C.role('DOC'), 4800));
  ok(C.isComplete(p, script), 'a later unflagged take completes the line');
  eq(C.takesFor(p, 'L0005').map(t => t.id), ['leaky', 'clean'], 'the flagged take stays');
  const t = C.buildTimeline(script, p);
  eq(t.placements.find(x => x.lineID === 'L0005').takeID, 'clean', 'the clean take is placed');
  ok(t.placements.every(x => !x.bleed), 'nothing flagged is placed');

  p = C.addTake(p, { ...take('door', 'L0004', C.SOUND, 1000), bleed: true });
  ok(!C.isComplete(p, script), 'a flagged sound cue is not mixed either');
  throwsKind(() => C.buildTimeline(script, p), 'bleed', ['L0004'], 'the flagged cue is named');
});

/* ---- The mix ---- */

test('the mix puts each take where the timeline says', async () => {
  const script = fixtureScript();
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  let p = await store.create(script);
  const samples = tone([440], 0.3);
  for (const l of script.lines) {
    if (l.kind !== 'speech') continue;
    const file = await store.writeTake({ samples, sampleRate: 48000 }, p, l.id);
    p = C.addTake(p, { ...take(`t-${l.id}`, l.id, C.linePart(l), samples.length), file,
                       loudness: C.integratedLoudness(samples, 48000), peak: C.samplePeak(samples) });
  }
  await store.save(p);
  const timeline = C.buildTimeline(script, p);
  const blob = await store.renderMix(p.id, fakeOffline);
  const mix = C.decodeWav(await blob.arrayBuffer());
  eq(mix.sampleRate, 48000, 'the mix is at the take rate');
  eq(mix.samples.length, timeline.totalFrames, 'the mix is as long as its timeline');
  timeline.placements.forEach((x, i) => {
    ok(rmsAround(mix.samples, x.start + x.frames / 2) > 0.05, `take ${i} sounds where it is placed`);
    const n = timeline.placements[i + 1];
    if (n) ok(rmsAround(mix.samples, Math.floor((x.start + x.frames + n.start) / 2), 1200) < 0.01, `the gap after take ${i} is quiet`);
  });
  eq(store.production(p.id).mixedFrom, C.fingerprint(p), 'the record says which takes it was made from');
  ok((await backend.get(`${p.id}/mix.wav`)) !== null, 'mix.wav is kept with the production');

  const chunked = await C.renderMix(timeline, async (x) => C.decodeWav(await store.readTake(p.id, x.file)).samples,
                                    fakeOffline, { chunkSeconds: 0.25 });
  const c = C.decodeWav(await chunked.arrayBuffer()).samples;
  let diff = 0;
  for (let i = 0; i < c.length; i++) diff = Math.max(diff, Math.abs(c[i] - mix.samples[i]));
  ok(c.length === mix.samples.length && diff < 1e-4, `rendering in chunks changes nothing (max diff ${diff})`);
});

test('loudness: a full-scale 1 kHz sine reads -3.01 LUFS; WAV round-trips at 24 bits', () => {
  const full = tone([1000], 3, 1);
  ok(Math.abs(C.integratedLoudness(full, 48000) - -3.01) < 0.05, 'full scale');
  ok(Math.abs(C.integratedLoudness(full.map(x => x * 0.1), 48000) - -23.01) < 0.05, '-20 dB');
  eq(C.integratedLoudness(zeros(48000), 48000), null, 'silence is unmeasured');
  const x = tone([300], 0.1, 0.8);
  const back = C.decodeWav(C.encodeWav(x, 48000, 24));
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff = Math.max(diff, Math.abs(back.samples[i] - x[i]));
  ok(back.sampleRate === 48000 && back.samples.length === x.length && diff < 1e-6, `24-bit round trip (${diff})`);
});

/* ---- No device voice reaches a file (§5) ---- */

/** The bleed check's correlation, here only: the web never holds the device voice's samples. */
function correlation(signal, reference) {
  const f = 24;
  const dec = (x) => { const o = new Float32Array(Math.floor(x.length / f)); for (let i = 0; i < o.length; i++) { let s = 0; for (let j = 0; j < f; j++) s += x[i * f + j]; o[i] = s / f; } return o; };
  const s = dec(signal), r = dec(reference);
  if (!s.length || !r.length) return 0;
  const [long, short] = s.length >= r.length ? [s, r] : [r, s];
  let sn = 0; for (const v of short) sn += v * v;
  if (sn < 1e-12) return 0;
  const padded = join(zeros(short.length - 1), long, zeros(short.length - 1));
  let best = 0;
  for (let lag = 0; lag + short.length <= padded.length; lag++) {
    let dot = 0, w = 0;
    for (let i = 0; i < short.length; i++) { const v = padded[lag + i]; dot += v * short[i]; w += v * v; }
    if (w <= sn * 0.05) continue;
    best = Math.max(best, Math.abs(dot) / Math.sqrt(sn * w));
  }
  return Math.min(best, 1);
}

/** A device voice whose every line is a chirp the scan can look for. It "plays" to the
 *  speaker beside the microphone; speak() hands the session nothing, as speechSynthesis does. */
function signatureVoice(room) {
  const rendered = [];
  return {
    rendered,
    speak(text) {
      let h = 0; for (const ch of text) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
      const f0 = 300 + (h % 100);
      const sig = new Float32Array(24000);
      for (let i = 0; i < sig.length; i++) { const t = i / 48000; sig[i] = 0.3 * Math.sin(2 * Math.PI * (f0 * t + 500 * t * t)); }
      rendered.push(sig);
      room.speaker = sig;
      return Promise.resolve(true);
    },
    cancel() {},
  };
}

/** Plays nothing, records nothing: the microphone hears a performer, or, when leaky, the speaker. */
function fakeAudio(room, leaky) {
  let captures = 0;
  let captured = zeros(0);
  return {
    sampleRate: 48000, capture: 'direct',
    async start() {}, stop() {},
    beginCapture(onChunk) {
      captures += 1;
      captured = captures === 1
        ? Float32Array.from({ length: 48000 }, () => (Math.random() - 0.5) * 0.001)
        : join(zeros(9600), leaky && room.speaker ? room.speaker : tone([150, 175], 0.6), zeros(60000));
      for (let s = 0; s < captured.length; s += 960) onChunk(captured.subarray(s, Math.min(s + 960, captured.length)));
    },
    endCapture() { const c = captured; captured = zeros(0); return { samples: c, sampleRate: 48000 }; },
    startMeter() { room.metered = room.speaker = null; },
    stopMeter() { return leaky && room.speaker ? 1 : 0; },
    async playTake() {}, stopPlayback() {},
    async toTakeRate(c) { return c; },
  };
}

async function recordWholePlay(leaky) {
  const script = fixtureScript();
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  let p = await store.create(script);
  const room = { speaker: null };
  const voice = signatureVoice(room);
  for (const part of C.order(script).filter(C.isSpeaking)) {
    p = C.take(store.production(p.id), script, part, '');
    await store.save(p);
    const s = RecordingSession.create({ production: p, script, part, store, audio: fakeAudio(room, leaky), voice,
                                        sleep: async () => {} });
    await s.begin();
    for (const l of s.lines) await s.record(l.id);
    s.end();
    if (leaky) {
      let refused = null;
      try { C.finish(store.production(p.id), script, part); } catch (e) { refused = e.kind; }
      eq(refused, 'linesMissing', 'a part whose takes are flagged is not done');
      p = store.production(p.id);
      break;
    }
    p = C.finish(store.production(p.id), script, part);
    await store.save(p);
  }
  if (leaky) {
    ok(!C.isComplete(p, script), 'flagged takes leave the play unfinished');
  } else {
    ok(C.isComplete(p, script), 'every speaking line was recorded');
    await store.renderMix(p.id, fakeOffline);
  }
  const findings = [];
  for (const key of await backend.keys(`${p.id}/`)) {
    if (key.endsWith('.json')) continue;
    if (!key.endsWith('.wav')) { findings.push(`unexpected file ${key}`); continue; }
    const audio = C.decodeWav(await backend.get(key));
    for (const sig of voice.rendered) {
      if (correlation(audio.samples, sig) >= 0.5) { findings.push(key); break; }
    }
  }
  return { findings, signatures: voice.rendered.length, production: store.production(p.id), keys: await backend.keys(`${p.id}/`) };
}

test('no take, room tone, or mix holds the device voice', async () => {
  const run = await recordWholePlay(false);
  ok(run.signatures > 0, 'the first parts were cued by the device voice');
  eq(run.findings, [], 'the scan finds no device voice in any stored file');
  ok(run.keys.some(k => k.includes('/roomtone/')) && run.keys.some(k => k.endsWith('/mix.wav')), 'room tone and the mix were scanned');
  const takes = run.production.takes;
  ok(takes.every(t => !t.bleed), 'no take is flagged');
  ok(takes.every(t => t.frames < 60000), 'a take is the line window, not the whole capture');
  ok(takes.some(t => Object.values(t.heard).includes(C.STANDIN)), 'some lines were cued by the device voice');
  ok(takes.some(t => Object.values(t.heard).some(v => v !== C.STANDIN)), 'later parts heard the earlier performers\' takes');
});

test('control: a microphone that hears the device voice is caught', async () => {
  const run = await recordWholePlay(true);
  ok(run.findings.length > 0, 'the scan must find the device voice in a take');
  ok(run.production.takes.some(t => t.bleed), 'the level meter flags the take');
});

test('a listen plan is takes and words: open speech read live, open sound and directions skipped (C5)', () => {
  const script = fixtureScript();
  let p = C.newProduction(script);
  p = C.addTake(p, take('t3', 'L0003', C.role('MOLLY'), 100));
  p = C.addTake(p, { ...take('leak', 'L0005', C.role('DOC'), 100), bleed: true });
  const plan = C.listenPlan(p, script);
  eq(plan.map(e => [e.lineID, e.source]), script.lines.filter(l => l.id === 'L0003' || l.kind === 'speech')
    .map(l => [l.id, l.id === 'L0003' ? 'take' : 'voice']), 'the take plays, every other speech is read, the flagged take is not used');
  for (const e of plan.filter(x => x.source === 'voice')) {
    eq(Object.keys(e).sort(), ['lineID', 'part', 'source', 'text'], `${e.lineID}: a voice entry is words only`);
    eq(typeof e.text, 'string', `${e.lineID}: its words`);
  }
});

test('a play is marked only by facts from its record (Decision 067)', () => {
  const script = { ...fixtureScript(), authors: [{ name: 'Carlton, Henry Fisk', born: 1893, died: 1973 },
                                                 { name: 'Other, Ann', born: 1901 }, { name: 'Last, Al', died: 1950 }] };
  eq(C.authorFacts(script), 'Henry Fisk Carlton (1893–1973), Ann Other (b. 1901), Al Last (d. 1950)', 'authors with their years');
  eq(C.lengthLine(script), `3 parts · ${script.lines.length} lines`, 'speaking parts and every line, as Apple and Android count');
});

test('an author reads by the record\'s display name, never the filed form (Decision 075)', () => {
  const script = { ...fixtureScript(), authors: [{ name: 'Baker, George M. (George Melville)', display: 'George Melville Baker' },
                                                 { name: 'Carlton, Henry Fisk' }] };
  eq(C.authorLine(script), 'George Melville Baker, Henry Fisk Carlton', 'display first, else the filed name turned');
});

test('today\'s play: the golden rotation every platform runs (catalog/tests/golden/todays_play.json)', () => {
  const g = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'tests', 'golden', 'todays_play.json'), 'utf8'));
  g.hashes.forEach(h => eq(C.fnv1a64(h.text).toString(16).padStart(16, '0'), h.fnv1a64, `fnv1a64 of ${JSON.stringify(h.text)}`));
  g.cases.forEach(c => {
    const got = C.todaysPlay((c.ids || g.ids).map(id => ({ id })), c.date);
    eq(got ? got.id : null, c.want, `${c.date} over ${(c.ids || g.ids).length} ids`);
  });
  const reversed = [...g.ids].reverse().map(id => ({ id }));
  eq(C.todaysPlay(reversed, g.cases[0].date).id, g.cases[0].want, 'order-independent');
  ok(new Set(g.cases.slice(0, 8).map(c => c.want)).size > 1, 'control: the pick changes with the date');
});

test('today\'s scene: today\'s play among the short plays for two (WEB-DESIGN §4.2, §4.15)', () => {
  const row = (id, voices, minutes) => ({ id, voices, minutes });
  const lib = [row('long2', 2, 255), row('a', 2, 12), row('b', 2, 17), row('c', 3, 25), row('big', 12, 175)];
  eq(C.scenePool(lib).map(s => s.id).join(','), 'a,b', 'two voices, at most 20 minutes');
  eq(C.todaysScene(lib, '2026-11-15').id, C.todaysPlay([lib[1], lib[2]], '2026-11-15').id, 'todaysPlay over the pool');
  eq(C.scenePool([lib[0], lib[3], lib[4]]).map(s => s.id).join(','), 'c', 'else two or three voices, at most 30');
  eq(C.scenePool([lib[0], lib[4]]).length, 2, 'else every play');
  eq(C.todaysScene([], '2026-11-15'), null, 'an empty library has no scene');
});

test('today\'s scene: the golden every platform runs (todays_play.json `scene`, Decision 079)', () => {
  const g = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'tests', 'golden', 'todays_play.json'), 'utf8')).scene;
  g.cases.forEach(c => {
    const rows = c.ids ? g.rows.filter(r => c.ids.includes(r.id)) : g.rows;
    const got = C.todaysScene(rows, c.date);
    eq(got ? got.id : null, c.want, `${c.date} over ${rows.length} rows`);
  });
  ok(g.cases.some(c => !c.ids && C.todaysPlay(g.rows, c.date).id !== c.want), 'control: the scene is not today\'s play over every row');
});

test('the opening speeches: said words only, from the lines or the index row (contract §4.1)', () => {
  const s = { lines: [{ id: 'L1', kind: 'direction', source: '_Night._' },
    { id: 'L2', kind: 'speech', role: 'JIM', parts: [{ direction: 'low' }, { say: "That's  a _full_ one." }] },
    { id: 'L3', kind: 'speech', role: 'BILL', parts: [{ direction: 'enters' }] },
    { id: 'L4', kind: 'speech', role: 'BILL', parts: [{ say: '. Why--hullo.' }] }] };
  const o = C.openingOf(s);
  eq(o.map(x => `${x.name}|${x.text}|${x.id}`).join(' / '), "JIM|That's a full one.|L2 / BILL|Why\u2014hullo.|L4", 'directions and silent speeches skipped');
  eq(o[0].part, 'role:JIM', 'the part id');
  eq(C.openingOf(s, 1).length, 1, 'at most n');
  const idx = C.openingOf({ opening: [{ role: 'A', text: 'One.' }, { role: 'B', text: ' ' }, { role: 'B', text: 'Two.' }] });
  eq(idx.map(x => x.name + x.text).join(','), 'AOne.,BTwo.', 'an index row\'s opening, blanks dropped');
  eq(C.openingOf({ voices: 2 }).length, 0, 'a row published before `opening` has none');
});

test('a play\'s voices and minutes, and their bands (WEB-DESIGN §4.15)', () => {
  const s = { ...fixtureScript(), roles: [{ name: 'A', words: 3000 }, { name: 'B', words: 1500 }, { name: 'C', words: 10 }] };
  eq(C.voicesOf(s), 3, 'one voice per role');
  eq(C.minutesOf(s), 30, '4,510 words at 150 a minute');
  eq([C.voiceBand(s), C.lengthBand(s)], ['3-5', 'mid'], 'bands');
  eq(C.lengthBand({ roles: [{ words: 100 }] }), 'short', 'at least a minute, under 30 is short');
  eq(C.voiceBand({ roles: Array.from({ length: 11 }, () => ({ words: 1 })) }), '11+', 'eleven and up');
});

test('a class picks from the whole library: by name, one title told apart by author, then length (WEB-DESIGN §4.19)', () => {
  const rows = [
    { id: 'gut-2', title: 'The Robbers', sort_name: 'robbers', authors: ['A. Player'] },
    { id: 'gut-3', title: 'Ghosts', sort_name: 'ghosts', authors: ['Henrik Ibsen'] },
    { id: 'gut-1', title: 'The Robbers', sort_name: 'robbers', authors: ['Friedrich Schiller'] },
    { id: 'gut-5', title: 'Belinda', sort_name: 'belinda', authors: ['A. A. Milne'], minutes: 90 },
    { id: 'gut-4', title: 'Belinda', sort_name: 'belinda', authors: ['A. A. Milne'], minutes: 84 },
    { id: 'gut-6', title: 'Anon', authors: [] },
  ];
  eq(C.pickList(rows), [
    { id: 'gut-6', label: 'Anon' },
    { id: 'gut-4', label: 'Belinda, A. A. Milne, about 84 min' },
    { id: 'gut-5', label: 'Belinda, A. A. Milne, about 90 min' },
    { id: 'gut-3', label: 'Ghosts' },
    { id: 'gut-1', label: 'The Robbers, Friedrich Schiller' },
    { id: 'gut-2', label: 'The Robbers, A. Player' },
  ], 'the list');
  eq(C.pickList([]), [], 'an empty library');
  const page = fs.readFileSync(path.join(__dirname, 'class-ui.js'), 'utf8');
  ok(/API\.playLibrary\(\)\.then\(\(rows\) => \{\s*sel\.append\(\.\.\.C\.pickList\(rows\)/.test(page) && !page.includes('castableScripts'), 'the class page reads the library, never the bundle alone');
});

/** A store whose every write is counted, over a production half recorded. */
async function halfRecorded() {
  const script = fixtureScript();
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  let p = await store.create(script);
  const file = await store.writeTake({ samples: tone([200], 0.2), sampleRate: 48000 }, p, 'L0003');
  p = C.addTake(store.production(p.id), { ...take('t3', 'L0003', C.role('MOLLY'), 9600), file });
  await store.save(p);
  const writes = [];
  for (const k of ['add', 'put']) {
    const real = backend[k].bind(backend);
    backend[k] = async (key, value) => { writes.push(key); return real(key, value); };
  }
  return { script, backend, store, p, writes };
}

/** The guard (§5 rule 3): a device voice that HANDS BACK a synthetic buffer, as Apple's
 *  and Android's engines do, must still reach no take, mix, export, or upload. */
async function listenWithSyntheticBuffers() {
  const { script, backend, store, p, writes } = await halfRecorded();
  const synthetic = [];
  const voice = {
    async speak(text) { const b = Float32Array.from({ length: 4800 }, (_, i) => Math.sin(i / 7) * 0.3); synthetic.push(b); return b; },
    cancel() {},
  };
  const audio = { async startPlayback() {}, async playTake() {}, stopPlayback() {}, stop() {} };
  const keysBefore = await backend.keys();
  const l = ListenThrough.create({ production: p, script, store, audio, voice });
  await l.play();
  const keysAfter = await backend.keys();
  let exported = null;
  try { await store.exportMix(p.id, fakeOffline); } catch (e) { exported = e.kind; }
  return { synthetic: synthetic.length, writes, keysBefore, keysAfter, exported, production: store.production(p.id) };
}

test('guard: no synthetic buffer from a live listen-through reaches a take, the mix, an export, or an upload', async () => {
  const run = await listenWithSyntheticBuffers();
  ok(run.synthetic > 0, 'the device voice read the open lines and handed back buffers');
  eq(run.writes, [], 'the listen-through wrote nothing');
  eq(run.keysAfter, run.keysBefore, 'no file appeared');
  eq(run.production.takes.length, 1, 'no take was added');
  ok(!run.production.listenedThrough, 'a live listen-through never finishes the play');
  eq(run.exported, 'unfinished', 'and a play with device-voiced lines cannot be exported');
  const src = fs.readFileSync(path.join(__dirname, 'plays-session.js'), 'utf8');
  const listen = src.slice(src.indexOf('const ListenThrough'));
  eq(/\bstore\.(write|save|update|create|render|export|mark)\w*|\bfetch\s*\(|\bAPI\./.test(listen), false,
     'the listen-through calls no writer, renderer, exporter, or network');
});

/** Which modules may hold or write play audio. */
function writeViolations(file, source) {
  const out = [];
  if (/\bMediaRecorder\b|captureStream\s*\(|createMediaStreamDestination/.test(source)) out.push(`${file}: records an output stream`);
  // sound-store.js keeps a person's own sounds (B32 §3.4): a microphone capture or a file they brought, never a voice.
  if (/\bencodeWav\s*\(/.test(source) && !['plays-core.js', 'plays-store.js', 'sound-store.js'].includes(file)) out.push(`${file}: encodes audio`);
  if (file === 'sound-store.js' && /StandInVoice|TableRead|Kokoro|\.speak\s*\(/.test(source)) out.push(`${file}: reaches a device voice`);
  if (/\b(speechSynthesis|SpeechSynthesisUtterance)\b/.test(source) && file !== 'plays-voice.js') out.push(`${file}: speaks`);
  if (file.startsWith('plays-') && file !== 'plays-store.js'
      && /\bindexedDB\b|createWritable|getDirectory\s*\(|\.download\s*=/.test(source)) out.push(`${file}: persists`);
  // Kokoro (S6 prototype): the voice and its worker render and play, and keep nothing; the model
  // file keeps model bytes, and has no audio path.
  if ((file === 'kokoro-voice.js' || file === 'kokoro-worker.js')
      && /\bindexedDB\b|\bcaches\.|localStorage|sessionStorage|createWritable|getDirectory\s*\(|\.download\s*=|\bBlob\b|createObjectURL|PlayStore/.test(source)) {
    out.push(`${file}: keeps synthetic audio`);
  }
  if (file === 'kokoro-model.js' && /AudioContext|AudioBuffer|createBufferSource|speechSynthesis|PlayStore/.test(source)) {
    out.push(`${file}: has an audio path`);
  }
  // The voices' gate and Library > Voices (Decision 086): a download and defaults, never a sound kept.
  if ((file === 'voices.js' || file === 'voice-settings.js')
      && /AudioContext|AudioBuffer|createBufferSource|\bBlob\b|createObjectURL|PlayStore|indexedDB|\.put\s*\(/.test(source)) {
    out.push(`${file}: has an audio path`);
  }
  if (file === 'plays-voice.js'
      && /AudioContext|getUserMedia|MediaStream|\bBlob\b|ArrayBuffer|Float32Array|encodeWav|PlayStore|indexedDB|fetch\s*\(|audioWorklet/.test(source)) {
    out.push(`${file}: has an audio path`);
  }
  return out;
}

test('only the store writes play audio, and the device voice has no audio path', () => {
  const offenders = [];
  for (const f of fs.readdirSync(__dirname)) {
    if (!f.endsWith('.js') || f.endsWith('.test.js')) continue;
    offenders.push(...writeViolations(f, fs.readFileSync(path.join(__dirname, f), 'utf8')));
  }
  for (const f of ['sw.js', 'tv.js']) offenders.push(...writeViolations(f, fs.readFileSync(path.join(ROOT, f), 'utf8')));
  eq(offenders, [], 'no module but the store writes audio');
  eq(writeViolations('plays-voice.js', 'const b = new Blob([x]);').length, 1, 'control: a writer in the voice file is caught');
  eq(writeViolations('plays-ui.js', 'PlaysCore.encodeWav(s, 48000)').length, 1, 'control: an encoder in the UI is caught');
  eq(writeViolations('app.js', 'new MediaRecorder(stream)').length, 1, 'control: a recorder anywhere is caught');
  eq(writeViolations('kokoro-voice.js', "caches.open('x').then(c => c.put(u, r))").length, 1, 'control: a cache write in the Kokoro voice is caught');
  eq(writeViolations('kokoro-worker.js', "indexedDB.open('x')").length, 1, 'control: storage in the Kokoro worker is caught');
  eq(writeViolations('kokoro-voice.js', 'URL.createObjectURL(new Blob([s]))').length, 1, 'control: a Blob of Kokoro audio is caught');
  eq(writeViolations('kokoro-model.js', 'new AudioContext()').length, 1, 'control: an audio path in the model file is caught');
  eq(writeViolations('voices.js', 'cache.put(u, new Response(new Blob([s])))').length, 1, 'control: a kept sound in the voices gate is caught');
  eq(writeViolations('voice-settings.js', 'new AudioContext()').length, 1, 'control: an audio path in Library > Voices is caught');
});

test('the device voice offers only local English voices and is silent when muted', async () => {
  const voices = [
    { name: 'Cloud', lang: 'en-US', localService: false, default: true },
    { name: 'Ava', lang: 'en-US', localService: true, default: false },
    { name: 'Thomas', lang: 'fr-FR', localService: true, default: false },
    { name: 'Daniel', lang: 'en-GB', localService: true, default: false },
  ];
  eq(StandInVoice.castableVoices(voices, 'en-US').map(v => v.name), ['Ava', 'Daniel'], 'local English, the reader\'s own first');
  const spoken = [];
  const synth = { getVoices: () => voices, speak(u) { spoken.push(u); setTimeout(() => u.onend(), 0); }, cancel() {} };
  function Utterance(text) { this.text = text; }
  const v = StandInVoice.create({ muted: true, synth, Utterance, language: 'en-US' });
  eq(await v.speak('Yes, dearie?', 'role:MOLLY'), true, 'a line is read');
  eq(await v.speak('Doc!', 'role:FIBBER'), true, 'another part');
  eq(spoken.map(u => [u.voice.name, u.volume]), [['Ava', 0], ['Daniel', 0]], 'one voice per part, muted');
  const none = StandInVoice.create({ synth: { getVoices: () => [voices[0]], speak() { throw new Error('spoke'); }, cancel() {} }, Utterance });
  eq(await none.speak('Hello', 'role:X'), false, 'with no local voice nothing is sent to a speech server');
});

/* ---- The data ---- */

test('the bundled castable scripts decode, and each can be cast', () => {
  const lib = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog/plays/castable-scripts.json'), 'utf8'));
  eq(lib.format, 1, 'format 1');
  ok(lib.scripts.length > 0, 'there are scripts');
  const castable = new Set(['script_gov_work', 'script_pd_published_age', 'script_registered_age',
                            'script_source_cleared', 'script_registered_not_renewed', 'script_author_died']);
  for (const s of lib.scripts) {
    ok(castable.has(s.rights.bucket), `${s.id} is castable`);
    ok(s.rights.evidence.some(e => e.claim), `${s.id} carries a claim to show`);
    ok(C.castParts(s).filter(x => C.isSpeaking(x.id)).length >= 2, `${s.id} has parts`);
    ok(new Set(s.lines.map(l => l.id)).size === s.lines.length, `${s.id} line ids are unique`);
  }
});

test('the service worker treats the castable scripts as data and ships the plays shell', () => {
  const src = fs.readFileSync(path.join(ROOT, 'sw.js'), 'utf8');
  const handlers = {};
  const scope = 'https://eardrama.org/';
  const ctx = {
    self: { addEventListener: (t, fn) => { handlers[t] = fn; }, registration: { scope }, location: new URL(scope),
            clients: { claim: () => Promise.resolve() }, skipWaiting: () => Promise.resolve() },
    caches: { open: async () => ({ match: async () => undefined, put: async () => {} }), keys: async () => [] },
    fetch: async () => new Response('{}'), URL, Request, Response, Promise, setTimeout, console,
  };
  vm.runInNewContext(`${src}\n;globalThis.__shell = SHELL;`, ctx);
  let answered = false;
  handlers.fetch({ request: { url: `${scope}data/plays/castable-scripts.json`, destination: '', mode: 'cors', method: 'GET',
                              headers: new Headers() }, respondWith: () => { answered = true; } });
  ok(answered, 'data/plays/castable-scripts.json is answered as data');
  for (const f of ['js/plays-core.js', 'js/plays-store.js', 'js/plays-voice.js', 'js/plays-audio.js',
                   'js/plays-session.js', 'js/plays-ui.js', 'js/plays-worklet.js']) {
    ok(ctx.__shell.includes(f), `${f} is in the shell`);
  }
});

/* ---- The three recording modes (owner ruling 4, D3-6) ---- */

test('a part\'s face color: the seven largest speaking parts in a fixed order, the rest neutral (golden on every platform)', () => {
  const script = fixtureScript();
  eq(['MOLLY', 'FIBBER', 'DOC'].map(n => C.partHue(script, C.role(n))), ['mystery', 'scifi', 'western'], 'the fixture, largest first');
  eq([C.partHue(script, C.DIRECTIONS), C.partHue(script, C.SOUND)], ['', ''], 'directions and sound stand on neutral');
  const rodney = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog/plays/castable-scripts.json'), 'utf8'))
    .scripts.find(s => s.id === 'gut-28051');
  if (rodney) {
    eq(['URIAH', 'RODNEY', 'MCKEEN', 'FRANKLIN', 'PRUDENCE', 'RUTLEDGE', 'TOM', 'ANNOUNCER'].map(n => C.partHue(rodney, C.role(n))),
      ['mystery', 'scifi', 'western', 'serial', 'documentary', 'comedy', 'news', ''], 'Caesar Rodney\'s Ride: the eighth part is neutral');
  }
});

test('a run plan starts at the line\'s cue and stops after the part\'s last line', () => {
  const script = fixtureScript();
  let p = C.newProduction(script);
  p = C.addTake(p, take('f2', 'L0002', C.role('FIBBER'), 100));
  const plan = C.runPlan(p, script, C.role('MOLLY'), 'L0006');
  eq(plan.map(e => [e.lineID, e.source]), [['L0005', 'voice'], ['L0006', 'mine'], ['L0007', 'mine'], ['L0008', 'voice'],
    ['L0009', 'mine'], ['L0010', 'voice'], ['L0011', 'mine']], 'DOC\'s cue first, the unrecorded sound skipped, the part\'s lines its own');
  eq(C.runPlan(p, script, C.role('MOLLY'), 'L0003').slice(0, 2).map(e => [e.lineID, e.source]), [['L0002', 'take'], ['L0003', 'mine']],
    'a cue with a human take plays the take');
  eq(C.runPlan(p, script, C.role('FIBBER'), 'L0008').map(e => e.lineID).pop(), 'L0010', 'nothing plays after the part\'s last line');
  for (const e of plan.filter(x => x.source === 'voice')) eq(Object.keys(e).sort(), ['lineID', 'part', 'source', 'text'], `${e.lineID}: words only`);
  eq(C.runPlan(p, script, C.role('MOLLY'), 'nope'), [], 'an unknown line plans nothing');
});

test('discarding a run removes its takes and puts each line back on the take it had', () => {
  const script = fixtureScript();
  let p = C.newProduction(script);
  p = C.addTake(p, take('old', 'L0003', C.role('MOLLY'), 100));
  p = C.addTake(p, take('r1', 'L0003', C.role('MOLLY'), 100));
  p = C.addTake(p, take('r2', 'L0006', C.role('MOLLY'), 100));
  p = C.addTake(p, take('r3', 'L0006', C.role('MOLLY'), 100));
  const { production, gone } = C.discardRun(p, [{ lineID: 'L0003', prior: 'old', takes: ['r1'] }, { lineID: 'L0006', prior: null, takes: ['r2', 'r3'] }]);
  eq(gone.map(t => t.id).sort(), ['r1', 'r2', 'r3'], 'every take the run made goes');
  eq(production.takes.map(t => t.id), ['old'], 'the take from before the run stays');
  eq(production.chosen, { L0003: 'old' }, 'each line is back where it was');
});

/** A device voice that reads until it is cancelled, so a run can be paused mid-cue. */
function waitingVoice() {
  let release = null;
  const v = {
    spoken: [],
    speak(text) { v.spoken.push(text); return new Promise((r) => { release = r; v.waiting = true; }); },
    cancel() { v.waiting = false; if (release) { const r = release; release = null; r(false); } },
    finish() { v.waiting = false; if (release) { const r = release; release = null; r(true); } },
    waiting: false,
  };
  return v;
}
const tick = () => new Promise(r => setImmediate(r));

async function modeSession(voice, part = C.role('MOLLY')) {
  const script = fixtureScript();
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  let p = await store.create(script);
  p = C.take(p, script, part, '');
  await store.save(p);
  const phases = [];
  const s = RecordingSession.create({ production: p, script, part, store, audio: fakeAudio({ speaker: null }, false), voice,
                                      sleep: async () => {}, onChange: (x) => phases.push(x.phase.kind) });
  await s.begin();
  return { s, store, backend, script, phases };
}

test('Run through records every line of the part in one pass and opens its review; Discard the run deletes the files', async () => {
  const voice = signatureVoice({ speaker: null });
  const { s, store, backend, phases } = await modeSession(voice);
  ok(s.setMode('run'), 'the mode can be set while nothing plays');
  await s.runThrough('L0003');
  eq(s.phase.kind, 'runReview', 'the run ends on its review');
  eq(s.runTakes().map(t => t.lineID), ['L0003', 'L0006', 'L0007', 'L0009', 'L0011'], 'every line of the part has a take from the run');
  eq(voice.rendered.length, 4, 'the open parts between were read live (FIBBER twice, DOC, FIBBER), the cue before the first line too');
  ok(phases.includes('cue') && phases.includes('listening'), 'cues and listening alternate');
  ok(!s.setMode('step'), 'the mode holds while a run is under review');
  const files = (await backend.keys(`${s.production.id}/takes/`)).length;
  eq(files, 5, 'one take file per line');
  await s.discardRun();
  eq(s.phase.kind, 'idle', 'back to ready');
  eq((await backend.keys(`${s.production.id}/takes/`)).length, 0, 'the run\'s files are gone');
  eq(store.production(s.production.id).chosen, {}, 'no line keeps a run take');
  s.end();
});

test('Keep N takes keeps the run; Again in the review re-records one line and returns to the review', async () => {
  const { s, store } = await modeSession(signatureVoice({ speaker: null }));
  s.setMode('run');
  await s.runThrough('L0009');
  eq(s.runTakes().map(t => t.lineID), ['L0009', 'L0011'], 'a run from a later line records from there');
  const first = s.runTakes()[0].id;
  await s.record('L0009');
  eq(s.phase.kind, 'runReview', 'Again returns to the run\'s review');
  ok(s.runTakes()[0].id !== first, 'the review shows the new take');
  s.keepRun();
  const p = store.production(s.production.id);
  eq(Object.keys(p.chosen).sort(), ['L0009', 'L0011'], 'the run\'s lines keep their takes');
  eq(p.takes.length, 3, 'the superseded take stays until the person discards unused takes (§8 rule 5)');
  eq(s.run, null, 'the run is over');
  s.end();
});

test('Pause ends a run mid-cue and opens the review of what it took', async () => {
  const voice = waitingVoice();
  const { s } = await modeSession(voice);
  s.setMode('run');
  const running = s.runThrough('L0003');
  await tick();
  ok(voice.waiting && s.phase.kind === 'cue' && s.phase.run, 'FIBBER\'s cue is being read');
  ok(!s.setMode('lines'), 'the mode control is disabled while the run plays');
  voice.finish();
  for (let i = 0; i < 20 && !voice.waiting; i++) await tick();
  ok(voice.waiting, 'after the first line, the next open part is read');
  s.pause();
  await running;
  eq(s.phase.kind, 'runReview', 'Pause opens the review');
  eq(s.runTakes().map(t => t.lineID), ['L0003'], 'the review holds the one line taken');
  s.end();
});

test('Pause before any line is taken goes back to ready', async () => {
  const voice = waitingVoice();
  const { s } = await modeSession(voice);
  s.setMode('run');
  const running = s.runThrough('L0003');
  await tick();
  s.pause();
  await running;
  eq([s.phase.kind, s.run], ['idle', null], 'nothing to review');
  s.end();
});

test('Line by line ends on the line, ready; Step ends on the take\'s review', async () => {
  const { s } = await modeSession(signatureVoice({ speaker: null }));
  s.setMode('lines');
  await s.record('L0006');
  eq(s.phase.kind, 'idle', 'Line by line: the line is ready to record again');
  ok(s.production.chosen.L0006, 'the take is the line\'s');
  s.setMode('step');
  await s.record('L0007');
  eq([s.phase.kind, s.phase.lineID], ['review', 'L0007'], 'Step: the take waits for Keep or Again');
  ok(!s.setMode('bogus'), 'only the three modes');
  s.end();
});

test('Cue and With cue play and keep nothing', async () => {
  const voice = signatureVoice({ speaker: null });
  const { s, backend } = await modeSession(voice);
  s.setMode('lines');
  await s.playCue('L0006');
  eq(voice.rendered.length, 1, 'DOC\'s line was read');
  eq((await backend.keys(`${s.production.id}/takes/`)).length, 0, 'no take was written');
  await s.record('L0006');
  const before = (await backend.keys(`${s.production.id}/`)).length;
  await s.playWithCue(C.chosenTake(s.production, 'L0006'));
  eq((await backend.keys(`${s.production.id}/`)).length, before, 'With cue writes nothing');
  eq(s.phase.kind, 'idle', 'back where it was');
  s.end();
});

test('Cancel while a Step cue plays stops the cue and records nothing', async () => {
  const voice = waitingVoice();
  const { s, backend } = await modeSession(voice);
  s.setMode('step');
  const going = s.record('L0003');
  await tick();
  eq(s.phase.kind, 'cue', 'the cue is playing');
  s.cancel();
  await going;
  eq(s.phase.kind, 'idle', 'back to ready');
  eq((await backend.keys(`${s.production.id}/takes/`)).length, 0, 'nothing was recorded');
  const again = s.record('L0003');
  await tick();
  eq(s.phase.kind, 'cue', 'the next record plays its cue again (the cancel did not stick)');
  s.cancel();
  await again;
  s.end();
});

test('Cancel does nothing inside a run', async () => {
  const voice = waitingVoice();
  const { s } = await modeSession(voice);
  s.setMode('run');
  const running = s.runThrough('L0003');
  await tick();
  s.cancel();
  eq(voice.waiting, true, 'the run\'s cue is still playing');
  s.pause();
  await running;
  s.end();
});

test('The level meter follows the microphone while a line records', async () => {
  const { s } = await modeSession(signatureVoice({ speaker: null }));
  const seen = [];
  let loudest = 0;
  s.onLevel = (l) => { seen.push(l.length); loudest = Math.max(loudest, l[l.length - 1]); };
  await s.record('L0006');
  ok(seen.length > 5, 'a level for every chunk heard');
  ok(s.levels.length <= 48 && s.levels.every(v => v >= 0 && v <= 1), 'bounded, newest last, 0 to 1');
  ok(loudest > 0.5, 'the tone reads loud');
  s.end();
});

/* ---- Sound in the mix (B32 K2): catalog/tests/golden/mix_sound.json, shared with Swift and Kotlin ---- */

const SOUND_GOLDEN = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog/tests/golden/mix_sound.json'), 'utf8'));
function goldenSynth(spec, frames) {
  const out = new Float32Array(frames);
  for (let k = 0; k < frames; k++) {
    out[k] = spec.type === 'sine' ? spec.amp * Math.sin((2 * Math.PI * spec.hz * k) / SOUND_GOLDEN.sampleRate) : (k % spec.every === 0 ? spec.amp : 0);
  }
  return out;
}
function goldenProduction(sound) {
  const g = SOUND_GOLDEN;
  const p = { ...C.newProduction(g.script), takes: g.takes.map(t => ({ ...take(t.id, t.lineID, t.part, t.frames, t.loudness, t.peak) })), chosen: { ...g.chosen } };
  if (sound) p.sound = JSON.parse(JSON.stringify(sound));
  return p;
}
const goldenResolver = (have = () => true) => (src) => {
  const c = SOUND_GOLDEN.cues.find(x => x.pack === src.pack && x.cue === src.cue);
  return c && have(c) ? { key: `${c.pack}/${c.cue}`, frames: c.frames, kind: c.kind, loudness: c.loudness, peak: c.peak } : null;
};
const near = (a, b, tol = 1e-6) => Math.abs(a - b) <= tol;
function sameShape(t, want, name) {
  eq(t.totalFrames, want.totalFrames, `${name}: total frames`);
  eq(t.placements.map(x => [x.lineID, x.takeID, x.start, x.frames]), want.placements.map(x => [x.lineID, x.takeID, x.start, x.frames]), `${name}: voice placements`);
  ok(t.placements.every((x, i) => near(x.gain, want.placements[i].gain)), `${name}: voice gains`);
  eq('sounds' in t, 'sounds' in want, `${name}: sound lanes present only with sound`);
  if (!want.sounds) return;
  const fields = ['soundID', 'slotID', 'lane', 'start', 'frames', 'inFrame', 'outFrame', 'loop', 'fadeIn', 'fadeOut', 'duck'];
  eq(t.sounds.map(x => fields.map(f => x[f])), want.sounds.map(x => fields.map(f => x[f])), `${name}: sound placements`);
  ok(t.sounds.every((x, i) => near(x.gain, want.sounds[i].gain)), `${name}: sound gains`);
  eq(t.voice, want.voice, `${name}: voice activity, gaps under 1 s held`);
  eq(t.left, want.left, `${name}: sounds left out`);
}

test('sound cues place against the takes as the golden says (B32 §3.3)', () => {
  const g = SOUND_GOLDEN, e = g.expect;
  const voiceOnly = C.buildTimeline(g.script, goldenProduction(null));
  sameShape(voiceOnly, e.voiceOnly, 'voice only');
  eq(Object.keys(voiceOnly).sort(), ['placements', 'sampleRate', 'totalFrames'], 'a play with no sound has the timeline it always had');
  sameShape(C.buildTimeline(g.script, goldenProduction({ v: 1, slots: [g.sound.slots[2]] })), e.silentOnly, 'only a silent slot');
  sameShape(C.buildTimeline(g.script, goldenProduction(g.sound), { resolveSound: goldenResolver() }), e.full, 'full');
  throwsKind(() => C.buildTimeline(g.script, goldenProduction(g.sound), { resolveSound: goldenResolver(c => c.cue !== 'rain-steady-1') }),
    e.missing.kind, e.missing.detail, 'a sound not on this device is named, never dropped');
  sameShape(C.buildTimeline(g.script, goldenProduction(g.sound), { resolveSound: goldenResolver(c => c.cue !== 'rain-steady-1'), withoutMissing: true }),
    e.withoutMissing, 'export without them');
  throwsKind(() => C.buildTimeline(g.script, goldenProduction({ ...g.sound, v: 2 }), { resolveSound: goldenResolver() }), 'soundVersion', 2, 'a newer sound block is refused');
});

test('the duck is computed from the voice takes, as the golden says (B32 §4.2)', () => {
  const g = SOUND_GOLDEN, e = g.expect;
  for (const [depth, points] of Object.entries(e.envelopes)) eq(C.duckEnvelope(e.full.voice, Number(depth), g.sampleRate), points, `breakpoints at ${depth} dB`);
  eq(C.duckEnvelope(e.full.voice, 0, g.sampleRate), [], 'Off has no duck');
  let worst = 0;
  for (const [depth, frame, db] of e.duckAt) {
    const got = 20 * Math.log10(C.duckGains(C.duckEnvelope(e.full.voice, depth, g.sampleRate), frame, 1)[0]);
    worst = Math.max(worst, Math.abs(got - db));
  }
  ok(worst < 1e-6, `the envelope at each probe (worst ${worst} dB)`);
  const d = g.defaults;
  eq([d.effectsDuckDb, d.musicDuckDb, d.attackMs, d.releaseMs, d.holdMs], [-6, -12, 120, 600, 1000], 'the design defaults');
});

test('the mix with sound renders the golden samples to 1 LSB, held under -1 dBFS (B32 §4.3)', async () => {
  const g = SOUND_GOLDEN, e = g.expect;
  const t = C.buildTimeline(g.script, goldenProduction(g.sound), { resolveSound: goldenResolver() });
  const takes = new Map(g.takes.map(x => [x.id, goldenSynth(x.synth, x.frames)]));
  const cues = new Map(g.cues.map(x => [`${x.pack}/${x.cue}`, goldenSynth(x.synth, x.frames)]));
  const load = async (x) => (x.takeID ? takes.get(x.takeID) : x.src.take ? takes.get(x.src.take) : cues.get(`${x.src.pack}/${x.src.cue}`));
  for (const chunkSeconds of [1, 0.37]) {
    const mix = C.decodeWav(await (await C.renderMix(t, load, fakeOffline, { chunkSeconds })).arrayBuffer()).samples;
    eq(mix.length, e.full.totalFrames, `the mix is as long as its timeline (chunks of ${chunkSeconds} s)`);
    let worst = 0, at = -1;
    e.samples.forEach((want, i) => { const d = Math.abs(Math.round(mix[i * e.samplesEvery] * 32768) - want); if (d > worst) { worst = d; at = i * e.samplesEvery; } });
    for (const [f, want] of e.samplesAt) { const d = Math.abs(Math.round(mix[f] * 32768) - want); if (d > worst) { worst = d; at = f; } }
    ok(worst <= 1, `every golden sample within 1 LSB (chunks of ${chunkSeconds} s; worst ${worst} at ${at})`);
    let peak = 0;
    for (const v of mix) peak = Math.max(peak, Math.abs(v));
    ok(peak <= Math.pow(10, -1 / 20) + 1 / 32768, `the sample peak is held at -1 dBFS (${peak})`);
  }
  ok(near(C.mixScalar(e.peak), e.scalar), 'the one scalar');
  eq(C.mixScalar(0.5), 1, 'a quiet mix is not raised');
});

test('the sound block in the record: old records unchanged, performed cues kept (B32 §5.1)', () => {
  const g = SOUND_GOLDEN;
  const plain = goldenProduction(null);
  eq(C.fingerprint(plain), 'L0001=t1,L0002=t2,L0004=t4,L0005=t5', 'a record with no sound keeps its fingerprint, so its mix stays current');
  eq(C.fingerprint(goldenProduction({ v: 1, slots: [g.sound.slots[2]] })), C.fingerprint(plain), 'only silent slots change nothing');
  const withSound = goldenProduction(g.sound);
  ok(C.fingerprint(withSound) !== C.fingerprint(plain), 'placing a sound makes the mix stale');
  const moved = goldenProduction(g.sound);
  moved.sound.slots[1].sounds[2].startMs = -400;
  ok(C.fingerprint(moved) !== C.fingerprint(withSound), 'moving a sound makes the mix stale');
  eq(C.unusedTakes(withSound).map(t => t.id), [], 'a take a slot plays is not unused');
  eq(C.unusedTakes(plain).map(t => t.id), ['k-door'], 'without the slot it is');
  eq(C.deleteTake(withSound, 'k-door').gone, [], 'a take a slot plays is not deleted');
  eq(C.discardUnused(withSound).gone, [], 'nor discarded');
  ok(!C.hasSound(plain) && C.hasSound(withSound), 'hasSound');
});

test('the store mixes a performed cue from its own takes, and names a pack cue it cannot reach (B32)', async () => {
  const script = fixtureScript();
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  let p = await store.create(script);
  const samples = tone([440], 0.3);
  for (const l of script.lines) {
    if (l.kind !== 'speech') continue;
    const file = await store.writeTake({ samples, sampleRate: 48000 }, p, l.id);
    p = C.addTake(p, { ...take(`t-${l.id}`, l.id, C.linePart(l), samples.length), file });
  }
  const knock = tone([200], 0.2, 0.5);
  const kfile = await store.writeTake({ samples: knock, sampleRate: 48000 }, p, 'L0005');
  p = { ...p, takes: [...p.takes, { ...take('knock', 'L0005', C.SOUND, knock.length), file: kfile }] };
  p.sound = { v: 1, slots: [{ id: 'S1', line: 'L0005', piece: null, added: true, silent: false,
    sounds: [{ id: 'C1', src: { take: 'knock' }, at: 'before', startMs: 0, gainDb: 0, fadeInMs: 0, fadeOutMs: 0, loop: false, duckDb: null }] }] };
  await store.save(p);
  const blob = await store.renderMix(p.id, fakeOffline);
  const mix = C.decodeWav(await blob.arrayBuffer()).samples;
  const t = C.buildTimeline(script, p);
  eq(mix.length, t.totalFrames, 'the mix holds the cue');
  ok(rmsAround(mix, t.sounds[0].start + 4800) > 0.05, 'the knock sounds before the line');
  eq(store.production(p.id).mixedFrom, C.fingerprint(p), 'the record says which takes and sounds it was made from');
  const q = { ...store.production(p.id), sound: { v: 1, slots: [{ ...p.sound.slots[0], sounds: [{ ...p.sound.slots[0].sounds[0], id: 'C2', src: { pack: 'eardrama-sounds-1', cue: 'thunder-close' } }] }] } };
  await store.save(q);
  let kind = null, detail = null;
  try { await store.renderMix(q.id, fakeOffline); } catch (e) { kind = e.kind; detail = e.detail; }
  eq([kind, detail], ['missingSounds', ['C2']], 'a pack cue with no pack is named');
});

/* ---- A scene's range (B31 §3.4, PLAYS-DESIGN §2.12): catalog/tests/golden/production_range.json, shared with Swift and Kotlin ---- */

test('the store keeps a scene\'s production: the scene read back, a drifted range dropped once, older and newer records', async () => {
  const backend = PlayStore.memoryBackend();
  const store = PlayStore.open(backend);
  await store.load();
  const script = fixtureScript();
  const range = { from: 'L0006', to: 'L0009' };
  const p0 = await store.create(script, { range, heading: 'Scene II' });
  const p = C.addTake(p0, take('t-scene', 'L0006', 'role:MOLLY', 4800));
  await store.save(p);
  eq([(await store.script(p)).lines.length, (await store.wholeScript(p)).lines.length], [4, script.lines.length], 'the scene, and the whole kept');
  eq(store.takeDropped(p.id), false, 'nothing dropped');
  // A revision of the kept script that loses the scene's last line (rule 4).
  await backend.put(`${p.id}/script.json`, JSON.stringify({ ...script, revision: 'r2', lines: script.lines.filter(l => l.id !== 'L0009') }));
  const fresh = PlayStore.open(backend);
  await fresh.load();
  const back = await fresh.script(fresh.production(p.id));
  eq(back.lines.length, script.lines.length - 1, 'the whole play now');
  eq([('range' in fresh.production(p.id)), fresh.production(p.id).title, fresh.takeDropped(p.id), fresh.takeDropped(p.id)],
    [false, script.title, true, false], 'the range is dropped, the title is the play\'s, and it is said once');
  await backend.put('OLD/production.json', JSON.stringify({ ...C.newProduction(script, { id: 'OLD' }), format: undefined, takes: [take('t', 'L0002', 'role:FIBBER', 4800)], chosen: { L0002: 't' } }));
  await backend.put('NEW/production.json', JSON.stringify({ ...C.newProduction(script, { id: 'NEW' }), format: 3, takes: [take('t', 'L0002', 'role:FIBBER', 4800)] }));
  const third = PlayStore.open(backend);
  await third.load();
  eq([third.production('OLD') && third.production('OLD').format, third.production('NEW')], [2, null], 'an old record is read as format 2; a newer one is not listed');
  ok((await backend.get('NEW/production.json')) !== null, 'and the newer one is kept on disk');
});

const RANGE = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog/tests/golden/production_range.json'), 'utf8'));
const pairs = (cast) => cast.map(x => [x.id, x.lineCount]);
function rangeProduction(core, chosen, { sound = null } = {}) {
  const g = RANGE;
  const p = core.newProduction(g.script, { range: g.range, heading: g.heading });
  p.takes = g.takes.map(t => ({ ...take(t.id, t.lineID, t.part, t.frames, t.loudness, t.peak), ...(t.cue ? { cue: t.cue } : {}) }));
  p.chosen = { ...chosen };
  if (sound) p.sound = JSON.parse(JSON.stringify(sound));
  return p;
}
/** The golden's answers for one core; `core` is PlaysCore or a mutant of it. Returns what failed. */
function rangeAnswers(core) {
  const g = RANGE, e = g.expect, bad = [];
  const want = (got, exp, name) => { if (JSON.stringify(got) !== JSON.stringify(exp)) bad.push(`${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(exp)}`); };
  const p0 = core.newProduction(g.script, { range: g.range, heading: g.heading });
  want(p0.title, e.title, 'title');
  want(p0.format, e.format, 'format');
  want(p0.range, g.range, 'range stored');
  want(Object.keys(p0.parts).sort(), e.parts.slice().sort(), 'parts of the range only');
  const s = core.scoped(p0, g.script);
  want(s.lines.map(l => l.id), e.lineIDs, 'line ids');
  want(pairs(core.castParts(g.script, g.range)), e.cast, 'castParts(script, range)');
  want(pairs(core.castParts(s)), e.cast, 'cast of the scoped script');
  want(pairs(core.castParts(g.script)), e.wholeCast, 'whole cast unchanged');
  want([core.voicesOf(s), core.minutesOf(s)], [e.voices, e.minutes], 'voices and minutes are the range\'s');
  want(core.listenPlan(p0, g.script).map(x => x.lineID), e.listenBeforeAnyTake, 'listen before any take');
  for (const k of ['before', 'after']) {
    const d = g.done[k];
    const p = rangeProduction(core, d.chosen);
    want(core.isComplete(p, g.script), d.complete, `${k}: Done`);
    want(core.missingSpeech(p, g.script), d.missing, `${k}: missing`);
    for (const part of Object.keys(d.partMissing)) want(core.missingLines(p, g.script, part), d.partMissing[part], `${k}: ${part} missing`);
    if (d.wholeMissing) want(core.missingSpeech({ ...p, range: undefined }, g.script), d.wholeMissing, `${k}: the whole play is not done`);
  }
  const done = rangeProduction(core, g.done.after.chosen, { sound: g.sound });
  want(core.listenPlan(done, g.script).map(x => [x.lineID, x.source]), g.listenAfter, 'listen through after');
  try {
    const t = core.buildTimeline(g.script, done);
    want(t.placements.map(x => x.lineID), g.export.voice, 'export voice lines');
    want((t.sounds || []).map(x => x.soundID), g.export.sounds, 'export sounds');
    want((t.sounds || []).map(x => x.lineID), g.export.soundLines, 'export sound lines');
  } catch (err) { bad.push(`export threw ${err.kind || err.message}`); }
  let rec = core.take(rangeProduction(core, g.done.after.chosen), g.script, 'role:DEMEA', '');
  try { rec = core.finish(rec, g.script, 'role:DEMEA'); want(rec.parts['role:DEMEA'].status, 'done', 'finish in range'); } catch (err) { bad.push(`finish threw ${err.kind}`); }
  try { core.take(p0, g.script, 'role:SYRUS', ''); bad.push('a part outside the range was taken'); } catch (err) { want(err.kind, 'notOpen', 'a part outside the range'); }
  for (const c of g.drift) {
    const script = { ...g.script, revision: 'r2', lines: g.script.lines.filter(l => !(c.remove || []).includes(l.id)) };
    want(core.rangeDrifted({ ...p0, range: c.range || g.range }, script), c.drifted, c.name);
  }
  const dropped = core.dropRange({ ...p0, listenedThrough: true, mixedFrom: 'x' }, g.script);
  want([dropped.title, dropped.range || null, dropped.listenedThrough, Object.keys(dropped.parts).sort()],
    [g.dropped.title, g.dropped.range, g.dropped.listenedThrough, g.dropped.parts], 'dropped range');
  const old = g.old.record;
  const migrated = core.migrateProduction(JSON.parse(JSON.stringify(old)));
  want([core.fingerprint(old), core.fingerprint(migrated), migrated.format, core.isFinished(migrated)], [g.old.fingerprint, g.old.fingerprint, 2, true], 'old record migrated, fingerprint unchanged');
  want(pairs(core.castParts(core.scoped(migrated, g.script))), g.old.cast, 'an old production is the whole play');
  want(core.listenPlan(migrated, g.script).length, g.script.lines.filter(l => l.kind === 'speech').length, 'an old production listens through the whole play');
  want(core.productionTooNew({ ...old, ...g.tooNew }), true, 'a newer format is refused');
  want(core.productionTooNew(migrated), false, 'control: the current format is read');
  return bad;
}

test('a scene\'s range: the golden every platform runs (production_range.json)', () => {
  const bad = rangeAnswers(C);
  bad.forEach(b => ok(false, b));
  ok(!bad.length, 'every answer of the golden');
});

test('a scene\'s range: each mutant of the core breaks the golden', () => {
  const mutants = {
    'scoped ignores the range': { scoped: (p, s) => s, castParts: (s) => C.castParts(s) },
    'the mix keeps cues outside the range': { buildTimeline: (s, p, o) => C.buildTimeline({ ...C.scoped(p, s), range: undefined }, { ...p, range: undefined }, o) },
    'Done reads the whole play': { isComplete: (p, s) => C.isComplete({ ...p, range: undefined }, s) },
    'a range is not dropped on drift': { rangeDrifted: () => false },
    'migration rewrites the takes': { migrateProduction: (p) => ({ ...p, format: 2, chosen: {} }) },
    'title without the heading': { newProduction: (s, o) => ({ ...C.newProduction(s, o), title: s.title }) },
  };
  for (const [name, patch] of Object.entries(mutants)) {
    ok(rangeAnswers({ ...C, ...patch }).length > 0, `mutant caught: ${name}`);
  }
});

(async () => {
  for (const [name, fn] of results) {
    const before = failures;
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: threw ${e && e.stack}`); }
    if (failures === before) console.log(`  ok  ${name}`);
  }
  console.log(`${failures ? 'FAIL' : 'ok'}: ${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
