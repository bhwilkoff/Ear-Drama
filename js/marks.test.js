/**
 * Marks in the script reader (PLAYS-DESIGN §2.10, WEB-DESIGN §4.16 item 15; Decision 076 S5), run
 * against the SHIPPED js/plays-core.js, js/reader-core.js and js/marks-core.js: the golden cases every
 * stack runs (catalog/tests/golden/marks_anchor.json: snapping to words, a point mark's place, and
 * re-anchoring a revision), the offsets every drawn run keeps into the line's words (through layoutOf,
 * with emphasis, verse and run-in speakers), the overlap rules, groups, storage under the script id,
 * and the export rows.
 *   node js/marks.test.js
 *
 * Seen to fail, 2026-11-15: before js/marks-core.js existed (every case), and against mutated copies:
 * place() without the evidence floor (the short word is guessed into another line), bestIn() without
 * the context score (the second "no" lands on the first), add() merging without the touching rule
 * (`<` for `<=`: adjacent highlights stay two), layoutOf's verse rows without `at += lead` (the verse
 * offsets case over the bundle's verse plays), and remove() ignoring the group.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.resolve(__dirname, '..');
for (const f of ['plays-core.js', 'reader-core.js', 'marks-core.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
}
const C = vm.runInThisContext('PlaysCore');
const R = vm.runInThisContext('ReaderCore');
const M = vm.runInThisContext('MarksCore');

let passes = 0, failures = 0;
function test(name, fn) {
  try { fn(); passes += 1; console.log(`  ok    ${name}`); }
  catch (e) { failures += 1; console.log(`  FAIL  ${name}\n        ${e.message}`); }
}
function eq(a, b, msg) {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}: got ${x}, want ${y}`);
}
function ok(v, msg) { if (!v) throw new Error(msg); }

const golden = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'tests', 'golden', 'marks_anchor.json'), 'utf8'));
const bundle = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json'), 'utf8')).scripts;
const LIB = path.join(ROOT, 'catalog', 'out', 'plays-library');
const libIndex = fs.existsSync(path.join(LIB, 'index.json')) ? JSON.parse(fs.readFileSync(path.join(LIB, 'index.json'), 'utf8')) : null;
/** Up to `n` library scripts spread across the index (none when the library is not built here). */
function libraryScripts(n) {
  if (!libIndex) return [];
  const rows = libIndex.plays;
  const step = Math.max(1, Math.floor(rows.length / n));
  const out = [];
  for (let i = 0; i < rows.length && out.length < n; i += step) out.push(JSON.parse(fs.readFileSync(path.join(LIB, rows[i].path), 'utf8')).scripts[0]);
  return out;
}

/* ---- The golden cases (every stack) ---- */

test('golden: a selection grows to whole words, and space alone is nothing', () => {
  for (const c of golden.snap) {
    const w = M.snapWords(c.text, c.start, c.end);
    eq(w ? [w.start, w.end] : null, c.want, `snap ${JSON.stringify(c.text)} [${c.start}, ${c.end})`);
  }
});

test('golden: a point mark goes after its word and the punctuation that follows', () => {
  for (const c of golden.point) eq(M.pointAfter(c.text, c.end), c.want, `point ${JSON.stringify(c.text)} at ${c.end}`);
});

test('golden: re-anchoring a revision (same line, a split id, context, lost, nearest line)', () => {
  ok(golden.anchor.length >= 8, 'the golden file has its anchor cases');
  for (const c of golden.anchor) {
    const before = { id: 's', ...c.before }, after = { id: 's', ...c.after };
    const m = M.make(before, c.mark.line, c.mark.start, c.mark.end, c.mark.kind, {}, 1000);
    ok(m, `${c.name}: made`);
    const r = M.place(after, [m]);
    if (c.want === 'lost') {
      eq(r.placed.length, 0, `${c.name}: not placed`);
      eq(r.lost, [m], `${c.name}: kept exactly as stored`);
    } else {
      eq(r.lost.length, 0, `${c.name}: placed`);
      const p = r.placed[0];
      eq([p.line, p.start, p.end], c.want, c.name);
      eq(C.lineText(after.lines.find(l => l.id === p.line)).slice(p.start, p.end), m.text, `${c.name}: still the same words`);
      eq(p.revision, after.revision, `${c.name}: takes the new revision`);
    }
  }
});

/* ---- Offsets: every drawn run maps back into lineText ---- */

const same = (a, b) => a.replace(/[\s ]/g, ' ') === b.replace(/[\s ]/g, ' ');
/** Every run layoutOf draws, with the line's words it claims: [{ at, text }]. */
function drawn(line, roles) {
  if (line.kind !== 'speech') return R.layoutOf(line, roles).rows.flatMap(r => r.runs);
  const lay = R.layoutOf(line, roles);
  return lay.speeches.flatMap(s => [...(s.name ? [s.name] : []), ...s.rows.flatMap(r => r.runs)]);
}
function checkOffsets(script, tag) {
  const roles = (script.roles || []).map(r => r.name);
  let runs = 0;
  for (const line of script.lines) {
    const lt = C.lineText(line);
    for (const r of drawn(line, roles)) {
      runs += 1;
      const claimed = lt.slice(r.at, r.at + r.text.length);
      if (!same(claimed, r.text)) throw new Error(`${tag} ${line.id}: a run at ${r.at} draws ${JSON.stringify(r.text)} but the line holds ${JSON.stringify(claimed)}`);
    }
  }
  return runs;
}

test('offsets: every run layoutOf draws over every bundled script maps back into lineText', () => {
  let n = 0;
  for (const s of bundle) n += checkOffsets(s, s.id);
  ok(n > 5000, `runs checked (${n})`);
});

test('offsets: verse rows (printed breaks kept, an indented half-line) keep their offsets', () => {
  const verse = [];
  for (const s of bundle) for (const l of s.lines) if (l.kind === 'speech' && R.layoutOf(l, []).verse && /\n\s{2,}\S/.test(C.lineText(l))) verse.push([s, l]);
  const fixture = { id: 'v', roles: [{ name: 'CAPTAIN' }], lines: [{ id: 'L0001', kind: 'speech', role: 'CAPTAIN', parts: [
    { say: 'Doubtful it stood;\nAs two spent swimmers, that do cling together\n    And choke their art.' }] }] };
  ok(R.layoutOf(fixture.lines[0], ['CAPTAIN']).verse, 'the fixture is verse');
  checkOffsets(fixture, 'fixture');
  const rows = R.layoutOf(fixture.lines[0], ['CAPTAIN']).speeches[0].rows;
  eq(rows.map(r => r.indent), [false, false, true], 'the printed indent is kept as a row');
  for (const [s, l] of verse.slice(0, 200)) checkOffsets({ ...s, lines: [l] }, s.id);
  ok(bundle.some(s => s.lines.some(l => l.kind === 'speech' && R.layoutOf(l, []).verse)), 'the bundle holds verse');
});

test('offsets: emphasis (catalog em, and a short italic direction between said words) and a run-in speaker', () => {
  const s = { id: 'e', roles: [{ name: 'CHARTERIS' }, { name: 'GRACE' }], lines: [
    { id: 'L0001', kind: 'speech', role: 'CHARTERIS', parts: [{ say: 'It is the first in which' }, { direction: 'I' }, { say: 'have been serious.' }] },
    { id: 'L0002', kind: 'speech', role: 'CHARTERIS', em: [1], parts: [{ say: 'I believe it' }, { say: 'is' }, { say: 'a very pleasant state.' }] },
    { id: 'L0003', kind: 'speech', role: 'CHARTERIS', parts: [{ say: 'Of course. Why not?\nGRACE' }, { direction: 'reflecting' }, { say: '. Never mind _why_.' }] },
  ] };
  checkOffsets(s, 'fixture');
  const l3 = R.layoutOf(s.lines[2], ['CHARTERIS', 'GRACE']);
  eq(l3.speeches.map(x => x.role), ['CHARTERIS', 'GRACE'], 'the run-in speech is attributed');
  const em = drawn(s.lines[2], ['CHARTERIS', 'GRACE']).find(r => r.kind === 'em');
  eq(C.lineText(s.lines[2]).slice(em.at, em.at + em.text.length), 'why', 'the italic word keeps its offset (its marks not drawn)');
  for (const lib of libraryScripts(30)) checkOffsets(lib, lib.id);
});

/* ---- Making marks from a selection ---- */

const play = { id: 'gut-test', revision: 'r1', title: 'Test', lines: [
  { id: 'L0001', kind: 'speech', role: 'A', parts: [{ say: 'Yes--the first thing tomorrow morning, and then we go.' }] },
  { id: 'L0002', kind: 'direction', source: '[He crosses to the window.]' },
  { id: 'L0003', kind: 'speech', role: 'B', parts: [{ say: 'It is cold out there.' }] },
] };
const t1 = C.lineText(play.lines[0]);

test('a selection: span marks grow to words, a point mark goes after the last word, a note anchors to its first line', () => {
  const [h] = M.fromSelection(play, [{ line: 'L0001', start: 11, end: 17 }], 'highlight', { hue: 'green' }, 5);
  eq([h.start, h.end, h.text, h.hue, h.revision], [9, 20, 'first thing', 'green', 'r1'], 'grown to whole words, its hue and revision');
  eq(h.prefix, 'Yes--the ', 'the context before');
  eq(h.suffix, t1.slice(20, 52), 'up to 32 characters after');
  const [b] = M.fromSelection(play, [{ line: 'L0001', start: 30, end: 33 }], 'breath', {}, 5);
  eq([b.start, b.end, b.text], [38, 38, ''], 'a breath after "morning,"');
  const across = [{ line: 'L0001', start: 47, end: t1.length }, { line: 'L0002', start: 0, end: 10 }, { line: 'L0003', start: 0, end: 5 }];
  const hs = M.fromSelection(play, across, 'underline', {}, 5);
  eq(hs.map(m => m.line), ['L0001', 'L0002', 'L0003'], 'one mark per line');
  ok(hs[0].group && hs.every(m => m.group === hs[0].group), 'one group');
  const ns = M.fromSelection(play, across, 'note', { note: 'warm' }, 5);
  eq(ns.map(m => [m.line, m.note, m.group]), [['L0001', 'warm', undefined]], 'a note: its first line, no group');
  const [p] = M.fromSelection(play, across, 'pause', {}, 5);
  eq([p.line, p.start], ['L0003', 5], 'a pause after the last piece\'s word');
  const [beat] = M.fromSelection(play, [{ line: 'L0003', start: 0, end: 2 }], 'beat', { label: '  the turn, a long label past the limit ' }, 5);
  eq(beat.label, 'the turn, a long label p', 'a beat label trimmed to 24 characters');
  eq(M.fromSelection(play, [{ line: 'L0001', start: 8, end: 9 }], 'highlight'), [], 'a space alone makes nothing');
  eq(M.fromSelection(play, [{ line: 'L9999', start: 0, end: 3 }], 'highlight'), [], 'a line not in the script makes nothing');
});

/* ---- Overlap ---- */

test('overlap: highlights merge (overlapping or touching) into one in the new hue; notes never merge', () => {
  let ms = [];
  ms = M.add(play, ms, M.make(play, 'L0001', 9, 14, 'highlight', { hue: 'yellow' }));
  ms = M.add(play, ms, M.make(play, 'L0001', 21, 29, 'highlight', { hue: 'blue' }));
  ms = M.add(play, ms, M.make(play, 'L0001', 12, 20, 'highlight', { hue: 'pink' }));
  eq(M.order(play, ms).filter(m => m.kind === 'highlight').map(m => [m.start, m.end, m.hue]), [[9, 20, 'pink'], [21, 29, 'blue']], 'the overlap merged; the separate one stayed');
  eq(ms.find(m => m.hue === 'pink').text, t1.slice(9, 20), 'the merged quote is re-read');
  ms = M.add(play, ms, M.make(play, 'L0001', 20, 21, 'highlight', { hue: 'green' }));
  eq(ms.filter(m => m.kind === 'highlight').map(m => [m.start, m.end, m.hue]), [[9, 29, 'green']], 'touching both: one highlight over all, in the new hue');
  ms = M.add(play, ms, M.make(play, 'L0001', 9, 14, 'underline'));
  ms = M.add(play, ms, M.make(play, 'L0001', 14, 20, 'underline'));
  eq(ms.filter(m => m.kind === 'underline').map(m => [m.start, m.end]), [[9, 20]], 'touching underlines merge');
  eq(ms.filter(m => m.kind === 'highlight').length, 1, 'a highlight and an underline share words');
  ms = M.add(play, ms, M.make(play, 'L0001', 9, 14, 'note', { note: 'a' }));
  ms = M.add(play, ms, M.make(play, 'L0001', 9, 14, 'note', { note: 'b' }));
  eq(ms.filter(m => m.kind === 'note').length, 2, 'two notes on the same words stay two');
  ms = M.add(play, ms, M.make(play, 'L0003', 0, 2, 'highlight'));
  eq(ms.filter(m => m.kind === 'highlight').length, 2, 'another line never merges');
});

test('overlap: one point mark a place (a pause replaces a breath); a breath elsewhere stays', () => {
  let ms = [];
  ms = M.add(play, ms, M.make(play, 'L0001', 38, 38, 'breath'));
  ms = M.add(play, ms, M.make(play, 'L0001', 47, 47, 'breath'));
  ms = M.add(play, ms, M.make(play, 'L0001', 9, 20, 'highlight'));
  ms = M.add(play, ms, M.make(play, 'L0001', 38, 38, 'pause'));
  eq(ms.filter(m => !M.SPAN.has(m.kind)).map(m => [m.kind, m.start]).sort(), [['breath', 47], ['pause', 38]], 'replaced in place');
  ms = M.add(play, ms, M.make(play, 'L0001', 38, 38, 'beat', { label: 'turn' }));
  eq(ms.filter(m => m.start === 38 && !M.SPAN.has(m.kind)).map(m => [m.kind, m.label]), [['beat', 'turn']], 'a beat replaces the pause');
  eq(ms.filter(m => m.kind === 'highlight').length, 1, 'span marks untouched');
});

test('remove and update: a group goes together, a hue changes for the group, undo restores what was removed', () => {
  const across = [{ line: 'L0001', start: 47, end: t1.length }, { line: 'L0003', start: 0, end: 5 }];
  let ms = M.fromSelection(play, across, 'highlight', { hue: 'yellow' }).reduce((a, m) => M.add(play, a, m), []);
  ms = M.add(play, ms, M.make(play, 'L0002', 1, 3, 'highlight'));
  ms = M.update(ms, ms[0].id, { hue: 'blue' });
  eq(ms.map(m => m.hue), ['blue', 'blue', 'yellow'], 'the group took the hue; the other did not');
  const r = M.remove(ms, ms[1].id);
  eq(r.marks.length, 1, 'both of the group removed');
  eq(r.removed.length, 2, 'what was removed is returned, for Undo');
  eq([...r.marks, ...r.removed].length, 3, 'undo puts them back');
  let n = [M.make(play, 'L0003', 0, 2, 'note', { note: 'x' }), M.make(play, 'L0003', 0, 2, 'beat', { label: 'a' })];
  n = M.update(n, n[0].id, { note: 'cold, say it cold' });
  n = M.update(n, n[1].id, { label: 'shift' });
  eq(n.map(m => m.note ?? m.label), ['cold, say it cold', 'shift'], 'a note and a label change');
});

test('a tap on words: the narrowest span mark under the offset, a note first', () => {
  const ms = [M.make(play, 'L0001', 0, 40, 'highlight'), M.make(play, 'L0001', 9, 20, 'underline'), M.make(play, 'L0001', 9, 20, 'note'), M.make(play, 'L0001', 38, 38, 'breath')];
  eq(M.at(ms, 'L0001', 10).map(m => m.kind), ['note', 'underline', 'highlight'], 'narrowest first, a note before an equal underline');
  eq(M.at(ms, 'L0001', 38).map(m => m.kind), ['highlight'], 'a point mark is not a span');
  eq(M.at(ms, 'L0003', 1), [], 'another line');
});

test('the notebook order: script order (line, then offset), lost marks apart', () => {
  const ms = [M.make(play, 'L0003', 3, 5, 'underline'), M.make(play, 'L0001', 38, 38, 'breath'), M.make(play, 'L0001', 9, 20, 'highlight'), M.make(play, 'L0002', 1, 3, 'note')];
  eq(M.order(play, ms).map(m => `${m.line}:${m.start}`), ['L0001:9', 'L0001:38', 'L0002:1', 'L0003:3'], 'in reading order');
  const next = { ...play, revision: 'r2', lines: [play.lines[0], { id: 'L0003', kind: 'speech', role: 'B', parts: [{ say: 'Warm in here.' }] }] };
  const r = M.place(next, ms);
  eq(r.placed.map(m => m.kind).sort(), ['breath', 'highlight'], 'the first line\'s marks placed');
  eq(r.lost.map(m => m.line).sort(), ['L0002', 'L0003'], 'the others kept as not placed, untouched');
  ok(r.changed, 'the placed marks took the new revision');
  const again = M.place(next, r.placed);
  ok(!again.changed && again.lost.length === 0, 'placing again changes nothing');
});

test('re-anchoring over a real script: marks on many lines survive the same text under a new revision, and a split line', () => {
  const s = bundle.find(x => x.lines.length > 300);
  const ms = [];
  for (let i = 5; i < s.lines.length; i += 37) {
    const lt = C.lineText(s.lines[i]);
    const w = M.snapWords(lt, Math.floor(lt.length / 3), Math.floor(lt.length / 3) + 6);
    if (w) ms.push(M.make(s, s.lines[i].id, w.start, w.end, 'highlight'));
  }
  ok(ms.length > 5, `marks made (${ms.length})`);
  const next = { ...s, revision: `${s.revision}-next` };
  const r = M.place(next, ms);
  eq(r.lost.length, 0, 'none lost when only the revision changed');
  eq(r.placed.map(m => [m.line, m.start]), ms.map(m => [m.line, m.start]), 'each where it was');
  // Split one marked line in two (the run-in fix's shape): its words move to the new `a` id.
  const target = ms[2];
  const k = s.lines.findIndex(l => l.id === target.line);
  const lt = C.lineText(s.lines[k]);
  const cut = target.start;
  const split = { ...s, revision: 'split', lines: [...s.lines.slice(0, k),
    { id: target.line, kind: 'direction', source: lt.slice(0, cut).trim() || '[...]' },
    { id: `${target.line}a`, kind: 'direction', source: lt.slice(cut) }, ...s.lines.slice(k + 1)] };
  const r2 = M.place(split, [target]);
  eq(r2.placed.map(m => [m.line, m.start, m.text]), [[`${target.line}a`, 0, target.text]], 'the mark followed its words to the split id');
});

/* ---- On the device ---- */

function fakeStorage(fail = false) {
  const mem = new Map();
  return {
    get length() { return mem.size; },
    key: (i) => [...mem.keys()][i] ?? null,
    getItem: (k) => (mem.has(k) ? mem.get(k) : null),
    setItem: (k, v) => { if (fail) throw new Error('QuotaExceededError'); mem.set(k, String(v)); },
    removeItem: (k) => { mem.delete(k); },
    mem,
  };
}

test('storage: one key per script, unreadable or blocked storage reads as none, a failed write says false', () => {
  const st = fakeStorage();
  const ms = [M.make(play, 'L0001', 9, 20, 'highlight', { hue: 'blue' }, 1700000000000), M.make(play, 'L0003', 0, 2, 'note', { note: 'cold' }, 1700000000000)];
  ok(M.save(st, play, ms), 'saved');
  ok(st.mem.has('ed.marks.gut-test'), 'under ed.marks.<script id>');
  eq(M.load(st, 'gut-test'), ms, 'loaded back');
  eq(M.load(st, 'other'), [], 'another script has none');
  st.mem.set('ed.marks.bad', '{not json');
  eq(M.load(st, 'bad'), [], 'unreadable: none');
  st.mem.set('ed.marks.junk', JSON.stringify({ marks: [{ id: 'x', kind: 'scribble', line: 'L1', start: 0, end: 1, text: 'a' }, ms[0]] }));
  eq(M.load(st, 'junk').length, 1, 'a mark of an unknown kind is dropped on read');
  ok(!M.save(fakeStorage(true), play, ms), 'a full or blocked store says false');
  eq(M.load({ getItem() { throw new Error('SecurityError'); } }, 'gut-test'), [], 'blocked storage reads as none');
  ok(M.save(st, play, []) && !st.mem.has('ed.marks.gut-test'), 'no marks: the key is removed');
  eq(M.prefs(st), { show: true, hue: 'yellow' }, 'prefs default: shown, yellow');
  M.savePrefs(st, { show: false, hue: 'pink' });
  eq(M.prefs(st), { show: false, hue: 'pink' }, 'prefs kept');
});

test('export rows: every play\'s marks with the script and its title, never the prefs', () => {
  const st = fakeStorage();
  M.save(st, play, [M.make(play, 'L0001', 9, 20, 'highlight', { hue: 'blue' }, Date.parse('2026-11-15T12:00:00Z'))]);
  M.save(st, { ...play, id: 'gut-2', title: 'Two' }, [M.make({ ...play, id: 'gut-2' }, 'L0003', 0, 2, 'note', { note: 'cold' }, Date.parse('2026-11-15T12:00:00Z'))]);
  M.savePrefs(st, { show: true, hue: 'yellow' });
  const rows = M.exportRows(st);
  eq(rows.map(r => [r.script, r.title, r.kind, r.text, r.hue, r.note]), [['gut-2', 'Two', 'note', 'It', null, 'cold'], ['gut-test', 'Test', 'highlight', 'first thing', 'blue', null]], 'two plays, sorted by key');
  eq(rows[0].created, '2026-11-15T12:00:00.000Z', 'times as ISO 8601');
  eq(M.exportRows({ get length() { throw new Error('blocked'); } }), [], 'blocked storage exports nothing');
});

console.log(`\n${failures ? 'FAIL' : 'PASS'}: ${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
