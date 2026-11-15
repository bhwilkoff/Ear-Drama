/**
 * Kokoro, the downloadable voices (Decision 076 S6 PROTOTYPE, behind ?kokoro=1), run against the
 * SHIPPED js/voice-cast.js, js/plays-voice.js, js/kokoro-model.js and js/kokoro-voice.js with a fake
 * engine and a fake synthesizer: nothing here speaks or loads a model.
 *   node js/kokoro.test.js
 *
 * Seen to fail, 2026-11-15, against the S2 code before the S6 change:
 *   "a Kokoro casting resolves to the Kokoro voice": resolve() looked only among system voices, so
 *     a downloaded voice read as missing and the auto-cast system voice read instead.
 *   "a Kokoro part is read by the Kokoro engine": StandInVoice handed every voice to speechSynthesis.
 *   "falls back to the system voice when Kokoro cannot read the line" and "with no Kokoro engine":
 *     speechSynthesis was handed the Kokoro voice object (no such system voice) instead of a system voice.
 *   "a player made before the model boots": with the engine read once at creation (as first
 *     written), the player kept null and never used Kokoro (negative control run 2026-11-15).
 *   2026-11-15 (S6a, the web model in parts): the four part checks in "a file served in parts" accepted
 *     a bad manifest, and "a model served in parts" fetched model.onnx whole (404), against the S6 file.
 * The source scan in js/plays.test.js gained the kokoro- files (a cache write in the voice file,
 * an AudioContext in the model file), each control seen caught.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

for (const f of ['plays-core.js', 'voice-cast.js', 'kokoro-model.js', 'kokoro-voice.js', 'plays-voice.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
}
const VoiceCast = vm.runInThisContext('VoiceCast');
const StandInVoice = vm.runInThisContext('StandInVoice');
const KokoroModel = vm.runInThisContext('KokoroModel');
const KokoroVoice = vm.runInThisContext('KokoroVoice');

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const pass = JSON.stringify(a) === JSON.stringify(b);
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
const test = (name, fn) => results.push([name, fn]);

const RAW = [
  { name: 'Ava (Premium)', voiceURI: 'ava', lang: 'en-US', localService: true },
  { name: 'Samantha', voiceURI: 'sam', lang: 'en-US', localService: true },
];
const PARTS = ['role:MOLLY', 'role:FIBBER', 'role:DOC', 'directions'];
const sys = VoiceCast.systemVoices(RAW, 'en-US');
const kok = () => KokoroVoice.castable({ enabled: true, ready: true });
function memory() { const m = new Map(); return { getItem: k => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: k => m.delete(k) }; }

test('the cast lists downloaded voices only when on and ready', () => {
  eq(KokoroVoice.castable({ enabled: false, ready: true }), [], 'off: none, even downloaded');
  eq(KokoroVoice.castable({ enabled: true, ready: false }), [], 'on but not downloaded: none');
  const list = kok();
  eq(list.length, 28, 'on and downloaded: the 28 English voices');
  eq(list.filter(v => v.lang === 'en-GB').length, 8, 'eight British');
  ok(list.every(v => v.engine === 'kokoro' && / \(Kokoro\)$/.test(v.name)), 'each names its engine');
  eq(list.slice(0, 2).map(v => v.id), ['af_heart', 'af_bella'], 'Kokoro\'s own best grades first');
});

test('the prototype flag: ?kokoro=1 turns it on in this browser, ?kokoro=0 off', () => {
  const s = memory();
  eq(KokoroModel.enabled('', s), false, 'off by default');
  eq(KokoroModel.enabled('?kokoro=1', s), true, 'on');
  eq(KokoroModel.enabled('', s), true, 'kept');
  eq(KokoroModel.enabled('?kokoro=0', s), false, 'off again');
});

test('a Kokoro casting resolves to the Kokoro voice when it is downloaded', () => {
  const voices = [...kok(), ...sys];
  const entry = { engine: 'kokoro', voice: 'bm_george', name: 'George (Kokoro)', rate: 1.2, pitch: 0.9 };
  const r = VoiceCast.resolve(entry, 'role:DOC', voices, VoiceCast.autoCast(PARTS, voices));
  eq([r.read, r.voice && r.voice.engine, r.voice && r.voice.id, r.missing, r.rate, r.pitch], [true, 'kokoro', 'bm_george', null, 1.2, 0.9], 'read by George');
});

test('a Kokoro casting falls back visibly when the model is gone', () => {
  const entry = { engine: 'kokoro', voice: 'bm_george', name: 'George (Kokoro)', rate: 1, pitch: 1 };
  const auto = VoiceCast.autoCast(PARTS, sys);
  const r = VoiceCast.resolve(entry, 'role:DOC', sys, auto);
  eq([r.read, r.voice.engine, r.missing], [true, 'system', 'George (Kokoro)'], 'a system voice reads; the chip names George as missing');
  eq(r.entry.voice, 'bm_george', 'the choice is kept for when the voice returns');
});

test('a system voice id that happens to equal a Kokoro id is never confused with it', () => {
  const clash = VoiceCast.systemVoices([{ name: 'George', voiceURI: 'bm_george', lang: 'en-GB', localService: true }], 'en-US');
  const entry = { engine: 'kokoro', voice: 'bm_george', name: 'George (Kokoro)', rate: 1, pitch: 1 };
  const r = VoiceCast.resolve(entry, 'role:DOC', clash, VoiceCast.autoCast(PARTS, clash));
  eq(r.missing, 'George (Kokoro)', 'the engine is part of the match');
});

test('the caster offers downloaded voices first when they are present (castFor order)', () => {
  const storage = memory();
  let ready = false;
  const cast = VoiceCast.caster({ key: 's:x', parts: PARTS, storage,
                                  voices: () => [...KokoroVoice.castable({ enabled: true, ready }), ...sys] });
  eq(cast.resolve('role:MOLLY').voice.engine, 'system', 'before the download, system voices cast');
  ready = true;
  eq(cast.resolve('role:MOLLY').voice.engine, 'system', 'a download never recasts a part already cast');
  cast.recast();
  eq(cast.resolve('role:MOLLY').voice.id, 'af_heart', 'Recast all gives the largest part the best downloaded voice');
});

function fakeSynth() {
  const spoken = [];
  return { spoken, getVoices: () => RAW, speak(u) { spoken.push(u); setTimeout(() => u.onend(), 0); }, cancel() {}, addEventListener() {} };
}
function Utterance(text) { this.text = text; }
function fakeKokoro(answer = true) {
  const calls = [];
  return { calls, speak: async (text, id, opts) => { calls.push([text, id, opts.rate, opts.pitch]); return answer; }, cancel() {} };
}
function castWith(entry) {
  const storage = memory();
  const voices = () => [...kok(), ...sys];
  const cast = VoiceCast.caster({ key: 's:y', parts: PARTS, storage, voices });
  cast.set('role:DOC', entry);
  return cast;
}

test('a Kokoro part is read by the Kokoro engine, at its speed and pitch, and never by speechSynthesis', async () => {
  const synth = fakeSynth();
  const kokoro = fakeKokoro(true);
  const cast = castWith({ engine: 'kokoro', voice: 'af_bella', name: 'Bella (Kokoro)', rate: 1.3, pitch: 0.9 });
  const v = StandInVoice.create({ muted: true, synth, Utterance, language: 'en-US', cast, kokoro });
  eq(await v.speak('Anybody _home_?', 'role:DOC'), true, 'read');
  eq(kokoro.calls, [['Anybody home?', 'af_bella', 1.3, 0.9]], 'Kokoro read the words as spoken');
  eq(synth.spoken.length, 0, 'the system synthesizer said nothing');
});

test('falls back to the system voice when Kokoro cannot read the line', async () => {
  const synth = fakeSynth();
  const kokoro = fakeKokoro(false);
  const cast = castWith({ engine: 'kokoro', voice: 'af_bella', name: 'Bella (Kokoro)', rate: 1, pitch: 1 });
  const v = StandInVoice.create({ muted: true, synth, Utterance, language: 'en-US', cast, kokoro });
  eq(await v.speak('Anybody home?', 'role:DOC'), true, 'still read');
  eq(synth.spoken.map(u => u.voice.name), ['Ava (Premium)'], 'by the part\'s auto-cast system voice (DOC, third of two voices: Ava again)');
});

test('with no Kokoro engine, a Kokoro voice in the list still reads through the system fallback', async () => {
  const synth = fakeSynth();
  const cast = castWith({ engine: 'kokoro', voice: 'af_bella', name: 'Bella (Kokoro)', rate: 1, pitch: 1 });
  const v = StandInVoice.create({ muted: true, synth, Utterance, language: 'en-US', cast, kokoro: null });
  eq(await v.speak('Anybody home?', 'role:DOC'), true, 'read');
  eq(synth.spoken.map(u => u.voice.name), ['Ava (Premium)'], 'by a system voice, never a Kokoro voice handed to speechSynthesis');
});

test('a player made before the model boots still hands Kokoro parts to the engine once it exists', async () => {
  const synth = fakeSynth();
  const cast = castWith({ engine: 'kokoro', voice: 'af_bella', name: 'Bella (Kokoro)', rate: 1, pitch: 1 });
  const v = StandInVoice.create({ muted: true, synth, Utterance, language: 'en-US', cast });
  const fake = fakeKokoro(true);
  const real = KokoroVoice.engine;
  KokoroVoice.engine = () => fake;
  try {
    eq(await v.speak('Anybody home?', 'role:DOC'), true, 'read');
    eq(fake.calls.length, 1, 'by the engine that appeared after the player was made');
  } finally { KokoroVoice.engine = real; }
});

test('a manifest is refused without a permissive license, a size and a SHA-256 for every file', () => {
  const f = { path: 'model_q8f16.onnx', role: 'model', bytes: 86033585, sha256: '0'.repeat(64), license: 'Apache-2.0' };
  eq(KokoroModel.accept({ format: 1, files: [f] }).ok, true, 'Apache-2.0 with size and hash');
  eq(KokoroModel.accept({ format: 1, files: [{ ...f, license: undefined }] }).ok, false, 'no license recorded');
  eq(KokoroModel.accept({ format: 1, files: [{ ...f, license: 'GPL-3.0' }] }).ok, false, 'GPL (eSpeak data, Piper) refused');
  eq(KokoroModel.accept({ format: 1, files: [{ ...f, sha256: 'abc' }] }).ok, false, 'no SHA-256');
  eq(KokoroModel.accept({ format: 1, files: [{ ...f, path: '../x' }] }).ok, false, 'a path outside the folder');
  eq(KokoroModel.sizeText(KokoroModel.totalBytes({ files: [f, { ...f, bytes: 14622720 }] })), '101 MB', 'the size shown before download');
});

test('a file served in parts is accepted only when its parts are checked and add up', () => {
  const part = (i, bytes) => ({ path: `model.onnx.part${i}`, bytes, sha256: String(i).repeat(64).slice(0, 64) });
  const f = { path: 'model.onnx', role: 'model', bytes: 30, sha256: 'a'.repeat(64), license: 'Apache-2.0', parts: [part(0, 20), part(1, 10)] };
  eq(KokoroModel.accept({ format: 1, files: [f] }).ok, true, 'two parts adding up to the whole');
  eq(KokoroModel.accept({ format: 1, files: [{ ...f, bytes: 31 }] }).ok, false, 'parts that do not add up');
  eq(KokoroModel.accept({ format: 1, files: [{ ...f, parts: [part(0, 20), { ...part(1, 10), sha256: 'x' }] }] }).ok, false, 'a part without a SHA-256');
  eq(KokoroModel.accept({ format: 1, files: [{ ...f, parts: [{ ...part(0, 30), path: '../m' }] }] }).ok, false, 'a part outside the folder');
  eq(KokoroModel.accept({ format: 1, files: [{ ...f, parts: [] }] }).ok, false, 'no parts');
});

async function hex(bytes) {
  const d = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}
function fakeCaches() {
  const store = new Map();
  const cache = {
    match: async (u) => (store.has(u) ? new Response(store.get(u)) : undefined),
    put: async (u, r) => { store.set(u, new Uint8Array(await r.arrayBuffer())); },
    delete: async (u) => store.delete(u),
  };
  return { store, open: async () => cache, delete: async () => { store.clear(); return true; } };
}

test('a model served in parts downloads part by part, is checked whole, and reads back as one file', async () => {
  const whole = new Uint8Array(30).map((_, i) => i * 7);
  const a = whole.slice(0, 20), b = whole.slice(20);
  const manifest = { format: 1, files: [{ path: 'model.onnx', role: 'model', bytes: 30, sha256: await hex(whole), license: 'Apache-2.0',
    parts: [{ path: 'model.onnx.part00', bytes: 20, sha256: await hex(a) }, { path: 'model.onnx.part01', bytes: 10, sha256: await hex(b) }] }] };
  const served = { 'manifest.json': JSON.stringify(manifest), 'model.onnx.part00': a, 'model.onnx.part01': b };
  const fetched = [];
  const fetchImpl = async (u) => { const k = u.split('/').pop(); fetched.push(k); return served[k] ? new Response(served[k]) : new Response('', { status: 404 }); };
  const caches = fakeCaches();
  const m = KokoroModel.create({ manifestURL: 'https://eardrama.org/data/kokoro/manifest.json', fetchImpl, cachesImpl: caches });
  eq(await m.check(), false, 'nothing downloaded yet');
  await m.download();
  eq(fetched.filter(k => k !== 'manifest.json'), ['model.onnx.part00', 'model.onnx.part01'], 'each part fetched once; the whole never asked for');
  eq(await m.check(), true, 'ready');
  eq([...new Uint8Array(await m.bytes('model'))], [...whole], 'the parts read back as the whole file');

  const bad = fakeCaches();
  served['model.onnx.part01'] = new Uint8Array(10);
  const m2 = KokoroModel.create({ manifestURL: 'https://eardrama.org/data/kokoro/manifest.json', fetchImpl, cachesImpl: bad });
  let refused = false;
  try { await m2.download(); } catch (e) { refused = /checksum/.test(e.message); }
  eq(refused, true, 'a corrupt part is refused');
  eq(await m2.check(), false, 'and the model is not ready');
});

test('long speeches render in pieces under the token limit, cut at punctuation, nothing lost', () => {
  const ps = 'ðə kwˈɑləɾi ʌv mˈɜɹsi ɪz nˌɑt stɹˈAnd. '.repeat(30);
  const parts = KokoroVoice.chunks(ps, 400);
  ok(parts.length > 1, 'split');
  ok(parts.every(p => p.length <= 400), 'each under the limit');
  eq(parts.join(''), ps, 'joined, the whole speech');
  ok(parts.slice(0, -1).every(p => /[.!?;,] ?$|\s$/.test(p) || p.endsWith('.')), 'cut at a stop');
  eq(KokoroVoice.chunks('ˈAbəl', 400), ['ˈAbəl'], 'a short line is one piece');
});

test('tokenize maps phonemes through the vocabulary and pads both ends', () => {
  eq(KokoroVoice.tokenize('ab?', { a: 43, b: 44, '?': 6 }), [0, 43, 44, 6, 0], 'padded');
  eq(KokoroVoice.tokenize('a❓b', { a: 43, b: 44 }), [0, 43, 44, 0], 'unknown symbols dropped');
});

(async () => {
  for (const [name, fn] of results) {
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: ${e.stack}`); }
  }
  console.log(`${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
