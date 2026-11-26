// Writes catalog/tests/golden/mix_sound.json (B32 K2): the inputs, and every expected answer computed by the
// SHIPPED js/plays-core.js (buildTimeline, duckEnvelope, renderMix). Swift and Kotlin are held to it; re-run only
// when the algorithm changes on purpose, and port the change to every stack the same day.
//   node tools/mix_sound_golden.mjs
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ctx = vm.createContext({ crypto: globalThis.crypto, Blob, console });
vm.runInContext(fs.readFileSync(path.join(ROOT, 'js/plays-core.js'), 'utf8'), ctx, { filename: 'plays-core.js' });
const C = vm.runInContext('PlaysCore', ctx);

const RATE = 48000;
const PACK = 'eardrama-sounds-1';
const golden = {
  about: 'B32 K2: sound cues placed against takes and ducked under voices. Inputs are synthetic (sine: amp*sin(2*pi*hz*k/rate); click: amp where k % every == 0, else 0), made as 32-bit floats. Expected answers come from js/plays-core.js via tools/mix_sound_golden.mjs; js/plays.test.js, apple/Tests/MixSoundTests.swift and android MixSoundTest.kt hold their stacks to it. Samples are the 16-bit WAV values (round(clamp(x) * 32767)), within 1 LSB.',
  sampleRate: RATE,
  gap: C.DEFAULT_GAP,
  defaults: C.SOUND_DEFAULTS,
  script: {
    id: 'golden-sound', revision: 'r1', kind: 'radio', title: 'Golden Sound', authors: [],
    source: { name: 'Fixture', url: 'https://example.org' }, rights: { bucket: 'script_source_cleared', evidence: [] },
    roles: [{ name: 'ANNA', lines: 2, words: 4 }, { name: 'BEN', lines: 1, words: 3 }],
    lines: [
      { id: 'L0001', kind: 'speech', role: 'ANNA', parts: [{ say: 'Is it raining?' }] },
      { id: 'L0002', kind: 'speech', role: 'BEN', parts: [{ say: 'Listen.' }, { sound: 'rain on the roof' }, { say: 'Hear it?' }] },
      { id: 'L0003', kind: 'direction', source: '(The rain grows.)' },
      { id: 'L0004', kind: 'speech', role: 'ANNA', parts: [{ say: 'Close the door.' }] },
      { id: 'L0005', kind: 'sound', source: 'SOUND: DOOR SLAMS' },
    ],
  },
  takes: [
    { id: 't1', lineID: 'L0001', part: 'role:ANNA', frames: 48000, loudness: -16, peak: 0.5, synth: { type: 'sine', hz: 220, amp: 0.5 } },
    { id: 't2', lineID: 'L0002', part: 'role:BEN', frames: 72000, loudness: -20, peak: 0.5, synth: { type: 'sine', hz: 330, amp: 0.5 } },
    { id: 't4', lineID: 'L0004', part: 'role:ANNA', frames: 38400, loudness: -16, peak: 0.5, synth: { type: 'sine', hz: 440, amp: 0.5 } },
    { id: 't5', lineID: 'L0005', part: 'sound', frames: 9600, loudness: -16, peak: 0.3, synth: { type: 'sine', hz: 150, amp: 0.3 } },
    { id: 'k-door', lineID: 'L0002', part: 'sound', frames: 12000, loudness: -19, peak: 0.9, synth: { type: 'click', amp: 0.9, every: 6000 } },
  ],
  chosen: { L0001: 't1', L0002: 't2', L0004: 't4', L0005: 't5' },
  cues: [
    { pack: PACK, cue: 'knock-wood-1', frames: 14400, kind: 'effect', loudness: -19, peak: 0.8, synth: { type: 'click', amp: 0.8, every: 4800 } },
    { pack: PACK, cue: 'rain-steady-1', frames: 24000, kind: 'ambience', loudness: -22, peak: 0.3, synth: { type: 'sine', hz: 110, amp: 0.3 } },
    { pack: PACK, cue: 'calm-prelude', frames: 48000, kind: 'music', loudness: -20, peak: 0.4, synth: { type: 'sine', hz: 262, amp: 0.4 } },
  ],
};

const snd = (id, src, at, extra = {}) => ({ id, src, at, startMs: 0, gainDb: 0, fadeInMs: 0, fadeOutMs: 0, loop: false, duckDb: null, ...extra });
const soundBlock = {
  v: 1,
  lanes: { effects: { duckDb: -6 }, music: { duckDb: -12 } },
  slots: [
    { id: 'S1', line: 'L0001', piece: null, added: true, silent: false, sounds: [
      snd('B1', { pack: PACK, cue: 'calm-prelude' }, 'bed', { until: 'L0002', fadeInMs: 200, fadeOutMs: 500, loop: true }) ] },
    { id: 'S2', line: 'L0002', piece: 1, added: false, silent: false, sounds: [
      snd('K1', { pack: PACK, cue: 'knock-wood-1' }, 'before'),
      snd('R1', { pack: PACK, cue: 'rain-steady-1' }, 'under', { startMs: 500, gainDb: -3, loop: true, duckDb: -18 }),
      snd('D1', { take: 'k-door' }, 'after', { startMs: -500 }) ] },
    { id: 'S3', line: 'L0003', piece: null, added: false, silent: true, sounds: [] },
  ],
};

function synth(spec, frames) {
  const out = new Float32Array(frames);
  for (let k = 0; k < frames; k++) {
    out[k] = spec.type === 'sine' ? spec.amp * Math.sin((2 * Math.PI * spec.hz * k) / RATE) : (k % spec.every === 0 ? spec.amp : 0);
  }
  return out;
}

function production(sound) {
  const p = { id: 'P', scriptID: 'golden-sound', scriptRevision: 'r1', title: 'Golden Sound', created: 0, parts: {},
    takes: golden.takes.map(t => ({ id: t.id, lineID: t.lineID, part: t.part, file: `${t.id}.wav`, created: 0, frames: t.frames,
      sampleRate: RATE, capture: 'direct', heard: {}, loudness: t.loudness, peak: t.peak, bleed: false })),
    chosen: { ...golden.chosen }, roomTone: [], listenedThrough: false };
  if (sound) p.sound = sound;
  return p;
}
const resolver = (have) => (src) => {
  const c = golden.cues.find(x => x.pack === src.pack && x.cue === src.cue);
  return c && have(c) ? { key: `${c.pack}/${c.cue}`, frames: c.frames, kind: c.kind, loudness: c.loudness, peak: c.peak } : null;
};
const round6 = (x) => Math.round(x * 1e6) / 1e6;
const shape = (t) => ({
  placements: t.placements.map(x => ({ lineID: x.lineID, takeID: x.takeID, start: x.start, frames: x.frames, gain: round6(x.gain) })),
  totalFrames: t.totalFrames,
  ...(t.sounds ? {
    sounds: t.sounds.map(x => ({ soundID: x.soundID, slotID: x.slotID, lane: x.lane, start: x.start, frames: x.frames, inFrame: x.inFrame,
      outFrame: x.outFrame, loop: x.loop, gain: round6(x.gain), fadeIn: x.fadeIn, fadeOut: x.fadeOut, duck: x.duck })),
    voice: t.voice, left: t.left,
  } : {}),
});

function fakeOffline(channels, length) {
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
        const at = Math.round(s.when * RATE), off = Math.round(s.offset * RATE), d = s.buffer.getChannelData(0);
        for (let i = off; i < d.length && at + i - off < length; i++) out[at + i - off] += d[i] * s.g.gain.value;
      }
      return { getChannelData: () => out };
    },
  };
}

const script = golden.script;
const voiceOnly = C.buildTimeline(script, production(null));
const silentOnly = C.buildTimeline(script, production({ v: 1, slots: [soundBlock.slots[2]] }));
const full = C.buildTimeline(script, production(soundBlock), { resolveSound: resolver(() => true) });
let missingKind = null, missingDetail = null;
try { C.buildTimeline(script, production(soundBlock), { resolveSound: resolver(c => c.cue !== 'rain-steady-1') }); } catch (e) { missingKind = e.kind; missingDetail = e.detail; }
const without = C.buildTimeline(script, production(soundBlock), { resolveSound: resolver(c => c.cue !== 'rain-steady-1'), withoutMissing: true });

const envelopes = {};
for (const d of [-6, -12, -18]) envelopes[String(d)] = C.duckEnvelope(full.voice, d, RATE);
const probes = [0, 2000, 47999, 48000, 60000, 76800, 80000, 95040, 98000, 100800, 150000, 172800, 190000, 210000, 237599, 250000, 260000];
const duckAt = [];
for (const d of [-6, -12, -18]) for (const f of probes) duckAt.push([d, f, round6(20 * Math.log10(C.duckGains(envelopes[String(d)], f, 1)[0]))]);

const cueSamples = new Map(golden.cues.map(c => [`${c.pack}/${c.cue}`, synth(c.synth, c.frames)]));
const takeSamples = new Map(golden.takes.map(t => [t.id, synth(t.synth, t.frames)]));
const load = async (x) => (x.takeID ? takeSamples.get(x.takeID) : x.src.take ? takeSamples.get(x.src.take) : cueSamples.get(`${x.src.pack}/${x.src.cue}`));
let peak = 0;
const raw = await C.renderMix({ ...full, sounds: full.sounds }, load, (c, n) => {
  const f = fakeOffline(c, n);
  const go = f.startRendering;
  f.startRendering = async () => { const r = await go(); const d = r.getChannelData(0); for (const v of d) peak = Math.max(peak, Math.abs(v)); return r; };
  return f;
}, { chunkSeconds: 1 });
const wav = C.decodeWav(await raw.arrayBuffer());
const ints = Array.from(wav.samples, v => Math.round(v * 32768));
const every = 240;
const samples = [];
for (let f = 0; f < ints.length; f += every) samples.push(ints[f]);
let peakFrame = 0;
for (let i = 0; i < ints.length; i++) if (Math.abs(ints[i]) > Math.abs(ints[peakFrame])) peakFrame = i;
const extra = [peakFrame, 67200, 81600, 100800, 124800, 168000, 172800, 179999, 250000, 260000].map(f => [f, ints[f]]);

golden.sound = soundBlock;
golden.expect = {
  voiceOnly: shape(voiceOnly),
  silentOnly: shape(silentOnly),
  full: shape(full),
  missing: { kind: missingKind, detail: missingDetail },
  withoutMissing: shape(without),
  envelopes,
  duckAt,
  peak: round6(peak),
  scalar: round6(C.mixScalar(peak)),
  samplesEvery: every,
  samples,
  samplesAt: extra,
};
const out = path.join(ROOT, 'catalog/tests/golden/mix_sound.json');
const compact = (v, depth = 0) => {
  if (Array.isArray(v) && v.every(x => typeof x === 'number' || (Array.isArray(x) && x.every(y => typeof y === 'number')))) return JSON.stringify(v);
  if (Array.isArray(v)) return `[\n${v.map(x => ' '.repeat(depth + 1) + compact(x, depth + 1)).join(',\n')}\n${' '.repeat(depth)}]`;
  if (v && typeof v === 'object') {
    const keys = Object.keys(v);
    if (depth >= 2) return JSON.stringify(v);
    return `{\n${keys.map(k => `${' '.repeat(depth + 1)}${JSON.stringify(k)}: ${compact(v[k], depth + 1)}`).join(',\n')}\n${' '.repeat(depth)}}`;
  }
  return JSON.stringify(v);
};
fs.writeFileSync(out, compact(golden) + '\n');
console.log(`wrote ${path.relative(ROOT, out)}: total ${full.totalFrames} frames, peak ${round6(peak)}, scalar ${round6(C.mixScalar(peak))}, ${samples.length} samples`);
