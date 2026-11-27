/**
 * The Sound part and the board on the web (B32 §2-§5; WEB-DESIGN §4.16 item 14a), run against the SHIPPED
 * js/plays-core.js, js/plays-store.js, js/plays-session.js, js/sound-core.js and js/sound-store.js: Sound on
 * every cast sheet, the slots and the edits a board makes, a performed cue kept as a take that is never a line's
 * chosen one, the pack manifest's rights gate (planted rows that must be refused), the pack as a source that may
 * be absent, own sounds on this device only (never reaching a share, an upload or a published record, and
 * carried whole by Export my data), the mix refusing a missing sound by name, and the live listen's cues.
 * Nothing is heard: the audio, the cache and the network are fakes.   node js/sound.test.js
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');

const JS = process.env.PLAYS_JS_DIR || __dirname;
const ROOT = path.resolve(__dirname, '..');
for (const f of ['plays-core.js', 'plays-store.js', 'voice-cast.js', 'plays-voice.js', 'plays-session.js', 'reader-core.js', 'sound-core.js', 'sound-store.js', 'export.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(JS, f), 'utf8'), { filename: f });
}
const C = vm.runInThisContext('PlaysCore');
const S = vm.runInThisContext('SoundCore');
const SoundStore = vm.runInThisContext('SoundStore');
const PlayStore = vm.runInThisContext('PlayStore');
const RecordingSession = vm.runInThisContext('RecordingSession');
const ListenThrough = vm.runInThisContext('ListenThrough');
const ReaderCore = vm.runInThisContext('ReaderCore');
const DataExport = vm.runInThisContext('DataExport');

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const pass = JSON.stringify(a) === JSON.stringify(b);
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
const test = (name, fn) => results.push([name, fn]);

/* ---- Fixtures ---- */

const say = (id, role, ...parts) => ({ id, kind: 'speech', role, parts: parts.map(p => (typeof p === 'string' ? { say: p } : p)) });
/** Caesar Rodney's shape: cues inside speeches, no sound line; one direction. */
function radioScript() {
  return {
    id: 'fixture-radio', revision: 1, title: 'A ride in the rain', roles: [{ name: 'URIAH' }, { name: 'RODNEY' }],
    lines: [
      say('L0001', 'URIAH', 'We got to make it, rain or no rain.'),
      say('L0002', 'RODNEY', "It's sprinkling."),
      say('L0003', 'URIAH', 'I felt it.', { sound: 'another peal of thunder closer' }),
      say('L0004', 'RODNEY', { direction: 'Sound of rain and wind' }, 'I guess it is on us.'),
      say('L0005', 'URIAH', 'Here, draw up your horse!', { direction: 'absently' }, 'Whoa, boy!'),
      { id: 'L0006', kind: 'direction', source: 'They ride off.' },
      say('L0007', 'RODNEY', 'Giddap!'),
    ],
  };
}
/** No cue rows at all, and no directions. */
function quietScript() {
  return { id: 'fixture-quiet', revision: 1, title: 'Quiet', roles: [{ name: 'A' }, { name: 'B' }],
    lines: [say('L0001', 'A', 'Hello.'), say('L0002', 'B', 'Hello yourself.')] };
}

const TAKE = (id, lineID, seconds = 1, extra = {}) => ({ id, lineID, part: 'x', file: `${id}.wav`, created: 1, frames: Math.round(seconds * 48000), sampleRate: 48000, capture: 'direct', heard: {}, peak: 0.5, bleed: false, ...extra });

function fakeOffline(channels, length, rate) {
  const sources = [];
  return {
    destination: {},
    createBuffer(c, n) { const d = new Float32Array(n); return { length: n, getChannelData: () => d }; },
    createGain() { return { gain: { value: 1 }, connect() {} }; },
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

const FIXTURE_DIR = path.join(ROOT, 'tools', 'fixtures', 'sounds');
const FIXTURE = JSON.parse(fs.readFileSync(path.join(FIXTURE_DIR, 'sounds.json'), 'utf8'));
const MANIFEST_URL = 'https://pack.test/eardrama-sounds-fixture/sounds.json';

/** API.sounds and the browser's cache, digest and decoder, as fakes over the fixture on disk. */
function fakeDevices({ manifest = FIXTURE, url = MANIFEST_URL, fail = false, corrupt = new Set() } = {}) {
  const cache = new Map();
  const fetched = [];
  const api = {
    manifestURL: () => url,
    async manifest() { if (fail) throw new Error('unreachable'); return JSON.parse(JSON.stringify(manifest)); },
    async file(base, p) {
      fetched.push(p);
      const bytes = fs.readFileSync(path.join(FIXTURE_DIR, p));
      const out = corrupt.has(p) ? Buffer.concat([bytes, Buffer.from([1])]) : bytes;
      return { url: new URL(p, base).href, bytes: out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength) };
    },
  };
  const devices = {
    cache: async () => ({
      keys: async () => [...cache.keys()].map(url => ({ url })),
      put: async (k, resp) => { cache.set(k, resp._bytes); },
      match: async (k) => (cache.has(k) ? { arrayBuffer: async () => cache.get(k) } : null),
      delete: async (k) => cache.delete(k),
    }),
    digest: async (bytes) => crypto.createHash('sha256').update(Buffer.from(bytes)).digest('hex'),
    decode: async (bytes) => { const d = C.decodeWav(bytes); return { samples: d.samples, sampleRate: 48000 }; },
    online: () => true,
  };
  return { api, devices, cache, fetched };
}
// The refused rows are logged; the test reads them from readManifest instead.
console.warn = () => {};
// The store wraps bytes in a Response; the fake cache keeps the bytes.
global.Response = class { constructor(bytes) { this._bytes = bytes; } };

/* ---- Parts ---- */

test('every script has a Sound part, counted by its cue rows, then Stage directions (B32 §3.1 item 1)', () => {
  eq(C.castParts(radioScript()).map(p => [p.id, p.lineCount, p.title]),
    [['role:URIAH', 3, 'URIAH'], ['role:RODNEY', 3, 'RODNEY'], ['sound', 2, 'Sound'], ['directions', 1, 'Stage directions']], 'a radio play with cues inside speeches');
  eq(C.castParts(quietScript()).map(p => [p.id, p.lineCount]), [['role:A', 1], ['role:B', 1], ['sound', 0]], 'a play with no cue rows still has Sound');
  eq(C.cueRows(radioScript()).map(r => [r.line, r.piece]), [['L0003', 1], ['L0004', 0]], 'the reader\'s cue rows: a sound piece and an aside beginning "sound of"');
  ok(ReaderCore && C.CUE_WORDS.test('Music, soft') && !C.CUE_WORDS.test('absently'), 'one rule for the reader and the slots');
  eq(Object.keys(C.newProduction(quietScript()).parts), ['role:A', 'role:B', 'sound'], 'a new production holds the Sound part');
  eq(S.partLine(quietScript(), C.newProduction(quietScript()), false), 'Add sounds', 'no cue rows: Add sounds');
  eq(S.partLine(radioScript(), C.newProduction(radioScript()), false), '2 cues · none chosen', 'cues, none chosen');
});

test('stage directions read by a person never block: "N of M recorded · the rest silent" (B32 §2 item 3)', () => {
  const s = radioScript();
  let p = C.take(C.newProduction(s), s, C.DIRECTIONS, '');
  eq(S.directionsLine(s, p), '0 of 1 recorded · the rest silent', 'none recorded');
  p = C.addTake(p, TAKE('d1', 'L0006'));
  eq(S.directionsLine(s, p), '1 of 1 recorded', 'all recorded');
  eq(C.missingSpeech(p, s).length, 6, 'only speaking lines decide completeness: the six speeches, never the direction');
  ok(C.finish(p, s, C.DIRECTIONS).parts.directions.status === 'done', 'Done with directions at any count');
});

/* ---- Slots and the board's edits ---- */

test('slots are the cue rows plus added lines, in script order; a slot is never filled for the person', () => {
  const s = radioScript();
  let p = C.newProduction(s);
  eq(S.slotsOf(s, p).map(x => [x.line, x.piece, x.added, x.sounds.length]), [['L0003', 1, false, 0], ['L0004', 0, false, 0]], 'two empty slots');
  ok(!p.sound, 'opening the board writes nothing');
  const r = S.addSlot(p, 'L0001');
  p = r.production;
  eq(S.slotsOf(s, p).map(x => x.line), ['L0001', 'L0003', 'L0004'], 'Add a sound here on line 1 sorts first');
  eq(S.addSlot(p, 'L0001').id, r.id, 'adding again finds the same slot');
  eq(S.prune(p).sound, undefined, 'an added slot left empty is removed');
  eq(S.prune(p, r.id).sound.slots.length, 1, 'but not while it is the current slot');
});

test('a sound added to a slot takes the placement the cue implies (§3.3)', () => {
  const s = radioScript();
  let p = C.addTake(C.newProduction(s), TAKE('t3', 'L0003', 2));
  const slot3 = S.slotsOf(s, p)[0];
  let e = S.ensure(p, slot3); p = e.production;
  let a = S.addSound(p, s, e.id, { pack: 'x', cue: 'thunder-close' }, { kind: 'effect', take: C.usableTake(p, 'L0003') });
  p = a.production;
  let x = p.sound.slots[0].sounds[0];
  eq([x.at, x.startMs, x.gainDb, x.duckDb], ['after', 0, 0, null], 'a cue printed after every said word: After');
  const slot4 = S.slotsOf(s, p)[1];
  e = S.ensure(p, slot4); p = e.production;
  p = S.addSound(p, s, e.id, { pack: 'x', cue: 'rain-steady' }, { kind: 'ambience' }).production;
  x = p.sound.slots[1].sounds[0];
  eq([x.at, x.until, x.fadeInMs, x.fadeOutMs, x.loop], ['bed', 'L0004', 1500, 2000, true], 'a loop at a cue before the words: a Bed with its fades');
  const mid = { id: 'm', kind: 'speech', role: 'U', parts: [{ say: 'one two three' }, { sound: 'bang' }, { say: 'four' }] };
  eq(S.defaultPlacement({ lines: [mid] }, { line: 'm', piece: 1 }), { at: 'under', share: 0.75 }, 'inside the words: Under at the share said before it');
  ok(p.listenedThrough === false, 'a change unfinishes the play');
});

test('the board\'s settings are held to what it offers', () => {
  const s = radioScript();
  let p = C.newProduction(s);
  const e = S.ensure(p, S.slotsOf(s, p)[0]); p = e.production;
  const a = S.addSound(p, s, e.id, { own: 'o1', name: 'Knock' }); p = a.production;
  p = S.updateSound(p, e.id, a.id, { startMs: -5000, gainDb: 40, fadeInMs: 300, duckDb: 0 });
  let x = p.sound.slots[0].sounds[0];
  eq([x.startMs, x.gainDb, x.fadeInMs, x.duckDb], [-2000, 6, 200, 0], 'Start to -2 s, level to +6 dB, a fade to its step, Off kept');
  p = S.updateSound(p, e.id, a.id, { at: 'bed' });
  x = p.sound.slots[0].sounds[0];
  eq([x.at, x.until, x.loop], ['bed', 'L0003', true], 'Bed takes an Until');
  p = S.updateSound(p, e.id, a.id, { until: 'L0007' });
  eq(p.sound.slots[0].sounds[0].until, 'L0007', 'Until is a line the person picked');
  p = S.updateSound(p, e.id, a.id, { at: 'before' });
  x = p.sound.slots[0].sounds[0];
  eq([x.at, 'until' in x, x.loop, x.fadeInMs], ['before', false, false, 0], 'leaving Bed drops its Until and fades');
  p = S.setSilent(p, e.id, true);
  ok(!p.sound.slots[0].silent, 'a slot holding a sound is never silent');
  p = S.removeSound(p, e.id, a.id);
  p = S.setSilent(p, e.id, true);
  ok(p.sound.slots[0].silent, 'Leave silent on an empty slot');
  eq(S.summary(s, p).silent, 1, 'counted as left silent');
  ok(!C.hasSound(p), 'a silent slot places nothing in the mix');
});

/* ---- A performed cue is a take like any line (round 3) ---- */

test('a performed cue is a take on its slot, never a line\'s chosen take, and the mix places it', async () => {
  const s = radioScript();
  const store = PlayStore.open(PlayStore.memoryBackend());
  await store.load();
  let p = await store.create(s);
  const f3 = await store.writeTake({ samples: new Float32Array(4800), sampleRate: 48000 }, p, 'L0003');
  p = C.addTake(p, TAKE('t3', 'L0003', 0.1, { file: f3 }));
  await store.save(p);
  const e = S.ensure(store.production(p.id), S.slotsOf(s, p)[0]);
  await store.save(e.production);
  const audio = {
    sampleRate: 48000, capture: 'direct', async start() {}, stop() {}, async playTake() {}, stopPlayback() {}, startMeter() {}, stopMeter() { return 0; },
    async toTakeRate(c) { return c; },
    beginCapture(onChunk) {
      this.n = (this.n || 0) + 1;
      this.cap = this.n === 1 ? new Float32Array(48000).map(() => (Math.random() - 0.5) * 0.001)
        : Float32Array.from({ length: 70000 }, (_, i) => (i > 9600 && i < 19000 ? Math.sin(i / 7) * 0.5 : 0));
      for (let k = 0; k < this.cap.length; k += 960) onChunk(this.cap.subarray(k, k + 960));
    },
    endCapture() { return { samples: this.cap, sampleRate: 48000 }; },
  };
  const voice = { async speak() { return true; }, cancel() {}, reads: () => false };
  const session = RecordingSession.create({ production: store.production(p.id), script: s, part: C.SOUND, store, audio, voice, sleep: async () => {} });
  await session.begin();
  const t = await session.recordCue('L0003', (prod, take) => S.addPerformed(prod, s, e.id, take));
  ok(!!t, 'the take was kept');
  const now = store.production(p.id);
  eq(now.chosen.L0003, 't3', 'the actor\'s chosen take is unchanged');
  eq(C.takesFor(now, 'L0003').map(x => x.id), ['t3'], 'the line\'s take list does not show the performed cue');
  const kept = now.takes.find(x => x.id === t.id);
  eq([kept.part, kept.cue], ['sound', e.id], 'the take is the Sound part\'s, on its slot');
  eq(now.sound.slots[0].sounds[0].src, { take: t.id }, 'the slot plays it');
  ok(C.deleteTake(now, t.id).gone.length === 0, 'a performed cue in use is never deleted');
  // Every speaking line taken: the mix places the performed cue.
  let q = now;
  for (const l of s.lines.filter(x => x.kind === 'speech' && x.id !== 'L0003')) q = C.addTake(q, TAKE(`t-${l.id}`, l.id, 0.5));
  const tl = C.buildTimeline(s, q);
  eq(tl.sounds.map(x => [x.src.take, x.at]), [[t.id, 'after']], 'the timeline places the performed cue');
});

/* ---- The pack: a source that may be absent, and its rights gate ---- */

test('the manifest reader keeps only rows with a license in the gate, evidence and a checked date (B32 §5.2)', () => {
  const m = S.readManifest(FIXTURE);
  eq(m.cues.map(c => c.id), ['thunder-close', 'thunder-distant', 'rain-steady', 'knock-wood', 'door-creak', 'calm-prelude'], 'the fixture\'s six cues');
  eq(m.refused.map(r => [r.id, r.why]), [['planted-cc-by', 'license CC-BY-4.0'], ['planted-no-evidence', 'no evidence'], ['planted-refused-host', 'refused host freesound.org']],
    'the planted CC-BY, no-evidence and refused-host rows are refused');
  const noDate = JSON.parse(JSON.stringify(FIXTURE));
  delete noDate.cues[0].license.checked;
  eq(S.readManifest(noDate).refused.map(r => r.why), ['no checked date', 'license CC-BY-4.0', 'no evidence', 'refused host freesound.org'], 'a row with no checked date is refused');
  let threw = false;
  try { S.readManifest({ ...FIXTURE, format: 2 }); } catch { threw = true; }
  ok(threw, 'a format this client does not read is refused, never guessed');
  eq(S.cueLine(m.cues[0]), '0:01 · Fixture · CC0', 'the row says length, source and license');
  eq(S.seedQuery('ANOTHER PEAL OF THUNDER CLOSER', m.cues), 'thunder', 'the search opens on the cue\'s first word that is a tag');
  eq(S.seedQuery('Knocks at the door', m.cues), 'knock', 'a plural finds its tag');
  eq(S.seedQuery('All bow low', m.cues), '', 'no tag: empty, never a guess');
  eq(S.search(m.cues, 'thunder').map(c => c.id), ['thunder-close', 'thunder-distant'], 'search by title and tag');
  eq(S.search(m.cues, 'storm', 'weather').length, 3, 'within one category');
});

test('no pack configured: the library is absent and nothing is fetched; configured but unreachable: an error to say so', async () => {
  const none = fakeDevices({ url: null });
  const st = SoundStore.create({ backend: PlayStore.memoryBackend(), api: none.api, devices: none.devices });
  eq((await st.loadPack()).status, 'none', 'no manifest URL: none');
  eq(none.fetched.length, 0, 'nothing fetched');
  const down = fakeDevices({ fail: true });
  const st2 = SoundStore.create({ backend: PlayStore.memoryBackend(), api: down.api, devices: down.devices });
  const errors = console.error; console.error = () => {};
  eq((await st2.loadPack()).status, 'error', 'unreachable: error');
  console.error = errors;
});

test('a category downloads on the press, each file checked against its sha256; a bad file twice fails the category', async () => {
  const dev = fakeDevices();
  const st = SoundStore.create({ backend: PlayStore.memoryBackend(), api: dev.api, devices: dev.devices });
  await st.loadPack();
  eq(st.categoryState('weather').state, 'missing', 'not here before the press');
  ok(await st.download('weather'), 'downloaded');
  eq(st.categoryState('weather').state, 'here', 'here after');
  eq(dev.fetched.sort(), ['weather/rain-steady.wav', 'weather/thunder-close.wav', 'weather/thunder-distant.wav'], 'only that category\'s files');
  const samples = await st.cueSamples(st.cue('thunder-close'));
  ok(samples.length > 0, 'a cached file decodes');
  const bad = fakeDevices({ corrupt: new Set(['doors/knock-wood.wav']) });
  const st2 = SoundStore.create({ backend: PlayStore.memoryBackend(), api: bad.api, devices: bad.devices });
  await st2.loadPack();
  const [w, e] = [console.warn, console.error]; console.warn = console.error = () => {};
  ok(!(await st2.download('doors')), 'a file whose checksum fails twice fails the download');
  console.warn = w; console.error = e;
  eq(st2.categoryState('doors').state, 'failed', 'the category says it failed');
  eq(bad.fetched.filter(f => f === 'doors/knock-wood.wav').length, 2, 'downloaded again once, then the error');
});

/* ---- Own sounds: this device only ---- */

test('own sounds are kept under sounds/mine/ on this device, listed, removed, and exported whole', async () => {
  const backend = PlayStore.memoryBackend();
  const dev = fakeDevices({ url: null });
  const st = SoundStore.create({ backend, api: dev.api, devices: dev.devices });
  eq(await st.mine(), [], 'none yet');
  const samples = Float32Array.from({ length: 4800 }, (_, i) => Math.sin(i / 5) * 0.3);
  const row = await st.saveOwn({ name: 'Owl at night', samples, sampleRate: 48000, from: 'recorded' });
  eq((await backend.keys('sounds/mine/')).length, 2, 'a WAV and a row');
  ok(!(await backend.keys()).some(k => /production\.json$/.test(k)), 'never a production');
  eq((await st.mine()).map(r => r.name), ['Owl at night'], 'listed');
  const back = await st.ownSamples(row.id);
  ok(Math.abs(back[100] - samples[100]) < 1e-3, 'read back as kept (16-bit)');
  const rows = await st.exportRows();
  eq([rows[0].name, rows[0].from, rows[0].seconds], ['Owl at night', 'recorded', 0.1], 'Export my data names it');
  const wav = Buffer.from(rows[0].wav, 'base64');
  eq(wav.subarray(0, 4).toString(), 'RIFF', 'and carries the sound itself');
  const data = DataExport.build({ history: () => [], follows: () => [], queue: () => [], position: () => null }, [], 0, [], [], rows);
  eq(data.ownSounds.map(r => r.id), [row.id], 'the export file has ownSounds[]');
  await st.removeOwn(row.id);
  eq((await backend.keys('sounds/mine/')).length, 0, 'deleting removes both');
});

test('own sounds never reach a share, an upload, a sync or a published record (B32 §3.4)', () => {
  const s = radioScript();
  let p = C.newProduction(s);
  const e = S.ensure(p, S.slotsOf(s, p)[0]); p = e.production;
  p = S.addSound(p, s, e.id, { own: 'o1', name: 'Owl' }).production;
  p = S.addSound(p, s, e.id, { pack: 'eardrama-sounds-1', cue: 'thunder-close' }).production;
  const pub = S.withoutOwn(p.sound);
  eq(pub.slots[0].sounds.map(x => x.src), [{ pack: 'eardrama-sounds-1', cue: 'thunder-close' }], 'the publishable block leaves own sounds out');
  eq(S.sources(p).own, ['o1'], 'and the warning knows there is one');
  for (const f of ['plays-share.js', 'sync.js', 'api.js', 'plays-store.js']) {
    const src = fs.readFileSync(path.join(JS, f), 'utf8');
    ok(!/sounds\/mine|SoundStore|ownSamples|exportRows\(\)/.test(src), `${f} never reads own sounds`);
  }
  const ui = fs.readFileSync(path.join(JS, 'plays-ui.js'), 'utf8');
  ok(/Your own sounds stay on this device\. The published play leaves them out\./.test(ui), 'Publish says so before the consent');
  const sh = fs.readFileSync(path.join(JS, 'plays-share.js'), 'utf8');
  ok(!/\.sound\b/.test(sh.replace(/C\.SOUND/g, '')), 'the share client sends no sound block (Decision 091: batch P)');
});

/* ---- The mix with sound ---- */

async function completeWithSounds() {
  const s = radioScript();
  const store = PlayStore.open(PlayStore.memoryBackend());
  await store.load();
  let p = await store.create(s);
  for (const l of s.lines.filter(x => x.kind === 'speech')) {
    const file = await store.writeTake({ samples: new Float32Array(24000).fill(0.1), sampleRate: 48000 }, p, l.id);
    p = C.addTake(p, { ...TAKE(`t-${l.id}`, l.id, 0.5), file });
  }
  const e = S.ensure(p, S.slotsOf(s, p)[0]); p = e.production;
  p = S.addSound(p, s, e.id, { own: 'gone-own', name: 'Owl at night' }).production;
  p = S.addSound(p, s, e.id, { pack: 'eardrama-sounds-fixture', cue: 'knock-wood' }).production;
  await store.save(p);
  return { s, store, p };
}

test('a sound this device lacks refuses the mix by name; Export without them leaves it out and the mix stays stale', async () => {
  const { store, p } = await completeWithSounds();
  const dev = fakeDevices();
  const sounds = SoundStore.create({ backend: store.backend, api: dev.api, devices: dev.devices });
  const got = await sounds.prepare(p);
  eq(got.missing.map(m => [m.title, m.own]), [['Owl at night', true]], 'the own sound from another device is named by the name it was given; the pack cue was downloaded');
  let kind = null;
  try { await store.renderMix(p.id, fakeOffline, { resolveSound: got.resolveSound, loadSound: got.loadSound }); } catch (e) { kind = e.kind; }
  eq(kind, 'missingSounds', 'refused, never dropped silently');
  const blob = await store.renderMix(p.id, fakeOffline, { resolveSound: got.resolveSound, loadSound: got.loadSound, withoutMissing: true });
  ok(blob.size > 44, 'without them, the mix renders');
  ok(!store.production(p.id).mixedFrom, 'a mix without them is never recorded as current');
});

/* ---- The live listen's cues ---- */

test('the live listen plays a slot\'s sounds at its line: Before waits, After follows, a bed stops at its Until, voices duck them', async () => {
  const s = radioScript();
  let p = C.newProduction(s);
  for (const l of s.lines.filter(x => x.kind === 'speech')) p = C.addTake(p, TAKE(`t-${l.id}`, l.id, 0.5));
  const e3 = S.ensure(p, S.slotsOf(s, p)[0]); p = e3.production;
  p = S.addSound(p, s, e3.id, { pack: 'x', cue: 'thunder' }).production;
  const e4 = S.ensure(p, S.slotsOf(s, p)[1]); p = e4.production;
  const bed = S.addSound(p, s, e4.id, { pack: 'x', cue: 'rain' }, { kind: 'ambience' }); p = bed.production;
  p = S.updateSound(p, e4.id, bed.id, { until: 'L0005' });
  const log = [];
  const store = { readTake: async () => C.encodeWav(new Float32Array(10), 48000, 16).buffer };
  const audio = { async startPlayback() {}, async playTake() { log.push('take'); }, stopPlayback() {}, stop() {} };
  const voice = { async speak(t) { log.push(`voice ${t}`); }, cancel() {} };
  const lt = ListenThrough.create({
    production: p, script: s, store, audio, voice,
    cues: (plan) => {
      const sched = S.listenCues(s, p, plan);
      return {
        at: (i) => sched[i],
        async start({ sound }) {
          log.push(`start ${sound.src.cue}`);
          let end;
          const h = { soundID: sound.id, bed: !!sound.loop, done: new Promise(r => { end = r; }), stop() { log.push(`stop ${sound.src.cue}`); end(); }, duck(on) { log.push(`duck ${on ? 'on' : 'off'} ${sound.src.cue}`); } };
          if (!sound.loop) setTimeout(end, 0);
          return h;
        },
        stopAll() {},
      };
    },
  });
  await lt.play();
  const at = (x) => log.indexOf(x);
  ok(at('start thunder') > 0 && log[at('start thunder') - 1] === 'take', 'the After thunder starts once line 3 has played');
  ok(at('start rain') >= 0 && log[at('start rain') + 1] === 'duck on rain', 'the bed starts with line 4 and ducks under it');
  ok(at('stop rain') > at('start rain') && log.slice(at('stop rain') - 3, at('stop rain')).includes('take'), 'and stops after line 5, its Until');
  eq(log.filter(x => x === 'take').length, 6, 'every take played');
  const r = S.inPlace(s, lt.plan, 'L0003');
  eq([lt.plan[r.from].lineID, lt.plan[r.to].lineID], ['L0002', 'L0004'], 'Hear it in place: the line before to the line after');
});

(async () => {
  for (const [name, fn] of results) {
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: ${e.stack || e}`); }
  }
  console.log(failures ? `FAIL: ${passes} passed, ${failures} failed` : `ok: ${passes} passed, 0 failed`);
  process.exit(failures ? 1 : 0);
})();
