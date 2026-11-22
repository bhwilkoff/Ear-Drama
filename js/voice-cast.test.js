/**
 * Casting the device voices (PLAYS-DESIGN §2.8, Decision 076 S2), run against the SHIPPED
 * js/voice-cast.js, js/plays-voice.js and js/plays-session.js with a fake synthesizer: nothing
 * here speaks (every `speak` is a stub that ends at once, every utterance muted).
 *   node js/voice-cast.test.js
 *
 * Seen to fail, 2026-11-14:
 *   "one cast everywhere" against the shipped code before S2 (each player assigned voices in
 *     the order parts first spoke): MOLLY was read by Samantha in the recorder, Ava (Premium) in the listen-through.
 *   autoCast giving the best voice to the LAST part: "the largest part gets the best voice" fails.
 *   autoCast keyed on the part's name (a hash of the id): "renaming every part changes nothing" fails.
 *   autoCast without the gender step: "alternates the voices' own reported gender" fails.
 *   resolve() returning the stored voice without checking the device has it: the fallback test fails.
 *   StandInVoice reading every part's entry but ignoring rate and pitch: the per-part speed test fails.
 * The shared-cast test carries its own control: two players without a cast still disagree.
 *
 * Decision 086 (the defaults in Settings > Voices), seen to fail 2026-11-22:
 *   ordered() without the engine rank (downloaded voices sorted among the device's by quality only):
 *     "the Default pool: downloaded first, then the person's order" fails ("Heart first").
 *   caster() writing auto-cast into storage on first read, as before: "a Default is worked out at
 *     each read, never written in" fails.
 *   loadDefaults() ignoring the stored row: "the defaults persist" and "at the default speed" fail.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

for (const f of ['plays-core.js', 'voice-cast.js', 'plays-voice.js', 'plays-session.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
}
const C = vm.runInThisContext('PlaysCore');
const VoiceCast = vm.runInThisContext('VoiceCast');
const StandInVoice = vm.runInThisContext('StandInVoice');
const ListenThrough = vm.runInThisContext('ListenThrough');

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const pass = JSON.stringify(a) === JSON.stringify(b);
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
const test = (name, fn) => results.push([name, fn]);

function line(id, role, kind = 'speech', text = 'words') {
  return kind === 'speech' ? { id, kind, role, parts: [{ say: text }] } : { id, kind, source: text };
}
function fixtureScript(names = ['MOLLY', 'FIBBER', 'DOC']) {
  const [M, F, D] = names;
  const lines = [
    line('L0001', null, 'direction', '(A _kitchen_.)'),
    line('L0002', F, 'speech', 'Well, Molly.'),
    line('L0003', M, 'speech', 'Yes, dearie?'),
    line('L0004', null, 'sound', 'SOUND: DOOR OPENS'),
    line('L0005', D, 'speech', 'Anybody home?'),
    line('L0006', M, 'speech', 'Come in.'),
    line('L0007', M, 'speech', 'Sit down.'),
    line('L0008', F, 'speech', 'Doc!'),
    line('L0009', M, 'speech', 'Tea?'),
    line('L0010', F, 'speech', 'Not for me.'),
    line('L0011', M, 'speech', 'Good night.'),
  ];
  return { id: 'gut-0', revision: 'r1', kind: 'radio', title: 'Good Grammar', authors: [], roles: [], lines };
}
const RAW = [
  { name: 'Cloud', voiceURI: 'cloud', lang: 'en-US', localService: false, default: true },
  { name: 'Daniel', voiceURI: 'com.daniel', lang: 'en-GB', localService: true, default: false },
  { name: 'Ava (Premium)', voiceURI: 'com.ava.premium', lang: 'en-US', localService: true, default: false },
  { name: 'Samantha', voiceURI: 'com.samantha', lang: 'en-US', localService: true, default: true },
  { name: 'Thomas', voiceURI: 'com.thomas', lang: 'fr-FR', localService: true, default: false },
  { name: 'Karen (Enhanced)', voiceURI: 'com.karen', lang: 'en-AU', localService: true, default: false },
];
function memoryStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k), m };
}
function fakeSynth(raw = RAW) {
  const spoken = [];
  const synth = { voices: raw, getVoices() { return this.voices; }, speak(u) { spoken.push(u); setTimeout(() => u.onend && u.onend(), 0); }, cancel() {} };
  function Utterance(text) { this.text = text; }
  return { synth, spoken, Utterance };
}
const voicesOf = (synth) => () => VoiceCast.systemVoices(synth.getVoices(), 'en-US');

/* ---- The voice list ---- */

test('the castable voices: local English only, best first (Premium, Enhanced, own language, default, name)', () => {
  const v = VoiceCast.systemVoices(RAW, 'en-US');
  eq(v.map(x => x.name), ['Ava (Premium)', 'Karen (Enhanced)', 'Samantha', 'Daniel'], 'tier, then en-US, then default, then name');
  eq(v.map(x => x.id), ['com.ava.premium', 'com.karen', 'com.samantha', 'com.daniel'], 'each by its voiceURI, never a language');
  eq(v.map(x => x.gender), [null, null, null, null], 'the web reports no gender');
  eq([VoiceCast.tierOf('Zoe (Premium)'), VoiceCast.tierOf('Microsoft Aria Online (Natural)'), VoiceCast.tierOf('Fred')], [2, 1, 0], 'tiers from the name');
});

/* ---- Auto-cast (§2.8 rule 4) ---- */

test('auto-cast is deterministic, gives distinct voices in cast order, and the largest part gets the best voice', () => {
  const script = fixtureScript();
  const parts = C.castParts(script);
  const voices = VoiceCast.systemVoices(RAW, 'en-US');
  const a = VoiceCast.autoCast(parts, voices);
  const b = VoiceCast.autoCast(parts, voices.slice());
  eq(a, b, 'the same voice list gives the same cast');
  eq(parts.map(p => p.id), ['role:MOLLY', 'role:FIBBER', 'role:DOC', 'sound', 'directions'], 'cast order, largest first');
  eq(a['role:MOLLY'].voice, voices[0].id, 'the largest part gets the best voice');
  eq(['role:MOLLY', 'role:FIBBER', 'role:DOC'].map(p => a[p].voice), voices.slice(0, 3).map(v => v.id), 'distinct voices, best first');
  eq([a.sound.engine, a.directions.engine], ['none', 'none'], 'sound and directions are Not read');
});

test('auto-cast never reads a part\'s name: renaming every part changes nothing', () => {
  const voices = VoiceCast.systemVoices(RAW, 'en-US');
  const plain = VoiceCast.autoCast(C.castParts(fixtureScript()), voices);
  const named = VoiceCast.autoCast(C.castParts(fixtureScript(['LADY MACBETH', 'MRS. GIBBS', 'FATHER BROWN'])), voices);
  eq(Object.values(named).map(e => [e.voice, e.pitch]), Object.values(plain).map(e => [e.voice, e.pitch]),
     'the same voices by place in the cast, whatever the names say');
  const src = fs.readFileSync(path.join(__dirname, 'voice-cast.js'), 'utf8');
  const auto = src.slice(src.indexOf('function autoCast'), src.indexOf('const clamp'));
  eq(/\.(title|role|name)\b|roleName|partTitle|lines\b/.test(auto.replace(/v\.name/g, '')), false, 'autoCast reads no title, role, name or line');
});

test('auto-cast alternates the voices\' own reported gender, where the platform reports one', () => {
  const voices = [
    { engine: 'system', id: 'a', name: 'A', gender: 'female' }, { engine: 'system', id: 'b', name: 'B', gender: 'female' },
    { engine: 'system', id: 'c', name: 'C', gender: 'male' }, { engine: 'system', id: 'd', name: 'D', gender: null },
    { engine: 'system', id: 'e', name: 'E', gender: 'male' },
  ];
  const parts = ['role:P1', 'role:P2', 'role:P3', 'role:P4'];
  eq(parts.map(p => VoiceCast.autoCast(parts, voices)[p].voice), ['a', 'c', 'b', 'e'], 'best first, each next of the other reported gender');
});

test('auto-cast with fewer voices than parts starts the list again at the next pitch', () => {
  const voices = VoiceCast.systemVoices(RAW, 'en-US').slice(0, 2);
  const a = VoiceCast.autoCast(C.castParts(fixtureScript()), voices);
  eq(['role:MOLLY', 'role:FIBBER', 'role:DOC'].map(p => [a[p].voice, a[p].pitch]),
     [[voices[0].id, 1], [voices[1].id, 1], [voices[0].id, 0.86]], 'the third part repeats the best voice, pitched');
});

/* ---- One cast everywhere (§2.8 rule 2) ---- */

async function whoReads(makeVoice) {
  const script = fixtureScript();
  const p = C.newProduction(script, { id: 'P1' });
  const recorder = makeVoice();
  // Recording FIBBER: the recorder cues 'Doc!' with MOLLY's 'Sit down.', then DOC's line is a Run-up.
  await recorder.v.speak('Sit down.', C.role('MOLLY'));
  await recorder.v.speak('Anybody home?', C.role('DOC'));
  const listen = makeVoice();
  const audio = { async startPlayback() {}, async playTake() {}, stopPlayback() {}, stop() {} };
  await ListenThrough.create({ production: p, script, store: {}, audio, voice: listen.v }).play();
  const byPart = (spoken) => Object.fromEntries(spoken.map(u => [u.part, u.voice.name]));
  return { recorder: byPart(recorder.spoken), listen: byPart(listen.spoken) };
}

test('one cast everywhere: the recorder and the listen-through read each part in the same voice', async () => {
  const storage = memoryStorage();
  const script = fixtureScript();
  const make = () => {
    const f = fakeSynth();
    const cast = VoiceCast.caster({ key: VoiceCast.productionKey('P1'), parts: C.castParts(script), voices: voicesOf(f.synth), storage });
    const v = StandInVoice.create({ muted: true, synth: f.synth, Utterance: f.Utterance, language: 'en-US', cast });
    const spoken = [];
    const speak = v.speak;
    v.speak = (text, part, rate) => { const n = f.spoken.length; return speak(text, part, rate).then(r => { if (f.spoken[n]) { f.spoken[n].part = part; spoken.push(f.spoken[n]); } return r; }); };
    return { v, spoken };
  };
  const r = await whoReads(make);
  eq(r.recorder['role:MOLLY'], r.listen['role:MOLLY'], 'MOLLY: one voice in both');
  eq(r.recorder['role:DOC'], r.listen['role:DOC'], 'DOC: one voice in both');
  eq(r.listen['role:MOLLY'], 'Ava (Premium)', 'and it is the auto-cast voice: the largest part, the best voice');

  // Control: players with no shared cast (each assigning by who spoke first) disagree.
  const loose = () => {
    const f = fakeSynth();
    const v = StandInVoice.create({ muted: true, synth: f.synth, Utterance: f.Utterance, language: 'en-US' });
    const spoken = [];
    const speak = v.speak;
    v.speak = (text, part, rate) => { const n = f.spoken.length; return speak(text, part, rate).then(x => { if (f.spoken[n]) { f.spoken[n].part = part; spoken.push(f.spoken[n]); } return x; }); };
    return { v, spoken };
  };
  const c = await whoReads(loose);
  ok(c.recorder['role:MOLLY'] !== c.listen['role:MOLLY'], 'control: without one cast the same part changes voice');
});

test('a choice made in the picker is the voice every player reads; Recast all runs auto-cast again', async () => {
  const storage = memoryStorage();
  const f = fakeSynth();
  const script = fixtureScript();
  const mk = () => VoiceCast.caster({ key: 'p:P2', parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  mk().set('role:MOLLY', { engine: 'system', voice: 'com.daniel', name: 'Daniel', rate: 1.3, pitch: 0.8 });
  const r = mk().resolve('role:MOLLY');
  eq([r.voice.name, r.rate, r.pitch, r.missing], ['Daniel', 1.3, 0.8, null], 'another player reads the choice');
  const v = StandInVoice.create({ muted: true, synth: f.synth, Utterance: f.Utterance, language: 'en-US', cast: mk() });
  await v.speak('Tea?', 'role:MOLLY', 1.5);
  const u = f.spoken[f.spoken.length - 1];
  eq([u.voice.name, Math.round(u.rate * 100) / 100, u.pitch, u.volume], ['Daniel', 1.95, 0.8, 0], 'its voice, its speed (times the session\'s), its pitch, muted');
  mk().recast();
  eq(mk().resolve('role:MOLLY').voice.name, 'Ava (Premium)', 'Recast all puts auto-cast back');
});

test('stage directions are Not read until given a voice; then the listen-through reads them', async () => {
  const storage = memoryStorage();
  const f = fakeSynth();
  const script = fixtureScript();
  const cast = VoiceCast.caster({ key: 'p:P3', parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  eq(cast.resolve(C.DIRECTIONS).read, false, 'directions: Not read by default');
  const p = C.newProduction(script, { id: 'P3' });
  const audio = { async startPlayback() {}, async playTake() {}, stopPlayback() {}, stop() {} };
  const voice = StandInVoice.create({ muted: true, synth: f.synth, Utterance: f.Utterance, language: 'en-US', cast });
  await ListenThrough.create({ production: p, script, store: {}, audio, voice }).play();
  eq(f.spoken.some(u => u.text.includes('kitchen')), false, 'no direction read');
  cast.set(C.DIRECTIONS, { engine: 'system', voice: 'com.karen', name: 'Karen (Enhanced)' });
  f.spoken.length = 0;
  await ListenThrough.create({ production: p, script, store: {}, audio, voice }).play();
  const d = f.spoken.find(u => u.text.includes('kitchen'));
  ok(!!d, 'the direction is read once it has a voice');
  eq(d && [d.text, d.voice.name], ['(A kitchen.)', 'Karen (Enhanced)'], 'in its voice, the italic marks never spoken');
  eq(f.spoken.some(u => u.text.includes('DOOR')), false, 'sound stays Not read');
});

/* ---- A voice that vanishes (§2.8 rule 8) ---- */

test('a cast voice this browser lacks falls back to the auto-cast voice, visibly, and the choice is kept', () => {
  const storage = memoryStorage();
  const f = fakeSynth();
  const script = fixtureScript();
  const cast = VoiceCast.caster({ key: 'p:P4', parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  cast.set('role:FIBBER', { engine: 'system', voice: 'com.zoe', name: 'Zoe (Premium)' });
  const r = cast.resolve('role:FIBBER');
  eq([r.read, r.missing, r.voice.name], [true, 'Zoe (Premium)', 'Karen (Enhanced)'], 'read by its auto-cast voice, Zoe named as missing');
  eq(cast.entry('role:FIBBER').voice, 'com.zoe', 'the choice is kept');
  f.synth.voices = RAW.concat([{ name: 'Zoe (Premium)', voiceURI: 'com.zoe', lang: 'en-US', localService: true }]);
  eq(cast.resolve('role:FIBBER').voice.name, 'Zoe (Premium)', 'and returns when the voice does');
  const k = VoiceCast.caster({ key: 'p:P5', parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  k.set('role:DOC', { engine: 'kokoro', voice: 'af_heart', name: 'Heart' });
  eq(k.resolve('role:DOC').missing, 'Heart', 'a Kokoro voice (none until S6) falls back the same way');
});

test('no voice yet (Chrome before voiceschanged): nothing is cast or stored, and nothing is spoken', async () => {
  const storage = memoryStorage();
  const f = fakeSynth([]);
  const script = fixtureScript();
  const cast = VoiceCast.caster({ key: 'p:P6', parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  const r = cast.resolve('role:MOLLY');
  eq([r.read, r.none], [false, true], 'not read, and says there is no voice');
  eq(VoiceCast.load('p:P6', storage), null, 'auto-cast waits for a non-empty list');
  const v = StandInVoice.create({ synth: f.synth, Utterance: f.Utterance, language: 'en-US', cast });
  eq(await v.speak('Tea?', 'role:MOLLY'), false, 'speak reports it could not read');
  eq(f.spoken.length, 0, 'nothing reached the synthesizer');
  f.synth.voices = RAW;
  eq(cast.resolve('role:MOLLY').voice.name, 'Ava (Premium)', 'the voices land: auto-cast runs');
  eq(VoiceCast.load('p:P6', storage), null, 'a Default is worked out at each read, never written in as a choice (Decision 086)');
});

test('the cast is this browser\'s: a production starts from its play\'s cast, keys are bounded, storage failures are survived', () => {
  const storage = memoryStorage();
  const f = fakeSynth();
  const script = fixtureScript();
  const play = VoiceCast.caster({ key: VoiceCast.scriptKey('gut-0'), parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  play.set('role:DOC', { engine: 'system', voice: 'com.daniel', name: 'Daniel' });
  const prod = VoiceCast.caster({ key: VoiceCast.productionKey('P7'), seed: VoiceCast.scriptKey('gut-0'), parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  eq(prod.resolve('role:DOC').voice.name, 'Daniel', 'the production starts from the play\'s cast');
  prod.set('role:DOC', { voice: 'com.samantha', name: 'Samantha' });
  eq(play.resolve('role:DOC').voice.name, 'Daniel', 'and changing it leaves the play\'s alone');
  for (let i = 0; i < 100; i++) VoiceCast.save(`p:x${i}`, {}, storage);
  ok(Object.keys(JSON.parse(storage.getItem(VoiceCast.KEY))).length <= 80, 'the newest 80 casts are kept');
  const broken = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } };
  const c = VoiceCast.caster({ key: 'p:P8', parts: C.castParts(script), voices: voicesOf(f.synth), storage: broken });
  eq(c.resolve('role:MOLLY').voice.name, 'Ava (Premium)', 'blocked storage still casts');
  const sync = fs.readFileSync(path.join(__dirname, 'sync.js'), 'utf8');
  eq(/ed\.cast|VoiceCast/.test(sync), false, 'sync never carries the cast (Q8)');
});

test('the table read reads from a line to the end, each part in its voice, following each line', async () => {
  const TableRead = vm.runInThisContext('TableRead');
  const storage = memoryStorage();
  const f = fakeSynth();
  const script = fixtureScript();
  const cast = VoiceCast.caster({ key: 's:gut-0', parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  const voice = StandInVoice.create({ muted: true, synth: f.synth, Utterance: f.Utterance, language: 'en-US', cast });
  const followed = [];
  const t = TableRead.create({ script, voice, cast, onLine: (l) => followed.push(l && l.id) });
  await t.play(4);
  eq(followed.filter(Boolean), ['L0005', 'L0006', 'L0007', 'L0008', 'L0009', 'L0010', 'L0011'], 'from line five on, sound skipped (Not read)');
  eq(f.spoken.map(u => u.voice.name)[0], 'Samantha', 'DOC in its own voice');
  eq(t.playing, false, 'done');
  const src = fs.readFileSync(path.join(__dirname, 'plays-session.js'), 'utf8');
  const tr = src.slice(src.indexOf('const TableRead'));
  eq(/\bstore\b|\bfetch\s*\(|\bAPI\./.test(tr), false, 'the table read holds no store and calls no network');
});

/* ---- The device's voice defaults (Settings > Voices, Decision 086) ---- */

const KOK = [
  { engine: 'kokoro', id: 'af_heart', name: 'Heart (Kokoro)', lang: 'en-US', tier: 2, grade: 'A', gender: 'female' },
  { engine: 'kokoro', id: 'am_michael', name: 'Michael (Kokoro)', lang: 'en-US', tier: 0, grade: 'C+', gender: 'male' },
  { engine: 'kokoro', id: 'am_adam', name: 'Adam (Kokoro)', lang: 'en-US', tier: 0, grade: 'F+', gender: 'male', offByDefault: true },
];

test('the Default pool: downloaded first, then the person\'s order; left-out voices dropped; never empty', () => {
  const sys = VoiceCast.systemVoices(RAW, 'en-US');
  const all = [...sys, ...KOK];
  const ids = (vs) => vs.map(v => v.id);
  eq(ids(VoiceCast.poolOf(all)), ['af_heart', 'am_michael', 'com.ava.premium', 'com.karen', 'com.samantha', 'com.daniel'],
     'Heart first: downloaded voices before the device\'s, Kokoro\'s lowest grade (Adam) left out, then the device\'s best first');
  let d = VoiceCast.normalizeDefaults(null);
  d = VoiceCast.move(all, d, sys.find(v => v.id === 'com.samantha'), -1);
  d = VoiceCast.move(all, d, sys.find(v => v.id === 'com.samantha'), -1);
  eq(ids(VoiceCast.poolOf(all, d)).slice(2), ['com.samantha', 'com.ava.premium', 'com.karen', 'com.daniel'], 'Samantha moved up twice, among the device\'s voices only');
  eq(ids(VoiceCast.poolOf(all, d)).slice(0, 2), ['af_heart', 'am_michael'], 'a device voice never climbs over a downloaded one');
  d = { ...d, off: { 'kokoro:af_heart': true, 'kokoro:am_adam': false } };
  eq(ids(VoiceCast.poolOf(all, d)).slice(0, 2), ['am_michael', 'am_adam'], 'Heart left out by the person; Adam ticked back in');
  const allOff = { order: [], off: Object.fromEntries(all.map(v => [VoiceCast.voiceKey(v), true])), rate: 1 };
  eq(VoiceCast.poolOf(all, allOff).length, all.length, 'every voice left out: the pool falls back to them all, never silence');
});

test('untouched parts read Default at the defaults\' speed; a choice overrides and Default takes it back', () => {
  const storage = memoryStorage();
  const f = fakeSynth();
  const script = fixtureScript();
  VoiceCast.saveDefaults({ order: [], off: {}, rate: 1.2 }, storage);
  const cast = VoiceCast.caster({ key: 'p:D1', parts: C.castParts(script), voices: voicesOf(f.synth), storage });
  const r = cast.resolve('role:MOLLY');
  eq([r.isDefault, r.voice.name, r.rate], [true, 'Ava (Premium)', 1.2], 'Default: the best voice, at the default speed');
  cast.set('role:MOLLY', { engine: 'system', voice: 'com.daniel', name: 'Daniel' });
  eq([cast.resolve('role:MOLLY').isDefault, cast.resolve('role:MOLLY').voice.name], [false, 'Daniel'], 'chosen in the picker');
  eq(cast.defaultEntry('role:MOLLY').name, 'Ava (Premium)', 'the picker can still name what Default would read');
  cast.reset('role:MOLLY');
  eq([cast.resolve('role:MOLLY').isDefault, cast.resolve('role:MOLLY').voice.name], [true, 'Ava (Premium)'], 'Default chosen again');
});

test('a download reaches every untouched part at once, and leaves the person\'s choices alone', () => {
  const storage = memoryStorage();
  const f = fakeSynth();
  const script = fixtureScript();
  let downloaded = false;
  const cast = VoiceCast.caster({ key: 'p:D2', parts: C.castParts(script), storage,
                                  voices: () => [...(downloaded ? KOK : []), ...voicesOf(f.synth)()] });
  cast.set('role:DOC', { engine: 'system', voice: 'com.samantha', name: 'Samantha' });
  eq(cast.resolve('role:MOLLY').voice.engine, 'system', 'before the download: a device voice');
  downloaded = true;
  eq(cast.resolve('role:MOLLY').voice.id, 'af_heart', 'after: the largest part reads the best downloaded voice, with no Recast');
  eq(cast.resolve('role:FIBBER').voice.id, 'am_michael', 'the next part the best of the other reported gender');
  eq(cast.resolve('role:DOC').voice.name, 'Samantha', 'a part the person cast keeps its voice');
});

test('the defaults persist in this browser, are cleaned on read, and survive blocked storage; old auto rows are not choices', () => {
  const storage = memoryStorage();
  VoiceCast.saveDefaults({ order: ['system:com.daniel', 7], off: { 'system:com.karen': true, x: 'yes' }, rate: 9 }, storage);
  eq(VoiceCast.loadDefaults(storage), { order: ['system:com.daniel'], off: { 'system:com.karen': true }, rate: 2 }, 'kept, cleaned, the speed clamped');
  storage.setItem(VoiceCast.DEFAULTS_KEY, '{not json');
  eq(VoiceCast.loadDefaults(storage), { order: [], off: {}, rate: 1 }, 'a broken row reads as no defaults');
  const broken = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } };
  VoiceCast.saveDefaults({ rate: 1.5 }, broken);
  eq(VoiceCast.loadDefaults(broken).rate, 1, 'blocked storage: the plain defaults');
  storage.setItem(VoiceCast.KEY, JSON.stringify({ 'p:old': { parts: { 'role:MOLLY': { engine: 'system', voice: 'com.samantha', name: 'Samantha' } }, at: 1 } }));
  eq(VoiceCast.load('p:old', storage), null, 'a row from before Decision 086 (auto-cast written in) is not a choice');
  const sync = fs.readFileSync(path.join(__dirname, 'sync.js'), 'utf8');
  eq(/ed\.voices|loadDefaults/.test(sync), false, 'sync never carries the defaults');
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
