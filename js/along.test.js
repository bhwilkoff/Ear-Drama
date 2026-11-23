/**
 * The read-along's controller (js/along.js; PLAYS-DESIGN §2.11 rules 3, 6, 7, 11), run against the SHIPPED
 * js/plays-core.js, js/reader-core.js and js/along.js with a fake voice and a fake player: nothing here speaks.
 *   node js/along.test.js
 *
 * Seen to fail, 2026-11-23, against mutated copies of js/along.js: pause() that left the line unheld (two cases),
 * setSpeed() that left a file in the air at the old rate, and onWord passing the voice's range without ReaderCore.word.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

for (const f of ['plays-core.js', 'reader-core.js', 'along.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
}
const C = vm.runInThisContext('PlaysCore');
const R = vm.runInThisContext('ReaderCore');
const Along = vm.runInThisContext('Along');

let passes = 0, failures = 0;
const later = [];
function atest(name, fn) { later.push([name, fn]); }
function eq(a, b, msg) {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}: got ${x}, want ${y}`);
}
function ok(v, msg) { if (!v) throw new Error(msg); }
const tick = () => new Promise(r => setTimeout(r, 0));

const script = {
  id: 's', title: 'T', roles: [{ name: 'A' }, { name: 'B' }],
  lines: [
    { id: 'L1', kind: 'speech', role: 'A', parts: [{ say: 'Good night, _sweet_ prince.' }] },
    { id: 'L2', kind: 'speech', role: 'B', parts: [{ say: 'Who is there?' }] },
    { id: 'L3', kind: 'direction', source: '[Enter HAMLET.]' },
    { id: 'L4', kind: 'speech', role: 'A', parts: [{ say: 'Nay, answer me.' }] },
  ],
};

/** A voice whose speak() waits until the test finishes it, recording what it was given. */
function fakeVoice(reads = () => true) {
  const v = { said: [], cancels: 0, pending: null, opts: null, rates: [] };
  v.reads = reads;
  v.speak = (text, part, rate, opts) => new Promise((resolve) => { v.said.push(text); v.rates.push(rate); v.opts = opts; v.pending = resolve; });
  v.cancel = () => { v.cancels += 1; if (v.pending) { const p = v.pending; v.pending = null; p(false); } };
  v.finish = (read = true) => { const p = v.pending; v.pending = null; if (p) p(read); };
  return v;
}
function fakeMedia() {
  const m = { made: [], rates: [] };
  m.make = (entry) => {
    let finish;
    const e = { entry, muted: false, rate(x) { m.rates.push(x); e.rateNow = x; }, pause() { if (finish) finish(true); }, play: () => new Promise((r) => { finish = r; }) };
    e.finish = (v = true) => finish && finish(v);
    m.made.push(e);
    return e;
  };
  return m;
}
const harness = (entries, extra = {}) => {
  const voice = extra.voice || fakeVoice();
  const media = fakeMedia();
  const log = { lines: [], words: [], changes: 0 };
  const a = Along.create({ script, entries, voice, media: media.make, speed: 1, onLine: (id) => log.lines.push(id), onWord: (id, w) => log.words.push([id, w]), onChange: () => { log.changes += 1; } });
  return { a, voice, media, log };
};
const voiceEntries = () => Along.tableEntries(script, { reads: () => true });

atest('the cast reads every line it reads, in order, and the light follows (rule 6)', async () => {
  const h = harness(voiceEntries());
  eq(h.a.entries.map(e => e.lineID), ['L1', 'L2', 'L3', 'L4'], 'every line with a voice');
  h.a.play();
  await tick();
  eq(h.voice.said, ['Good night, _sweet_ prince.'], 'the first line is given to the voice');
  eq(h.a.line(), 'L1', 'the line heard');
  h.voice.finish(); await tick();
  eq(h.a.line(), 'L2', 'the next line');
  h.voice.finish(); await tick(); h.voice.finish(); await tick(); h.voice.finish(); await tick();
  eq(h.a.playing, false, 'ended');
  eq(h.log.lines.slice(-1), [null], 'the light goes out at the end');
});

atest('a part the cast does not read is not in the plan (Previous and Next skip it)', async () => {
  const entries = Along.tableEntries(script, { reads: (part) => part !== C.linePart(script.lines[2]) });
  eq(entries.map(e => e.lineID), ['L1', 'L2', 'L4'], 'the direction has no voice');
});

atest('pause holds the line, and play starts that line again from its beginning (rule 6)', async () => {
  const h = harness(voiceEntries());
  h.a.play(); await tick();
  h.voice.finish(); await tick();
  eq(h.a.line(), 'L2', 'on the second line');
  h.a.pause(); await tick();
  eq([h.a.playing, h.a.held, h.a.line()], [false, true, 'L2'], 'held and still lit');
  ok(h.voice.cancels > 0, 'the voice was silenced');
  const before = h.voice.said.length;
  h.a.play(); await tick();
  eq(h.voice.said.length, before + 1, 'the line is given to the voice again');
  eq(h.voice.said[before], 'Who is there?', 'the same line, from its beginning');
  eq(h.a.line(), 'L2', 'still the second line');
});

atest('Previous and Next play from there; paused, they move the held line (rule 6)', async () => {
  const h = harness(voiceEntries());
  h.a.play(); await tick();
  h.a.next(); await tick();
  eq([h.a.playing, h.a.line()], [true, 'L2'], 'playing from the next line');
  h.a.pause();
  h.a.next();
  eq([h.a.playing, h.a.held, h.a.line()], [false, true, 'L3'], 'the held line moved');
  h.a.prev(); h.a.prev();
  eq(h.a.line(), 'L1', 'back to the first');
  h.a.prev();
  eq(h.a.line(), 'L1', 'no line before the first');
  eq([h.a.canPrev(), h.a.canNext()], [false, true], 'the ends');
});

atest('stop ends the reading and the light', async () => {
  const h = harness(voiceEntries());
  h.a.play(); await tick();
  h.a.stop();
  eq([h.a.playing, h.a.held, h.a.line()], [false, false, null], 'nothing lit');
  eq(h.log.lines.slice(-1), [null], 'the reader is told');
});

atest('the word heard is a voice range mapped onto the printed words (rule 3)', async () => {
  const h = harness(voiceEntries());
  h.a.play(); await tick();
  h.voice.opts.onWord(12, 5);
  eq(h.log.words.filter(w => w[1]).pop(), ['L1', { start: 13, end: 18 }], '"sweet" in "Good night, _sweet_ prince."');
  h.voice.opts.onWord(99, 3);
  eq(h.log.words.pop(), ['L1', null], 'a range outside the line marks nothing');
});

atest('a word reported after the line moved on is dropped', async () => {
  const h = harness(voiceEntries());
  h.a.play(); await tick();
  const late = h.voice.opts.onWord;
  h.a.next(); await tick();
  const n = h.log.words.length;
  late(0, 4);
  eq(h.log.words.length, n, 'nothing reported for the old line');
});

atest('a take or a file lights the line and marks no word, and takes the speed at once (rules 3, 7)', async () => {
  const plan = Along.dramaEntries([{ lineID: 'L1', url: 'a.mp3' }, { lineID: 'L2', url: 'b.mp3' }]);
  const h = harness(plan);
  h.a.play(); await tick();
  eq(h.media.made.length, 1, 'the first file is playing');
  eq(h.media.rates, [1], 'at the speed it was made with');
  h.a.setSpeed(1.5);
  eq(h.media.made[0].rateNow, 1.5, 'the file in the air took the new rate at once');
  eq(h.log.words.filter(w => w[1]), [], 'no word was marked');
  h.media.made[0].finish(); await tick();
  eq(h.a.line(), 'L2', 'the next file');
  eq(h.media.made[1].rateNow, 1.5, 'the next file starts at the new speed');
});

atest('a voice takes a new speed from its next line (rule 7)', async () => {
  const h = harness(voiceEntries());
  h.a.play(); await tick();
  h.a.setSpeed(2);
  h.voice.finish(); await tick();
  eq(h.voice.rates, [1, 2], 'the first line at 1x, the next at 2x');
});

atest('when nothing could be read the reading holds at the first line instead of racing through (a browser waiting for a press)', async () => {
  const h = harness(voiceEntries());
  h.a.play(); await tick();
  h.voice.finish(false); await tick();
  eq([h.a.playing, h.a.held, h.a.line()], [false, true, 'L1'], 'held at the first line');
  h.a.play(); await tick();
  h.voice.finish(true); await tick();
  eq(h.a.line(), 'L2', 'a press reads on');
});

atest('from() starts at the first line at or after the reader\'s place', async () => {
  const h = harness(voiceEntries());
  h.a.from(2);
  h.a.play(); await tick();
  eq(h.a.line(), 'L3', 'the third line');
});

atest('speed: steps, nearest step, label', async () => {
  eq(R.ALONG_SPEEDS, [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], 'quarter steps from half to double');
  eq([R.alongSpeed(1.3), R.alongSpeed('0.6'), R.alongSpeed(undefined), R.alongSpeed(NaN), R.alongSpeed(9), R.alongSpeed(0)], [1.25, 0.5, 1, 1, 2, 0.5], 'the nearest step');
  eq([R.speedLabel(1.25), R.speedLabel(1), R.speedLabel(2), R.speedLabel(0.5)], ['1.25×', '1×', '2×', '0.5×'], 'the label');
  const store = new Map();
  const storage = { getItem: (k) => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, v) };
  eq(R.savedSpeed(storage), 1, 'none saved');
  R.saveSpeed(1.74, storage);
  eq([store.get('ed.along.speed'), R.savedSpeed(storage)], ['1.75', 1.75], 'saved as a step');
  eq(R.savedSpeed({ getItem() { throw new Error('blocked'); } }), 1, 'blocked storage reads as 1x');
  R.saveSpeed(2, { setItem() { throw new Error('blocked'); } });
});

atest('a production\'s plan reads takes where there are takes and the cast where not', async () => {
  const p = { id: 'p', takes: [{ id: 't1', lineID: 'L2', part: 'role:B', file: 'f.wav', created: 1, frames: 10, sampleRate: 48000 }], chosen: { L2: 't1' }, roomTone: [] };
  const entries = Along.productionEntries(p, script, { reads: () => false });
  eq(entries.map(e => [e.lineID, e.source]), [['L1', 'voice'], ['L2', 'take'], ['L4', 'voice']], 'takes and voices, directions only with a voice');
});

(async () => {
  for (const [name, fn] of later) {
    try { await fn(); passes += 1; console.log(`  ok    ${name}`); }
    catch (e) { failures += 1; console.log(`  FAIL  ${name}\n        ${e.message}`); }
  }
  console.log(`${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
