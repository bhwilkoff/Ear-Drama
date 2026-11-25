/**
 * Casting an episode by ear (PLAYS-DESIGN §13 item 10, WEB-DESIGN §4.22), run against the SHIPPED
 * js/ear-core.js, own-core.js, own-store.js, player.js and api.js: the line that is lit, what is heard,
 * carrying and where it stops, undo, resume, the keys, what is kept and what becomes a script, the cues'
 * address and refusals, and the player held to one episode. No network, no sound.
 *   node js/ear.test.js
 *
 * Broken controls: MUTANTS below (each a rule of js/ear-core.js), and tools/own_mutants.mjs for the files it keeps in.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const dir = process.env.OWN_JS_DIR || __dirname;
const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8');
const load = (f) => vm.runInThisContext(read(f), { filename: f });
for (const f of ['plays-core.js', 'plays-store.js', 'own-core.js', 'own-store.js', 'reader-core.js', 'api.js']) load(f);
const O = vm.runInThisContext('OwnCore');
const PlayStore = vm.runInThisContext('PlayStore');
const OwnScripts = vm.runInThisContext('OwnScripts');
const ReaderCore = vm.runInThisContext('ReaderCore');
const API = vm.runInThisContext('API');
const SOURCE = read('ear-core.js');
const core = (src) => vm.runInThisContext(`(() => { ${src}\nreturn EarCore; })()`);
const EAR = core(SOURCE);

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  ok(x === y, x === y ? name : `${name}: got ${x}, want ${y}`);
}
const test = (name, fn) => results.push([name, fn]);

const VTT = `WEBVTT

00:00.000 --> 00:04.000
The Planet Man! This is the story of Dantro.

00:04.000 --> 00:06.000
I'm sorry, Pat.

00:06.000 --> 00:08.000
There, they're sending us a message.

00:08.000 --> 00:10.000
You are on the province of Mars.

00:12.500 --> 00:14.000
Cut your drive.

00:14.000 --> 00:16.000
Or we'll ray you out of space.
`;
const fresh = () => O.fromCues(O.parseCues(VTT));
const sit = (E, more = {}) => E.session({ doc: fresh(), ...more });
const cast = (S) => { const m = O.castOf(S.doc); return S.doc.lines.map(l => { const w = m.get(l.k); return w === O.OUT ? 'out' : w; }); };
/** The audio playing from `a` to `b` milliseconds, a frame every 16 ms. */
const playThrough = (S, a, b) => { for (let t = a; t <= b; t += 16) S.tick(t, true); };

/* Each is a rule with its own mutants: run over the shipped core, and over each broken one. */
const RULES = {
  hue(E) {
    const ps = [{ name: 'ANN', lines: 2 }, { name: 'BOB', lines: 9 }, { name: 'CY', lines: 2 }, { name: 'DEE', lines: 0 }];
    const H = vm.runInThisContext('PlaysCore').PART_HUES;
    eq([E.hueOf('BOB', ps), E.hueOf('ANN', ps), E.hueOf('CY', ps), E.hueOf('DEE', ps), E.hueOf('ZED', ps)], [H[0], H[1], H[2], 'none', 'none'], 'largest first, ties by who came first, no line none');
    const eight = Array.from({ length: 8 }, (_, i) => ({ name: `P${i}`, lines: 10 - i }));
    eq(E.hueOf('P7', eight), 'none', 'the eighth stands on neutral');
  },
  lit(E) {
    const S = sit(E);
    const at = (ms) => { S.tick(ms, false); return S.lit; };
    eq([0, 1453, 1454, 3999, 4000, 8000, 11000, 12499, 12500, 99999].map(at), [1, 1, 2, 2, 3, 5, 5, 5, 6, 7], 'the line lit is the last begun, and a pause between lines keeps it');
    const T = E.session({ doc: O.fromCues(O.parseCues(VTT.replace('00:00.000 -->', '00:01.000 -->'))) });
    T.tick(500, true);
    eq([T.lit, T.doc.heard.length], [0, 0], 'before the first line none is lit and none is heard');
    eq(T.give('A'), 'no_such_line', 'a tap with no line lit is refused');
    eq([S.tick(99999, false).moved, S.tick(0, false).moved], [false, true], 'a tick says when the line changes');
  },
  carry(E) {
    const S = sit(E);
    playThrough(S, 0, 1000);
    eq(S.give('announcer'), null, 'a tap is taken');
    playThrough(S, 1000, 5000);
    eq(cast(S).slice(0, 4), ['ANNOUNCER', 'ANNOUNCER', 'ANNOUNCER', null], 'the lit line and those after it as they are heard');
    S.give('Dantro');
    playThrough(S, 5000, 9000);
    eq(cast(S), ['ANNOUNCER', 'ANNOUNCER', 'DANTRO', 'DANTRO', 'DANTRO', null, null], 'until the next tap, and no line not yet heard');
    eq(S.count(), { cast: 5, lines: 7 }, 'the count');
    S.leaveOut();
    playThrough(S, 9000, 13000);
    eq(cast(S), ['ANNOUNCER', 'ANNOUNCER', 'DANTRO', 'DANTRO', 'out', 'out', null], 'Leave out carries as a part does');
    eq(E.rows(S.doc).map(r => r.named), [true, false, true, false, true, false, false], 'a name is printed where the speaker changes');
  },
  jump(E) {
    const S = sit(E);
    playThrough(S, 0, 500);
    S.give('A');
    S.jumped();
    S.tick(8100, true);
    eq(cast(S), ['A', null, null, null, null, null, null], 'a seek hears nothing between, and carries nothing over the gap');
    playThrough(S, 8100, 13000);
    eq(cast(S), ['A', null, null, null, null, null, null], 'lines after the gap are nobody\'s until a tap');
    S.give('B');
    playThrough(S, 13000, 14100);
    eq(cast(S), ['A', null, null, null, null, 'B', 'B'], 'and then they carry');
    const T = sit(E);
    T.tick(100, true);
    T.give('A');
    T.tick(5000, true);
    eq(cast(T).slice(0, 4), ['A', 'A', 'A', null], 'a slow frame hears the lines it passed');
  },
  paused(E) {
    const S = sit(E);
    playThrough(S, 0, 500);
    S.give('A');
    for (let t = 500; t < 9000; t += 16) S.tick(t, false);
    eq([cast(S), S.doc.heard.length], [['A', null, null, null, null, null, null], 1], 'a place moved while paused is seen, never heard');
  },
  again(E) {
    const S = sit(E);
    playThrough(S, 0, 9000);
    S.jumped(); S.tick(100, true); S.give('A');
    eq(cast(S), ['A', 'A', 'A', 'A', 'A', null, null], 'a tap on a line heard before carries over what was heard after it');
    S.jumped(); S.tick(4100, true); S.give('B');
    eq(cast(S), ['A', 'A', 'B', 'B', 'B', null, null], 'a late tap put right: back, and tap the other');
    S.jumped(); S.tick(6100, true); S.give('B');
    S.jumped(); S.tick(4100, true); S.give('A');
    eq(cast(S), ['A', 'A', 'A', 'B', 'B', null, null], 'and a mark after it stands');
    const T = sit(E);
    T.tick(100, true); T.give('A');
    playThrough(T, 100, 9000);
    T.jumped(); T.tick(4100, true); T.leaveOut();
    eq(cast(T), ['A', 'A', 'out', 'out', 'out', null, null], 'Leave out on a line heard before carries over what was heard after it');
  },
  undo(E) {
    const S = sit(E);
    eq([S.canUndo(), S.undo()], [false, 'nothing_to_undo'], 'nothing to take back at first');
    playThrough(S, 0, 500);
    S.give('A');
    playThrough(S, 500, 4500);
    S.give('B');
    eq(cast(S).slice(0, 3), ['A', 'A', 'B'], 'before');
    S.undo();
    eq(cast(S).slice(0, 3), ['A', 'A', 'A'], 'one tap taken back: the carry goes on over it');
    S.undo();
    eq([cast(S).slice(0, 3), S.canUndo()], [[null, null, null], false], 'and the first');
    eq(S.doc.heard.length, 3, 'what was heard is never taken back');
    S.tick(0, false); S.give('A'); S.assign(2, 'direction'); S.apply({ op: 'split', line: 3, at: 4 });
    S.undo(); S.undo(); S.undo();
    eq([S.doc.lines.length, S.canUndo()], [7, false], 'a line sheet\'s steps are undone in the same order');
  },
  parts(E) {
    const S = sit(E);
    eq(S.add(' dantro: '), { name: 'DANTRO', refusal: null }, 'a part is named as a part is stored');
    eq([cast(S)[0], S.parts()], [null, [{ name: 'DANTRO', lines: 0 }]], 'with no line lit it is only named');
    S.tick(8100, false);
    eq([S.add('Pat').refusal, cast(S)[4]], [null, 'PAT'], 'with a line lit it is theirs');
    eq([S.add('').refusal, S.add('x'.repeat(41)).refusal], ['empty', 'too_long'], 'a name the app cannot keep');
    eq(S.parts().map(p => p.name), ['DANTRO', 'PAT'], 'the first named is the first');
    S.add('Dantro');
    eq(S.parts().map(p => p.name), ['DANTRO', 'PAT'], 'a name twice is one part, and the order is the one they were named in');
    S.give('PAT'); S.undo();
    eq(S.parts().map(p => p.name), ['DANTRO', 'PAT'], 'a part stays when its line is taken back');
    const T = sit(E);
    T.tick(8100, false);
    T.add('A'); T.undo();
    eq([T.parts(), T.give('A')], [[{ name: 'A', lines: 0 }], null], 'a part stays after its first line is undone, to be tapped');
    playThrough(T, 8100, 13000);
    eq([T.sample('A').k, T.sample('A').k, T.sample('A').k, T.sample('B')], [5, 6, 5, null], 'Hear plays the next of a part\'s lines each time, around again');
    eq(E.spanOf({ at: [1000, 1100] }), [1000, 1700], 'a line of a tenth of a second is heard');
    eq(E.spanOf({ at: [1000, 4000] }), [1000, 4000], 'and no longer than it is');
  },
  takes(E) {
    let S = sit(E);
    playThrough(S, 0, 500);
    S.give('A');
    playThrough(S, 500, 5000);
    const doc = O.done(S.doc, { keepOpen: true });
    S = E.session({ doc, takes: ['L0003'] });
    S.tick(100, false);
    eq(S.give('B'), 'line_has_take', 'a tap that would move a recorded line is refused');
    S.tick(4100, false);
    eq([S.give('B'), S.leaveOut(), S.assign(3, 'direction')], ['line_has_take', 'line_has_take', 'line_has_take'], 'and one on it');
    eq(cast(S).slice(0, 3), ['A', 'A', 'A'], 'nothing moved');
    const T = E.session({ doc: O.done(fresh(), { keepOpen: true }), takes: ['L0003'] });
    T.tick(1400, true);
    T.give('A');
    playThrough(T, 1500, 4600);
    eq([cast(T)[1], cast(T)[2]], ['A', null], 'a carried part never reaches a recorded line of nobody\'s');
  },
  keys(E) {
    const k = (key, more = {}) => E.keyOf({ key, metaKey: false, ctrlKey: false, altKey: false, shiftKey: false, ...more });
    eq([k('1'), k('9')], [{ act: 'part', n: 0 }, { act: 'part', n: 8 }], '1 to 9 are the parts');
    eq([k(' '), k('ArrowLeft'), k('u'), k('U')], [{ act: 'toggle' }, { act: 'back' }, { act: 'undo' }, { act: 'undo' }], 'Space, Left, U');
    eq([k('z', { metaKey: true }), k('z', { ctrlKey: true })], [{ act: 'undo' }, { act: 'undo' }], 'the browser\'s own Undo');
    eq([k('0'), k('ArrowRight'), k('1', { metaKey: true }), k('1', { altKey: true }), k(' ', { ctrlKey: true }), k('z'), k('Z', { metaKey: true, shiftKey: true }), k('F1')], Array(8).fill(null), 'and no other key');
  },
  resume(E) {
    const S = sit(E);
    playThrough(S, 0, 500);
    S.give('A');
    playThrough(S, 500, 4500);
    const kept = JSON.parse(JSON.stringify(O.kept(S.doc)));
    const T = E.session({ doc: kept, names: ['A', 'B'] });
    eq([cast(T), T.parts().map(p => p.name), T.canUndo()], [cast(S), ['A', 'B'], false], 'a kept casting is the casting');
    T.tick(4500, true);
    eq(cast(T)[2], 'A', 'taken up where it was left, the carry goes on');
    playThrough(T, 4500, 6500);
    eq(cast(T)[3], 'A', 'line after line');
    eq([E.placeOf({ place: 4500 }, kept), E.placeOf({ place: 0 }, kept), E.placeOf({ place: 16000 }, kept), E.placeOf({ place: 9e9 }, kept), E.placeOf(null, kept), E.placeOf({ place: 'x' }, kept)], [4500, 0, 0, 0, 0, 0], 'the place it was left, or the start');
    const cues = O.parseCues(VTT);
    eq(E.signature(cues), E.signature(JSON.parse(JSON.stringify(cues))), 'the same transcript is the same');
    ok(E.signature(cues) !== E.signature(O.parseCues(VTT.replace('sorry', 'sure'))), 'other words are another');
    ok(E.signature(cues) !== E.signature(O.parseCues(VTT.replace('00:12.500', '00:12.400'))), 'other times are another');
    eq([E.refusalOf(fresh()), E.refusalOf(O.newDoc([])), E.refusalOf({ lines: Array(O.MAX_LINES + 1).fill({}) })], [null, 'no_lines', 'too_many_lines'], 'what cannot be cast');
  },
  rename: (E) => {
    const at = (S) => S.parts().map(p => `${p.name} ${p.lines}`);
    const start = () => {
      const S = E.session({ doc: O.fromCues([0, 1, 2, 3, 4, 5].map(i => ({ text: `Line ${i} here.`, at: [i * 1000, i * 1000 + 1000] }))), names: [] });
      for (const [ms, who] of [[100, 'Ann'], [2100, 'Bob'], [4100, 'Cy']]) { S.tick(ms, true); S.add(who); S.tick(ms + 1000, true); }
      return S;
    };
    let S = start();
    eq(at(S), ['ANN 2', 'BOB 2', 'CY 2'], 'three parts');
    eq(S.rename('BOB', 'the planet man'), { name: 'THE PLANET MAN', refusal: null }, 'renamed');
    eq(at(S), ['ANN 2', 'THE PLANET MAN 2', 'CY 2'], 'every line of theirs, in the same place: the same number and hue');
    S.undo();
    eq(at(S), ['ANN 2', 'BOB 2', 'CY 2'], 'one Undo takes it back, the order with it');
    S.rename('BOB', 'ann');
    eq(at(S), ['ANN 4', 'CY 2'], 'a name another part has joins the two');
    S.rename('CY', 'Cyrus');
    S.undo();
    eq(at(S), ['ANN 4', 'CY 2'], 'the second only');
    S.undo();
    eq(at(S), ['ANN 2', 'BOB 2', 'CY 2'], 'then the first');
    eq(S.undo(), null, 'and what was before it');
    S = start();
    S.rename('ANN', 'cy');
    eq(at(S), ['BOB 2', 'CY 4'], 'the one that had the name keeps its place');
    S = start();
    eq([S.rename('ANN', '').refusal, S.rename('ZED', 'X').refusal, S.rename('ANN', 'ANN').refusal], ['empty', 'no_such_part', null], 'refusals');
    S = start();
    S.names.push('DEE');
    eq(S.rename('DEE', 'Dora').refusal, null, 'a part with no line yet');
    eq(at(S), ['ANN 2', 'BOB 2', 'CY 2', 'DORA 0'], 'renamed too');
    S = start();
    S.doc = O.done(S.doc, { keepOpen: true });
    S.takes = new Set(['L0002']);
    eq([S.rename('ANN', 'X').refusal, at(S)[0]], ['part_has_take', 'ANN 2'], 'a part with a take on a carried line keeps its name');
    eq(S.undo(), 'nothing_to_undo', 'nothing to undo');
    eq(S.rename('CY', 'X').refusal, null, 'another does not');
  },
};
for (const [name, rule] of Object.entries(RULES)) test(`rule: ${name}`, () => rule(EAR));

/** [rule, text in the core, what it becomes]. */
const MUTANTS = [
  ['hue', 'b.p.lines - a.p.lines || a.i - b.i', 'a.i - b.i'],
  ['hue', '.filter(x => x.p.lines > 0)', ''],
  ['rename', "take(O.apply(S.doc, { op: 'rename', part: from, to: name }, env()))", "take(O.apply(S.doc, { op: 'rename', part: from, to: name }))"],
  ['rename', 'while (!why && renames.length', 'while (false && renames.length'],
  ['rename', 'order.map(n => (n === from ? name : n))', 'before.filter(n => n !== from)'],
  ['rename', 'order.includes(name) ? order.filter(n => n !== from) :', ''],
  ['lit', 'S.lit = k;', 'S.lit = k || 1;'],
  ['lit', 'const moved = k !== S.lit;', 'const moved = true;'],
  ['jump', 'from = k;\n      if (next', 'from = 0;\n      if (next'],
  ['carry', 'named: who !== null && who !== before', 'named: who !== null'],
  ['again', "take(O.tap(S.doc, S.lit, { out: true }, env()))", 'take(O.leaveOutHeard(S.doc, S.lit, env()))'],
  ['jump', 'S.jumped = () => { from = 0; };', 'S.jumped = () => {};'],
  ['jump', 'O.hear(S.doc, k, from)', 'O.hear(S.doc, k)'],
  ['paused', 'if (!playing || !k)', 'if (!k)'],
  ['again', "take(O.tap(S.doc, S.lit, { role: name }, env()))", "take(O.apply(S.doc, { op: 'assign', line: S.lit, to: { role: name } }, env()))"],
  ['undo', 'if (!r.refusal) S.doc = r.doc;', 'if (!r.refusal) S.doc = { ...r.doc, undo: [] };'],
  ['parts', 'const refusal = S.lit ? S.give(name) : null;', 'const refusal = null;'],
  ['parts', 'if (!refusal && !known) S.names.push(name);', 'if (!refusal) S.names.unshift(name);'],
  ['parts', 'mine[(i + 1) % mine.length]', 'mine[0]'],
  ['parts', 'Math.max(l.at[1], l.at[0] + LEAST_MS)', 'l.at[1]'],
  ['takes', 'const env = () => ({ takes: [...S.takes] });', 'const env = () => ({});'],
  ['takes', 'if (S.takes.size) {', 'if (false) {'],
  ['keys', "k >= '1' && k <= '9'", "k >= '0' && k <= '9'"],
  ['keys', 'if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return null;', ''],
  ['resume', 'return p > 0 && p < last ? p : 0;', 'return p;'],
  ['resume', '`${c.at[0]}-${c.at[1]} ${c.text}`', 'c.text'],
  ['resume', 'doc.lines.length > O.MAX_LINES', 'false'],
];
test('a mutant of every rule fails it', () => {
  for (const [rule, from, to] of MUTANTS) {
    ok(SOURCE.split(from).length === 2, `the mutant's text is in the core once: ${from}`);
    const was = [passes, failures, console.log];
    console.log = () => {};
    let broke = false;
    try { RULES[rule](core(SOURCE.split(from).join(to))); } catch { broke = true; }
    const caught = broke || failures > was[1];
    [passes, failures, console.log] = was;
    ok(caught, `${rule} passes the mutant of: ${from}`);
  }
});

/* ---- What is kept, and the script it becomes ---- */

const opener = (backend = PlayStore.memoryBackend()) => ({ backend, store: OwnScripts.open({ backend, now: () => 1000 }) });
const EP = { id: 'planetman|n53', url: 'https://eardrama.org/episode/planetman%7Cn53' };
async function half() {
  const { backend, store } = opener();
  const S = sit(EAR);
  playThrough(S, 0, 500);
  S.give('Announcer');
  playThrough(S, 500, 4500);
  S.give('Dantro');
  playThrough(S, 4500, 6500);
  const rec = store.begin({ title: 'Secret Council', doc: S.doc, episode: EP, ear: { sig: 'x', copy: 'u', place: 6500 } });
  rec.extras = S.names;
  return { backend, store, S, rec };
}
test('looking keeps nothing; a casting begun is a row that says how far it is', async () => {
  const { backend, store, rec } = await half();
  eq(await backend.keys('scripts/'), [], 'begin keeps nothing by itself');
  await store.keep(rec);
  const [row] = await store.list();
  eq([row.episode, row.ear, row.done, row.parts], [EP.id, { cast: 4, lines: 7 }, false, 2], 'the row');
  eq((await store.ofEpisode([EP.id])).id, rec.id, 'found by its episode');
  eq(await store.ofEpisode(['other']), null, 'and by no other');
  eq(await store.script(rec.id), null, 'no script before Done');
  const back = await store.get(rec.id);
  eq([O.castCount(back.doc), back.ear.place, back.episode], [{ cast: 4, lines: 7 }, 6500, EP], 'the page reads back what it kept');
});
test('Done on part of it is a script: carried lines are their part\'s, the rest directions, and casting goes on from it', async () => {
  const { store, rec } = await half();
  rec.doc = O.done(rec.doc, { keepOpen: true });
  rec.done = true;
  eq(await store.keep(rec), null, 'it may be kept');
  const s = await store.script(rec.id);
  eq(s.lines.map(l => l.role || l.kind), ['ANNOUNCER', 'ANNOUNCER', 'DANTRO', 'DANTRO', 'direction', 'direction', 'direction'], 'the lines');
  eq([s.source, s.episode, s.rights, s.kind], [{ name: 'Automatic transcript', url: EP.url }, EP.id, { bucket: 'own', evidence: [] }, 'own'], 'its source is the episode');
  eq(O.refusalOf(s), null, 'the reader and the recorder can read it');
  ok(!JSON.stringify(s).includes('"at"'), 'no time is in the script: the broadcast is no cue');
  const [row] = await store.list();
  eq([row.done, row.ear], [true, { cast: 4, lines: 7 }], 'the row still says how far');
  // Taken up again: the same ids, the same carry.
  const back = await store.get(rec.id);
  const T = EAR.session({ doc: back.doc, names: back.extras });
  T.tick(8100, true);
  T.give('Patrol');
  playThrough(T, 8100, 14100);
  back.doc = T.doc;
  await store.keep(back);
  const again = await store.script(rec.id);
  eq(again.lines.map(l => [l.id, l.role || l.kind]).slice(3), [['L0004', 'DANTRO'], ['L0005', 'PATROL'], ['L0006', 'PATROL'], ['L0007', 'PATROL']], 'more of it cast later');
});
test('the parts page finishes one: marks become the lines\' own parts, left-out lines go, and it counts as any script', async () => {
  const { store, rec, S } = await half();
  S.leaveOut();
  rec.doc = O.done(O.settle(S.doc));
  rec.done = true;
  await store.keep(rec);
  const s = await store.script(rec.id);
  eq(s.lines.map(l => l.role || l.kind), ['ANNOUNCER', 'ANNOUNCER', 'DANTRO', 'direction', 'direction', 'direction'], 'the lines');
  const [row] = await store.list();
  eq([row.ear.cast === row.ear.lines, row.lines, row.open], [true, 6, 0], 'nothing is left to cast');
});
test('a half-cast transcript exports with its parts, its source and its episode', async () => {
  const { store, rec } = await half();
  await store.keep(rec);
  const [x] = await store.exportRows();
  eq([x.source, x.episode, x.lines.map(l => l.role || l.kind)], ['Automatic transcript', EP.id, ['ANNOUNCER', 'ANNOUNCER', 'DANTRO', 'DANTRO', 'open', 'open', 'open']], 'the export');
});

/* ---- The transcript's times, from archive.org ---- */

const TXT = 'https://archive.org/download/OTRR_Suspense_Singles/Suspense%20430223%20%2864-48%29.autogenerated.txt';
async function cuesWith(answer, url = TXT) {
  const asked = [];
  const was = globalThis.fetch;
  globalThis.fetch = async (u) => { asked.push(String(u)); return answer(); };
  try { return { got: await API.transcriptCues(url).then(c => c, e => e.kind || String(e)), asked }; } finally { globalThis.fetch = was; }
}
const answer = (status, body) => () => ({ ok: status === 200, status, text: async () => body });
test('the cues are read from /cors/, the only path a browser may, and only for a transcript we show', async () => {
  eq(API.cuesURL(TXT), 'https://archive.org/cors/OTRR_Suspense_Singles/Suspense%20430223%20%2864-48%29.autogenerated.vtt', 'the address');
  eq([API.cuesURL(null), API.cuesURL('https://archive.org/download/x/y.txt'), API.cuesURL('https://example.com/download/x/y.autogenerated.txt'), API.cuesURL('https://archive.org/download/y.autogenerated.txt')], [null, null, null, null], 'nothing else has one');
  const none = await cuesWith(answer(200, VTT), 'https://example.com/a.autogenerated.txt');
  eq([none.got, none.asked], ['missing', []], 'and nothing else is asked for');
});
test('no times, no door: each answer that is not a transcript is a refusal, and a failure is asked for again', async () => {
  eq((await cuesWith(answer(404, ''))).got, 'missing', 'not there');
  eq((await cuesWith(answer(403, ''))).got, 'missing', 'not to be read');
  eq((await cuesWith(answer(200, '<html>busy</html>'))).got, 'missing', 'a page, not a transcript');
  eq((await cuesWith(answer(200, 'words with no times'))).got, 'missing', 'words with no times');
  eq((await cuesWith(answer(503, ''))).got, 'error', 'busy');
  eq((await cuesWith(() => { throw new TypeError('Failed to fetch'); })).got, 'error', 'the fetch refused');
  const good = await cuesWith(answer(200, VTT));
  eq([good.got.length, good.asked.length], [6, 1], 'then read, its failures not kept');
  eq((await cuesWith(answer(404, ''))).asked.length, 0, 'and read once');
});

/* ---- The player, held to one episode ---- */

function boot() {
  const on = {};
  const audio = { paused: true, ended: false, currentTime: 0, duration: 600, volume: 1, muted: true, playbackRate: 1, defaultPlaybackRate: 1, src: '', error: null,
    addEventListener(t, fn) { (on[t] ||= []).push(fn); }, fire(t) { (on[t] || []).slice().forEach(f => f()); },
    play() { this.paused = false; this.fire('play'); return Promise.resolve(); }, pause() { if (!this.paused) { this.paused = true; this.fire('pause'); } } };
  const kept = {};
  const ctx = vm.createContext({ console, Math, Number, Date, JSON, Object, Promise, Set, Map, URL, URLSearchParams, setInterval: () => ({ unref() {} }), clearInterval() {}, setTimeout, clearTimeout,
    location: { href: 'http://localhost/' }, document: { getElementById: () => audio, documentElement: { classList: { contains: () => false } }, addEventListener() {} }, window: { addEventListener() {} }, navigator: {},
    localStorage: { getItem: k => (k in kept ? kept[k] : null), setItem: (k, v) => { kept[k] = String(v); } } });
  for (const f of ['api.js', 'store.js', 'player.js']) vm.runInContext(read(f), ctx, { filename: f });
  vm.runInContext('globalThis.Player = Player; globalThis.Store = Store;', ctx);
  ctx.Player.setArcSource(() => null);
  return { audio, Player: ctx.Player, Store: ctx.Store };
}
const card = (id) => ({ id, title: id, series: 's', seriesName: 'S', url: `https://archive.org/download/x/${id}.mp3` });
test('held, the player keeps a page\'s speed and never the person\'s, and its end starts nothing', () => {
  const { audio, Player, Store } = boot();
  Player.setRate(1.25);
  Store.enqueue(card('next'));
  Player.hold(0.75);
  Player.load(card('now'));
  audio.fire('loadedmetadata');
  eq([audio.playbackRate, Store.rate(), Player.held], [0.75, 1.25, true], 'the page\'s speed, through a load');
  audio.ended = true;
  audio.fire('ended');
  eq(Player.current.id, 'now', 'the end of the episode starts nothing queued');
  audio.ended = false;
  Player.release();
  eq([audio.playbackRate, Player.held], [1.25, false], 'let go, it is the person\'s speed');
  audio.ended = true;
  audio.fire('ended');
  eq(Player.current.id, 'next', 'and the queue goes on');
});
test('following: a scroll stops it, Back to the line starts it again (the reader\'s own seam)', () => {
  const f = ReaderCore.alongFollow();
  f.line(4);
  eq([f.following, f.away(), f.following], [true, { turn: false, back: true }, false], 'away');
  eq([f.line(5), f.back(), f.following], [{ turn: false, back: true }, 5, true], 'and back, to the line being said now');
});
test('no file here proposes a speaker, makes a sound, or sends anything', () => {
  for (const f of ['ear-core.js', 'ear-ui.js']) {
    const src = read(f).replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
    for (const word of ['new Audio(', 'createMediaElementSource', 'AnalyserNode', 'createAnalyser', 'getUserMedia', 'fetch(', 'XMLHttpRequest', 'sendBeacon', 'workers.dev', 'API.plays', 'PlaysShare', 'publish'])
      ok(!src.includes(word), `${f} has ${word}`);
  }
});

(async () => {
  for (const [name, fn] of results) {
    const before = failures;
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: ${e.stack}`); }
    console.log(`  ${failures === before ? 'ok' : 'FAIL'}  ${name}`);
  }
  console.log(failures ? `FAIL: ${failures} of ${passes + failures}` : `ok: ${passes} passed, 0 failed (${MUTANTS.length} mutants)`);
  process.exit(failures ? 1 : 0);
})();
