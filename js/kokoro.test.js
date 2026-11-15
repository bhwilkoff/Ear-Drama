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
