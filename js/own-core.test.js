/**
 * Own scripts (R4-1, Decision 088.3) against the SHIPPED js/own-core.js: the golden cases every stack
 * runs (catalog/tests/golden/own_script_parse.json, own_script_ops.json, ear_cast_lines.json), each
 * file's control and a mutant of the core that must fail it, no word lost from any pasted text, the
 * catalog's own revisions recomputed, the script shape read by plays-core and the Worker's rules, real
 * plays printed in six layouts and read back, the caps, hostile texts, and 400 KB in under 100 ms.
 *   node js/own-core.test.js
 *
 * Seen to fail, 2026-11-24: every mutant in MUTANTS (each names the golden it breaks), the three
 * controls, the 100 ms case before couldEnd (120 ms), and six layouts before a name printed once was read.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { pathToFileURL } = require('node:url');

const ROOT = path.resolve(__dirname, '..');
const SOURCE = fs.readFileSync(path.join(__dirname, 'own-core.js'), 'utf8');
vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'plays-core.js'), 'utf8'), { filename: 'plays-core.js' });
const C = vm.runInThisContext('PlaysCore');
const load = (source) => vm.runInThisContext(`(() => { ${source}\nreturn OwnCore; })()`);
const CORE = load(SOURCE);
const golden = (f) => JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'tests', 'golden', f), 'utf8'));
const G = { parse: golden('own_script_parse.json'), ops: golden('own_script_ops.json'), ear: golden('ear_cast_lines.json') };
const ID = G.ops.scripts[0].want.id;

let passes = 0, failures = 0;
const tests = [];
const test = (name, fn) => tests.push([name, fn]);
function eq(a, b, msg) {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}: got ${x}, want ${y}`);
}
function ok(v, msg) { if (!v) throw new Error(msg); }
/** Key order is not part of a golden. */
const sorted = (v) => (Array.isArray(v) ? v.map(sorted)
  : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sorted(v[k])])) : v);
const same = (a, b, msg) => eq(sorted(a), sorted(b), msg);

/* ---- The golden runners: each takes a core, so a mutant runs them too ---- */

const lineOut = (l) => ({ kind: l.kind, ...(l.role ? { role: l.role } : {}), text: l.text, ...(l.label ? { label: l.label } : {}) });

function runParseCase(O, c) {
  const r = O.parse(c.raw);
  same({ lines: r.lines.map(lineOut), parts: r.parts }, c.want, `${c.layout}: ${c.name}`);
}
function runParse(O) {
  for (const c of G.parse.normalize) eq(O.normalize(c.raw), c.want, `normalize ${c.name}`);
  for (const c of G.parse.names) { const n = O.partName(c.raw); eq([n, O.partNameRefusal(n)], [c.name, c.refusal], `name ${JSON.stringify(c.raw)}`); }
  for (const c of G.parse.pieces) eq(O.pieces(c.text), c.parts, `pieces of ${JSON.stringify(c.text)}`);
  for (const c of G.parse.cases) runParseCase(O, c);
}

function runSequence(O, c) {
  let doc = O.newDoc(c.lines);
  const refusals = [];
  for (const s of c.steps) {
    if (s.op === 'done') { doc = O.done(doc, { keepOpen: !!s.keepOpen }); refusals.push(null); continue; }
    const before = JSON.stringify(doc);
    const r = O.apply(doc, s, s.env || {});
    eq(JSON.stringify(doc), before, `${c.name}: the doc given is not changed`);
    doc = r.doc;
    refusals.push(r.refusal);
  }
  same({ refusals, letters: doc.letters, undo: doc.undo.length, lines: doc.lines.map(l => ({ k: l.k, id: l.id, ...lineOut(l) })) }, c.want, c.name);
}
async function runOps(O) {
  for (const c of G.ops.sequences) runSequence(O, c);
  for (const c of G.ops.cut) eq(O.cutAt(c.text, c.at), c.want, `cut ${JSON.stringify(c.text)} at ${c.at}`);
  for (const c of G.ops.wordsChanged) eq(O.wordsChanged(c.before, c.after), c.want, `words changed ${JSON.stringify(c)}`);
  for (const c of G.ops.nearest) {
    const lines = [...c.roles].map(r => (r === '.' ? { kind: 'open', role: null, text: 'x' } : { kind: 'speech', role: r, text: 'x' }));
    eq(O.nearestParts(lines, c.at), c.want, `nearest in ${c.roles} at ${c.at}`);
  }
  const w = G.ops.letters;
  let doc = O.done(O.newDoc([{ kind: 'speech', role: 'A', text: w.text }]));
  for (let i = 0; i < w.splits; i++) {
    const t = doc.lines.find(l => l.k === 1).text;
    doc = O.apply(doc, { op: 'split', line: 1, at: t.lastIndexOf(' ') + 1 }).doc;
  }
  eq(doc.lines.map(l => l.id), w.want, 'letters past z');
  for (const c of G.ops.canonical) {
    eq(O.canonicalLines(c.lines), c.json, 'canonical JSON');
    eq(await O.revisionOf(c.lines), c.revision, 'revision');
  }
  for (const c of G.ops.scripts) {
    let d = O.newDoc(O.parse(c.raw).lines);
    for (const s of c.steps) d = O.apply(d, s).doc;
    const s = await O.seal(O.toScript(O.done(d), { id: c.want.id, title: c.title }));
    same(s, c.want, c.name);
    eq(O.refusalOf(s), c.refusal, `${c.name}: may be kept`);
  }
  for (const c of G.ops.refusals) eq(O.refusalOf(c.script), c.want, `refusal: ${c.name}`);
}

const castOut = (O, d) => { const m = O.castOf(d); return d.lines.map(l => { const w = m.get(l.k); return w === O.OUT ? { out: true } : w === null ? null : { role: w }; }); };
function runCast(O, c) {
  let d = O.fromCues(O.parseCues(G.ear.vtt));
  const refusals = [];
  for (const s of c.steps) {
    let r = { doc: d, refusal: null };
    if (s.hear !== undefined) r.doc = O.hear(d, s.hear, s.from);
    else if (s.tap !== undefined) r = O.tap(d, s.tap, s.out ? { out: true } : { role: s.role }, s.env || {});
    else if (s.leaveOut !== undefined) r = O.leaveOutHeard(d, s.leaveOut, s.env || {});
    else if (s.undo) r = O.apply(d, { op: 'undo' });
    else if (s.done) r.doc = O.done(d, { keepOpen: !!s.keepOpen });
    else r = O.apply(d, s, s.env || {});
    d = r.doc;
    refusals.push(r.refusal);
  }
  const settled = O.settle(d).lines.map(l => ({ k: l.k, kind: l.kind, ...(l.role ? { role: l.role } : {}), text: l.text, at: l.at }));
  same({ refusals, cast: castOut(O, d), count: O.castCount(d), settled }, c.want, c.name);
}
async function runEar(O) {
  const E = G.ear;
  for (const c of E.cues) same(O.parseCues(c.raw), c.want, `cues: ${c.name}`);
  for (const c of E.sentences) eq(O.fromCues([{ text: c.text, at: null }]).lines.map(l => l.text), c.want, `sentences of ${JSON.stringify(c.text)}`);
  for (const c of E.times) eq(O.fromCues([c.cue]).lines.map(l => ({ text: l.text, at: l.at })), c.want, `times: ${c.name}`);
  const d = O.fromCues(O.parseCues(E.vtt));
  eq(d.lines.map(l => ({ k: l.k, text: l.text, at: l.at })), E.lines, 'the lines of the transcript');
  for (const c of E.lineAt) eq(O.lineAt(d, c.ms), c.want, `the line at ${c.ms}`);
  for (const c of E.casts) runCast(O, c);
  let s = O.hear(O.tap(d, 1, { role: 'Dantro' }).doc, 3, 1);
  s = O.hear(O.tap(s, 4, { role: 'Pat' }).doc, 6, 4);
  s = O.done(O.tap(s, 6, { out: true }).doc, { keepOpen: true });
  same(await O.seal(O.toScript(s, { id: ID, title: 'The Visit', episode: E.script.episode })), E.script.want, 'a half-cast transcript as a script');
}

test('golden: own_script_parse (every stack)', () => {
  ok(G.parse.cases.length >= 40, '40 pasted texts');
  ok(new Set(G.parse.cases.map(c => c.layout)).size >= 8, 'eight layouts');
  runParse(CORE);
});
test('golden: own_script_ops (every stack)', () => runOps(CORE));
test('golden: ear_cast_lines (every stack)', () => runEar(CORE));

async function fails(fn) { try { await fn(); return false; } catch { return true; } }
test('each golden file\'s control is found wrong', async () => {
  ok(await fails(() => runParseCase(CORE, G.parse.control)), 'own_script_parse control passed');
  ok(await fails(() => runSequence(CORE, G.ops.control)), 'own_script_ops control passed');
  ok(await fails(() => runCast(CORE, G.ear.control)), 'ear_cast_lines control passed');
});

/** [the golden it must fail, text in the core, what it becomes]. */
const MUTANTS = [
  ['parse', 'if (n >= 2) return true;', 'if (n >= 1) return true;'],
  ['parse', '(starting.get(m.key) || 0) >= 5', '(starting.get(m.key) || 0) >= 4'],
  ['parse', 'established[form] = names >= 2;', 'established[form] = false;'],
  ['parse', "out.normalize('NFC')", 'out'],
  ['parse', 'awaiting = m.bare;', 'awaiting = false;'],
  ['parse', 'const maybe = TITLES.has(last) ||', 'const maybe = false && TITLES.has(last) ||'],
  ['parse', 'if (numeral || COMMON.has(key)) return;', 'if (numeral) return;'],
  ['parse', 'caps && gap.length >= 3', 'caps && gap.length >= 4'],
  ['parse', '!(awaiting && !blank && !isCaps(x.name))', 'true'],
  ['parse', "const whole = p === s.length - 1 ||", 'const whole = true ||'],
  ['parse', 'resume = role;', 'resume = null;'],
  ['parse', 'if (asciiWord(u) ||', 'if (false ||'],
  ['parse', "(u === 95 && n === 1 && !inner)", '(u === 95 && !inner)'],
  ['parse', 'kept = []; off = true; started = false; cut = true;', 'kept = []; cut = true;'],
  ['parse', 'else if (off) continue;', ''],
  ['parse', '|| (started && m.startsWith(PRINT_START))', '|| m.startsWith(PRINT_START)'],
  ['parse', 'i = last;', ''],
  ['parse', 'return cut && trim(body) ? body : text;', 'return body;'],
  ['parse', 'else if (opens(m, PRINT_ENDS)) { kept = [];', 'else if (opens(m, PRINT_ENDS)) {'],
  ['ops', 'if (gone.some(taken)) return', 'if (taken(l)) return'],
  ['ops', 'lines.slice(0, i + 1));\n    }', 'lines.slice(0, i));\n    }'],
  ['ear', 'above ? holdCast(doc, lines.slice(i), 0)', 'above ? lines.slice(i)'],
  ['ops', 'lines: doc.undo[doc.undo.length - 1], undo', 'letters: {}, lines: doc.undo[doc.undo.length - 1], undo'],
  ['ops', 'const base = baseOf(above ? above.id : null);', 'const base = above ? above.id : null;'],
  ['ops', "if (taken(l)) return refuse(doc, 'line_has_take');\n    if (op.op === 'leaveOut')", "if (op.op === 'leaveOut')"],
  ['ops', "if (mine.some(taken)) return refuse(doc, 'part_has_take');", ''],
  ['ops', 'while (p > 0 && insideCharacter(text, p)) p -= 1;', ''],
  ['ops', 'Object.keys(v).sort()', 'Object.keys(v)'],
  ['ops', "if (env.shared) return refuse(doc, 'shared');\n    const lines = doc.lines;", 'const lines = doc.lines;'],
  ['ops', 'return out.toLowerCase();', 'return out;'],
  ['ear', 'if (ABBREVIATIONS.has(', 'if (false && ABBREVIATIONS.has('],
  ['ear', 'else if (!heard.has(l.k)) carry = null;', ''],
  ['ear', 'Math.floor(', 'Math.ceil('],
  ['ear', 'cut === n ? n : cut + 1', 'cut'],
  ['ear', 'out[i] = { ...l, mark:', 'out[i] = { ...l, notMark:'],
  ['ear', 'if (who === OUT) continue;', ''],
];
test('a mutant of every rule fails its golden', async () => {
  const run = { parse: runParse, ops: runOps, ear: runEar };
  for (const [which, from, to] of MUTANTS) {
    ok(SOURCE.split(from).length === 2, `the mutant's text is in the core once: ${from}`);
    const mutant = load(SOURCE.split(from).join(to));
    ok(await fails(() => run[which](mutant)), `${which} passed the mutant of: ${from}`);
  }
});

/* ---- Nothing is lost, nothing is written ---- */

const bare = (s) => [...s].filter(c => /[\p{L}\p{N}\p{M}]/u.test(c)).join('');
test('every letter and digit of every golden text is in its lines, in order, and no other', () => {
  for (const c of G.parse.cases) {
    const r = CORE.parse(c.raw);
    eq(bare(r.lines.map(l => (l.label || '') + l.text).join('')), bare(r.text), `${c.layout}: ${c.name}`);
  }
});
test('every row of a line is a slice of the normalized text', () => {
  for (const c of G.parse.cases) {
    const r = CORE.parse(c.raw);
    for (const l of r.lines) for (const row of l.text.split('\n').slice(1)) ok(r.text.includes(row), `${c.name}: ${JSON.stringify(row)}`);
  }
});
test('a lone surrogate is U+FFFD, and nothing throws on it', () => {
  eq(CORE.normalize('a\ud800b\udc00c\ud83d\ude00'), 'a\ufffdb\ufffdc\ud83d\ude00', 'normalize');
  eq(CORE.parse('A\ud800: x\nB: y\nA\ud800: z\nB: w').parts.length, 2, 'parse');
  eq(CORE.cutAt('x\ud800y', 1), 1, 'cut');
});
test('pieces and textOf are inverse over 20,000 made-up texts', () => {
  const al = ['a', 'B', ' ', '(', ')', '[', ']', '.', '\n', '\u00e9'];
  let seed = 7;
  const next = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
  for (let i = 0; i < 20000; i++) {
    let s = '';
    for (let j = 1 + next(14); j > 0; j--) s += al[next(al.length)];
    s = CORE.trim(s);
    if (s) eq(CORE.pieces(CORE.textOf(CORE.pieces(s))), CORE.pieces(s), JSON.stringify(s));
  }
});

/* ---- The shape the reader and the recorder read ---- */

const BUNDLE = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json'), 'utf8')).scripts;
test('the revision formula is the catalog\'s: every bundled play\'s recomputes', async () => {
  for (const s of BUNDLE) eq(await CORE.revisionOf(s.lines), s.revision, s.id);
});

const spokenOf = (s) => s.lines.filter(l => l.kind === 'speech').map(l => [l.role, C.spokenText(l)]);
const LAYOUTS = {
  colon: (r, t) => `${r}: ${t}`, dot: (r, t) => `${r}. ${t}`, over: (r, t) => `${r}\n${t}`, tab: (r, t) => `${r}\t${t}`,
  columns: (r, t) => `${r}    ${t}`, bold: (r, t) => `**${r}:** ${t}`,
};
test('the bundled plays, printed in six layouts, read back with the same parts', () => {
  const plain = /^[A-Z][A-Z' ]{2,20}$/;
  for (const [name, print] of Object.entries(LAYOUTS)) {
    let words = 0, right = 0;
    for (const s of BUNDLE) {
      const said = spokenOf(s).filter(([r, t]) => plain.test(r) && r.split(' ').length <= 4 && t.trim() && !/[([\])]/.test(t)).map(([r, t]) => [r, CORE.normalize(t.replace(/\n\s*\n/g, '\n'))]);
      const count = new Map();
      for (const [r] of said) count.set(r, (count.get(r) || 0) + 1);
      const kept = said.filter(([r]) => count.get(r) >= 2);
      const got = CORE.parse(kept.map(([r, t]) => print(r, t.split('\n').join(' '))).join('\n\n')).lines;
      kept.forEach(([r, t], i) => {
        const n = CORE.wordsOf(t).length;
        words += n;
        if (got[i] && got[i].role === CORE.partName(r)) right += n;
      });
    }
    ok(words > 100000, `${name}: ${words} words`);
    ok(right / words > 0.98, `${name}: ${(100 * right / words).toFixed(2)}% of ${words} words`);
  }
});

test('an own script reads in plays-core as a bundled one does', async () => {
  const raw = 'ACT I\n\nANNA: Is anyone there? (She knocks.)\n\nBEN: Only me.\n\nSOUND: A door.\n\nACT II\n\nANNA: Then who is singing?\n\nBEN: The pipes.\n\nNobody moved.';
  const s = await CORE.seal(CORE.toScript(CORE.done(CORE.newDoc(CORE.parse(raw).lines)), { id: ID, title: 'The Pipes' }));
  eq(CORE.refusalOf(s), null, 'may be kept');
  for (const k of ['id', 'revision', 'kind', 'title', 'authors', 'source', 'rights', 'roles', 'lines']) ok(k in s && k in BUNDLE[0], k);
  eq(Object.keys(s.source).sort(), Object.keys(BUNDLE[0].source).sort(), 'source');
  eq(Object.keys(s.roles[0]).sort(), Object.keys(BUNDLE[0].roles[0]).sort(), 'a role');
  eq(C.castParts(s).map(p => [p.id, p.lineCount]), [['role:ANNA', 2], ['role:BEN', 2], ['sound', 1], ['directions', 3]], 'cast sheet');
  eq(C.contentsOf(s).map(x => x.title), ['ACT I', 'ACT II'], 'contents');
  eq(C.spokenText(s.lines[1]), 'Is anyone there?', 'spoken words');
  eq(C.lineText(s.lines[1]), 'Is anyone there? She knocks.', 'lineText');
  eq(C.searchScript(s, 'knocks').total, 1, 'search');
  const p = C.newProduction(s);
  eq([p.scriptID, p.scriptRevision], [s.id, s.revision], 'a production of it');
});

test('a kept doc, and a copy of a script, go on where they were', async () => {
  let d = CORE.done(CORE.newDoc(CORE.parse('ANNA: One two.\nBEN: Three.\nANNA: Four.\nBEN: Five.').lines));
  d = CORE.apply(d, { op: 'split', line: 1, at: 4 }).doc;
  const again = JSON.parse(JSON.stringify(CORE.kept(d)));
  eq(CORE.apply(again, { op: 'split', line: 2, at: 1 }).refusal, null, 'kept: an op');
  eq(CORE.apply(again, { op: 'undo' }).refusal, 'nothing_to_undo', 'kept: no steps');
  eq(CORE.apply(again, { op: 'add', after: 1, kind: 'sound', text: 'x' }).doc.lines[1].id, 'L0001b', 'kept: the next letter');
  const s = CORE.toScript(d, { id: ID, title: 'T' });
  const copy = CORE.fromScript(s);
  eq(CORE.apply(copy, { op: 'add', after: 1, kind: 'sound', text: 'x' }).doc.lines[1].id, 'L0001b', 'copy: the next letter');
  same(CORE.toScript(copy, { id: ID, title: 'T' }), s, 'copy: the same script');
});

/* ---- Caps, and the Worker's ---- */

test('the caps are the Worker\'s, or inside them', async () => {
  const worker = (f) => import(pathToFileURL(path.join(ROOT, 'worker', 'src', f)).href);
  const names = await worker('plays-names.js');
  const relay = await worker('plays-relay.js');
  const manifest = await worker('plays-manifest.js');
  eq(CORE.MAX_PART_NAME, names.MAX_NAME, 'a part\'s name');
  ok(CORE.MAX_LINES <= relay.MAX_LINES, 'lines');
  ok(!manifest.SCRIPT_ID.test(ID), 'a catalog id is never an own id');
  ok(BUNDLE.every(s => !CORE.OWN_ID.test(s.id)), 'and the other way');
  for (const c of G.parse.names) if (c.refusal === null) ok(!['too_long', 'name_too_long', 'bad_name'].includes(names.nameRefusal(c.name)), `the Worker takes ${c.name}`);
  for (const c of G.ops.scripts) ok(relay.parseCast(c.want.lines.map(l => ({ id: l.id, part: C.linePart(l) }))), `${c.name}: the Worker reads its cast sheet`);
  const lines = Array.from({ length: CORE.MAX_LINES }, (_, i) => ({ kind: 'speech', role: 'A'.repeat(40), text: `w${i}` }));
  const most = CORE.toScript(CORE.done(CORE.newDoc(lines)), { id: ID, title: 'T' });
  eq(most.lines[5999].id, 'L6000', 'the last id');
  ok(relay.parseCast(most.lines.map(l => ({ id: l.id, part: C.linePart(l) }))), 'the Worker reads the longest cast sheet');
  eq(manifest.validRow({ format: manifest.ROW_FORMAT, id: 'x', revision: '0'.repeat(12), title: 'T'.repeat(CORE.MAX_TITLE), cast: '0'.repeat(64), lines: 1, source: null, rights: { bucket: 'b', evidence: [] }, publishable: false }, 'x').title.length, CORE.MAX_TITLE, 'a title');
});

test('too much is refused: text, lines, canonical bytes', () => {
  eq(CORE.textRefusal('a'.repeat(CORE.MAX_BYTES)), null, '400,000 bytes');
  eq(CORE.textRefusal('a'.repeat(CORE.MAX_BYTES + 1)), 'too_long', 'one more');
  eq(CORE.textRefusal('\u00e9'.repeat(200001)), 'too_long', 'counted in UTF-8');
  eq(CORE.textRefusal('\u4e2d'.repeat(133333)), null, 'three bytes each');
  eq(CORE.textRefusal(' \ufeff\n\t'), 'empty', 'nothing');
  eq(CORE.utf8Length('a\u00e9\u4e2d\ud83d\ude00'), new TextEncoder().encode('a\u00e9\u4e2d\ud83d\ude00').length, 'UTF-8 length');
  const of = (n, text) => CORE.toScript({ ...CORE.done(CORE.newDoc(Array.from({ length: n }, () => ({ kind: 'speech', role: 'A', text })))) }, { id: ID, title: 'T' });
  eq(CORE.refusalOf(of(6001, 'x')), 'too_many_lines', '6,001 lines');
  eq(CORE.refusalOf(of(1, 'x'.repeat(399900))), null, 'just under');
  eq(CORE.refusalOf(of(1, 'x'.repeat(400000))), 'too_long', 'over');
  const full = CORE.newDoc(Array.from({ length: 6000 }, () => ({ kind: 'speech', role: 'A', text: 'x y' })));
  eq(CORE.apply(full, { op: 'split', line: 1, at: 1 }).refusal, 'too_many_lines', 'no split past the cap');
  eq(CORE.apply(full, { op: 'add', after: 1, kind: 'sound', text: 'x' }).refusal, 'too_many_lines', 'no line added past the cap');
});

/* ---- Time ---- */

const fill = (unit, n = CORE.MAX_BYTES) => unit.repeat(Math.ceil(n / unit.length)).slice(0, n);
const took = (fn) => { const t = performance.now(); fn(); return performance.now() - t; };
test('400 KB of script is read in under 100 ms', () => {
  const text = fill('ANNA: The lamp has gone out again, and there is no oil (she looks for it).\n\nBEN. We could light the candle\nfrom the stove.\n\nIt would be a small light, but a light.\n\nANNA\nSo be it.\n\n');
  const best = Math.min(...Array.from({ length: 7 }, () => took(() => CORE.parse(text))));
  ok(best < 100, `${best.toFixed(1)} ms`);
});
test('no text makes it slow: 400 KB of each hostile shape, each under two seconds', () => {
  const shapes = ['(', '[', '(a\n', '(a\n\n', '[a\n', '([', '((a', `A${' '.repeat(5000)}x`, 'A ', 'A. ', 'A:', 'A: ', ':', '.', '_', '*', '**a', '-', 'A (b [c ', 'MR. ', 'ABCDE FGHI\n', 'A\t', 'A   b\n', '@A:\n', '\r', '\ud800',
    'e\u0301\u0301', '\ud83d\udc69\u200d', 'Aaa. Bbb\n', 'Exit\n', 'SOUND ', 'ACT ', 'END OF ', 'A(', 'A,(', 'A.(', 'A.B.'];
  for (const s of shapes) {
    const text = fill(s);
    const ms = took(() => { CORE.parse(text); CORE.pieces(text); CORE.cutAt(text, 200000); CORE.wordsChanged(text, text); });
    ok(ms < 2000, `${JSON.stringify(s.slice(0, 12))}: ${ms.toFixed(0)} ms`);
  }
  for (const s of ['<', '-->\n', '<a', '&amp;', '00:01.000 --> 00:02.000\nHi. There.\n\n', 'Mr. A. B? "C" ', '1:']) {
    const ms = took(() => CORE.fromCues(CORE.parseCues(fill(s))));
    ok(ms < 2000, `cues ${JSON.stringify(s.slice(0, 12))}: ${ms.toFixed(0)} ms`);
  }
});

(async () => {
  for (const [name, fn] of tests) {
    try { await fn(); passes += 1; console.log(`  ok    ${name}`); }
    catch (e) { failures += 1; console.log(`  FAIL  ${name}\n        ${String(e.message).slice(0, 1500)}`); }
  }
  console.log(failures ? `FAIL: ${failures} of ${passes + failures} (${G.parse.cases.length} texts)` : `PASS: ${passes} (${G.parse.cases.length} texts, ${G.ops.sequences.length} op sequences, ${G.ear.casts.length} casts, ${MUTANTS.length} mutants)`);
  process.exit(failures ? 1 : 0);
})();
