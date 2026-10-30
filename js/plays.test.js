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
for (const f of ['plays-core.js', 'plays-store.js', 'plays-voice.js', 'plays-session.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
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
    [['MOLLY', 5], ['FIBBER', 3], ['DOC', 1], ['Sound effects', 1], ['Stage directions', 1]], 'titles and counts');
  eq(C.displayName('Carlton, Henry Fisk'), 'Henry Fisk Carlton', 'a filed name reads in order');
  eq(C.displayName('Baker, 1832-1890'), 'Baker, 1832-1890', 'control: a date is not a first name');
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
  eq(Object.keys(record).sort(), ['chosen', 'created', 'id', 'listenedThrough', 'parts', 'roomTone', 'scriptID',
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
  if (/\bencodeWav\s*\(/.test(source) && !['plays-core.js', 'plays-store.js'].includes(file)) out.push(`${file}: encodes audio`);
  if (/\b(speechSynthesis|SpeechSynthesisUtterance)\b/.test(source) && file !== 'plays-voice.js') out.push(`${file}: speaks`);
  if (file.startsWith('plays-') && file !== 'plays-store.js'
      && /\bindexedDB\b|createWritable|getDirectory\s*\(|\.download\s*=/.test(source)) out.push(`${file}: persists`);
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

(async () => {
  for (const [name, fn] of results) {
    const before = failures;
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: threw ${e && e.stack}`); }
    if (failures === before) console.log(`  ok  ${name}`);
  }
  console.log(`${failures ? 'FAIL' : 'ok'}: ${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
