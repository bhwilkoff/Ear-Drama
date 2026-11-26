/**
 * The script reader (WEB-DESIGN §4.16, Decision 076 S0 and S1), run against the SHIPPED
 * js/plays-core.js and js/reader-core.js: the act and scene headings every stack must agree on
 * (catalog/tests/golden/script_sections.json), the contents over real scripts (picked from the
 * data, never pinned), search, a part's next line, the open speaking parts, the page arithmetic,
 * the reading position kept across a re-layout, and the text runs marks will anchor to.
 *   node js/reader.test.js
 *
 * Seen to fail, 2026-11-14: before js/reader-core.js existed (every ReaderCore case), and against
 * mutated copies: contentsOf without the same-act rule (the grouping case), lineAtPage returning
 * the last line that starts on the page (the carried-over case and the re-layout case), and runsOf
 * counting the joined pieces without the space between them (the runs case over real scripts).
 * Seen to fail, 2026-11-26: landingPage returning the kept line's first page (the B29 case: "went back to page 1").
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.resolve(__dirname, '..');
for (const f of ['plays-core.js', 'reader-core.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), { filename: f });
}
const C = vm.runInThisContext('PlaysCore');
const R = vm.runInThisContext('ReaderCore');

let passes = 0, failures = 0;
function test(name, fn) {
  try { fn(); passes += 1; console.log(`  ok    ${name}`); }
  catch (e) { failures += 1; console.log(`  FAIL  ${name}\n        ${e.message}`); }
}
const later = [];
function atest(name, fn) { later.push([name, fn]); }
function eq(a, b, msg) {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}: got ${x}, want ${y}`);
}
function ok(v, msg) { if (!v) throw new Error(msg); }

const bundle = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json'), 'utf8')).scripts;
const LIB = path.join(ROOT, 'catalog', 'out', 'plays-library');
const libIndex = fs.existsSync(path.join(LIB, 'index.json')) ? JSON.parse(fs.readFileSync(path.join(LIB, 'index.json'), 'utf8')) : null;
/** Up to `n` library scripts, spread across the index (every k-th), so no test names a play. */
function libraryScripts(n, keep = () => true) {
  if (!libIndex) return [];
  const rows = libIndex.plays;
  const step = Math.max(1, Math.floor(rows.length / (n * 3)));
  const out = [];
  for (let i = 0; i < rows.length && out.length < n; i += step) {
    const s = JSON.parse(fs.readFileSync(path.join(LIB, rows[i].path), 'utf8')).scripts[0];
    if (keep(s)) out.push({ row: rows[i], s });
  }
  return out;
}
const L = (id, kind, extra = {}) => ({ id, kind, role: kind === 'speech' ? extra.role || 'A' : null, ...extra });

test('section headings: the golden cases every stack runs', () => {
  const g = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'tests', 'golden', 'script_sections.json'), 'utf8'));
  ok(g.cases.length > 20, 'the golden file has its cases');
  for (const c of g.cases) {
    eq(C.sectionLevel(c.text), c.level, `level of ${JSON.stringify(c.text)}`);
    if (c.title) eq(C.sectionTitle(c.text), c.title, `title of ${JSON.stringify(c.text)}`);
    if (c.act) eq(C.actKey(c.text), c.act, `act of ${JSON.stringify(c.text)}`);
  }
});

test('contents: an act heading that repeats the act is its scene; an epilogue stands alone', () => {
  const s = { id: 't', lines: [
    L('L0001', 'speech', { parts: [{ say: 'Before anything.' }] }),
    L('L0002', 'direction', { source: 'SCENE I. A road.' }),
    L('L0003', 'speech', { parts: [{ say: 'One.' }] }),
    L('L0004', 'speech', { parts: [{ say: 'Two.' }] }),
    L('L0005', 'direction', { source: 'ACT I. SCENE II. The same.' }),
    L('L0006', 'speech', { parts: [{ say: 'Three.' }] }),
    L('L0007', 'speech', { parts: [{ say: 'Four.' }] }),
    L('L0008', 'direction', { source: '_Enter_ B.' }),
    L('L0009', 'speech', { parts: [{ say: 'Five.' }] }),
  ], sections: [{ line: 'L0004', source: 'ACT I.' }, { line: 'L0007', source: 'ACT II.' }, { line: 'L0009', source: 'EPILOGUE' }] };
  const secs = C.sectionsOf(s);
  eq(secs.map(x => [x.line, x.level, x.isLine]), [['L0002', 'scene', true], ['L0004', 'act', false], ['L0005', 'scene', true],
    ['L0007', 'act', false], ['L0009', 'part', false]], 'sections in reading order, set-aside headings marked, a repeated act a scene');
  const toc = C.contentsOf(s);
  eq(toc.map(t => [t.title, t.scenes.map(x => x.title)]), [['SCENE I. A road.', []], ['ACT I.', ['ACT I. SCENE II. The same.']],
    ['ACT II.', []], ['EPILOGUE', []]], 'grouped');
  eq([C.placeOf(s, 4).act.title, C.placeOf(s, 4).scene.title], ['ACT I.', 'ACT I. SCENE II. The same.'], 'a line\'s place');
  eq(C.placeOf(s, 0).act, null, 'before the first heading, no place');
  eq(C.contentsOf({ id: 'none', lines: [L('L0001', 'speech', { parts: [{ say: 'x' }] })] }), [], 'no headings, no contents');
});

test('contents: a printed list of the acts before the play (no speech under it) is left out', () => {
  const s = { id: 'list', lines: [
    L('L0001', 'direction', { source: 'ACT I.—“Shot in the back.”' }),
    L('L0002', 'direction', { source: 'ACT II.—“After Taps.”' }),
    L('L0003', 'direction', { source: 'ACT III.—“Home Again.”' }),
    L('L0004', 'direction', { source: 'SCENE.—A room.' }),
    L('L0005', 'speech', { parts: [{ say: 'Hello.' }] }),
    L('L0006', 'speech', { parts: [{ say: 'Goodbye.' }] }),
  ], sections: [{ line: 'L0004', source: 'ACT I.' }] };
  eq(C.contentsOf(s).map(t => t.title), ['ACT I.'], 'only the act the play opens with');
  eq(C.sectionsOf({ id: 'empty-end', lines: [L('L0001', 'speech', { parts: [{ say: 'x' }] }), L('L0002', 'direction', { source: 'ACT II.' })] }), [],
    'a heading with nothing after it');
});

test('contents over real scripts: every section lands on a line, in order, scenes inside their acts', () => {
  const picked = [...bundle.map(s => ({ s })), ...libraryScripts(60)];
  ok(picked.length >= 15, 'scripts to read');
  let withContents = 0, setAside = 0;
  for (const { s } of picked) {
    const ids = new Set(s.lines.map(l => l.id));
    const secs = C.sectionsOf(s);
    secs.forEach((x, i) => {
      ok(ids.has(x.line), `${s.id}: section at a line that exists (${x.line})`);
      ok(s.lines[x.index].id === x.line, `${s.id}: index matches`);
      ok(!x.isLine || s.lines[x.index].kind !== 'speech', `${s.id}: a heading line is never a speech`);
      ok(x.title.length > 0 && !x.title.includes('\n') && !x.title.includes('_'), `${s.id}: a one-line title`);
      if (i) ok(secs[i - 1].index <= x.index, `${s.id}: in reading order`);
      if (!x.isLine) setAside += 1;
    });
    const toc = C.contentsOf(s);
    if (toc.length) withContents += 1;
    toc.forEach((t, k) => {
      const nextAt = k + 1 < toc.length ? toc[k + 1].index : Infinity;
      t.scenes.forEach(sc => ok(sc.index >= t.index && sc.index <= nextAt, `${s.id}: ${sc.title} inside ${t.title}`));
    });
    eq(toc.reduce((n, t) => n + 1 + t.scenes.length, 0), secs.length, `${s.id}: every section in the contents once`);
  }
  ok(withContents > 0, 'some real script has contents');
  if (libIndex) ok(setAside > 0, 'the built library carries printed headings the parser set aside');
});

test('search: case, accents, curly quotes and line breaks fold; hits in order with their words around them', () => {
  const s = { id: 't', lines: [
    L('L0001', 'speech', { role: 'ANNE', parts: [{ say: 'I don’t know the CAFÉ' }, { direction: 'aside' }, { say: 'on the\ncorner.' }] }),
    L('L0002', 'direction', { source: '_Enter_ the waiter.' }),
    L('L0003', 'speech', { role: 'BEN', parts: [{ say: 'The cafe is shut. Don\'t go.' }] }),
  ] };
  const r = C.searchScript(s, "don't");
  eq([r.total, r.hits.map(h => [h.line, h.role, h.match])], [2, [['L0001', 'ANNE', 'don’t'], ['L0003', 'BEN', 'Don\'t']]], 'quotes fold');
  eq(C.searchScript(s, 'café').hits.map(h => h.line), ['L0001', 'L0003'], 'accents fold');
  eq(C.searchScript(s, 'the corner').hits.map(h => h.match), ['the\ncorner'.replace(/\s+/g, ' ')], 'a line break is a space');
  eq(C.searchScript(s, 'w').total, 0, 'one letter finds nothing');
  eq(C.searchScript(s, 'the', { limit: 1 }).hits.length, 1, 'limit');
  eq(C.searchScript(s, 'the', { limit: 1 }).total, 3, 'the total counts past the limit');
  const h = C.searchScript(s, 'shut').hits[0];
  eq(h.before + h.match + h.after, 'The cafe is shut. Don\'t go.', 'the words around the match');
  const real = bundle[0];
  const word = C.lineText(real.lines.find(l => l.kind === 'speech')).split(/\s+/).find(w => w.length > 4);
  ok(C.searchScript(real, word).total >= 1, `a word from a real script is found (${word})`);
});

test('a part\'s next and previous line, and the open speaking parts', () => {
  const s = { id: 't', lines: [L('L1', 'speech', { role: 'A' }), L('L2', 'speech', { role: 'B' }), L('L3', 'direction', { source: 'x' }),
    L('L4', 'speech', { role: 'A' }), L('L5', 'sound', { source: 'BELL' })] };
  eq([C.nextLineOf(s, 'role:A', -1), C.nextLineOf(s, 'role:A', 0), C.nextLineOf(s, 'role:A', 3)], [0, 3, -1], 'next');
  eq([C.nextLineOf(s, 'role:A', 3, -1), C.nextLineOf(s, 'role:A', 0, -1)], [0, -1], 'previous');
  const p = C.newProduction({ ...s, title: 't', revision: 'r' }, { id: 'P', created: 0 });
  eq(C.openSpeakingParts(p, s), ['role:A', 'role:B'], 'sound and directions are never open parts');
  p.parts['role:A'] = { status: 'done' };
  eq(C.openSpeakingParts(p, s), ['role:B'], 'a done part is not open');
  eq(C.openSpeakingParts({ parts: { directions: { status: 'open' }, sound: { status: 'open' } } }, null), [], 'without the script, by the record');
});

test('an index row and its full script count the same voices, minutes and cast', () => {
  const s = bundle[0];
  const row = { voices: 4, minutes: 12, cast: [9, 5, 1], authors: ['Ann Author'] };
  eq([C.voicesOf(row), C.minutesOf(row), C.castOf(row), C.partCountOf(row), C.authorLine(row)], [4, 12, [9, 5, 1], 3, 'Ann Author'], 'a row');
  eq([C.castOf({ voices: 3, roles: 7, minutes: 9 }), C.partCountOf({ roles: 7 })], [[], 7], 'a row published before `cast` draws no cast and does not throw');
  eq(C.castOf(s), C.castParts(s).filter(x => C.isSpeaking(x.id)).map(x => x.lineCount), 'a full script counts its lines');
  if (!libIndex) return;
  const byId = new Map(libIndex.plays.map(p => [p.id, p]));
  for (const b of bundle) {
    const r = byId.get(b.id);
    ok(r, `${b.id} in the library`);
    eq(C.voicesOf(b), r.voices, `${b.id}: voices`);
    eq(C.castOf(b), r.cast, `${b.id}: cast`);
  }
});

test('ReaderCore: settings default to pages, and unknown values fall back', () => {
  eq(R.normalizePrefs(null), { layout: 'pages', size: R.DEFAULT_SIZE, spacing: 'normal' }, 'defaults');
  eq(R.normalizePrefs({ layout: 'scroll', size: 6, spacing: 'loose' }), { layout: 'scroll', size: 6, spacing: 'loose' }, 'kept');
  eq(R.normalizePrefs({ layout: 'curl', size: 99, spacing: 'huge' }), { layout: 'pages', size: R.DEFAULT_SIZE, spacing: 'normal' }, 'refused');
  eq(R.SIZES[R.DEFAULT_SIZE], 1, 'the default size is the body size');
});

test('ReaderCore: the line a page shows first is the one carried over', () => {
  // line 0 on page 0; line 1 runs from page 0 onto page 1; line 2 starts on page 1; line 3 fills pages 2-4.
  const starts = [0, 0, 1, 2], ends = [0, 1, 1, 4];
  eq([0, 1, 2, 3, 4].map(p => R.lineAtPage(starts, ends, p)), [0, 1, 3, 3, 3], 'first line still showing');
  eq(R.lineAtPage([], [], 0), -1, 'no lines');
});

test('ReaderCore: turns, spreads, swipes, taps and keys', () => {
  eq([834, 859, 860, 951, 1440].map(R.perSpread), [1, 1, 2, 2, 2], 'two pages from 860 px');
  eq([R.turn(0, -1, 1, 10), R.turn(0, 1, 1, 10), R.turn(9, 1, 1, 10)], [0, 1, 9], 'one page, clamped');
  eq([R.turn(0, 1, 2, 9), R.turn(3, 1, 2, 9), R.turn(7, 1, 2, 9), R.turn(8, 1, 2, 9)], [2, 4, 8, 8], 'spreads start on even pages');
  eq([R.pageAt(0, 400), R.pageAt(399.6, 400), R.pageAt(1200, 400)], [0, 1, 3], 'a column\'s page');
  eq(R.pageCount(4 * 400 - 32, 400, 32), 4, 'pages from the flow width');
  eq([R.swipeTurn(-90, 400, 375), R.swipeTurn(90, 400, 375), R.swipeTurn(-40, 60, 375), R.swipeTurn(-40, 400, 375), R.swipeTurn(-10, 5, 375)],
    [1, -1, 1, 0, 0], 'swipe past a fifth, or flick');
  eq([R.tapZone(10, 375), R.tapZone(200, 375), R.tapZone(370, 375)], ['prev', 'middle', 'next'], 'outer fifths turn');
  eq([R.keyTurn('ArrowRight'), R.keyTurn('PageUp'), R.keyTurn(' ', false), R.keyTurn(' ', true), R.keyTurn('ArrowDown'), R.keyTurn('Home'), R.keyTurn('a')],
    [1, -1, 1, -1, 1, 'first', 0], 'keys and pedals');
  eq([R.pageLabel(0, 1, 140), R.pageLabel(10, 2, 140), R.pageLabel(138, 2, 139)], ['1 of 140', '11–12 of 140', '139 of 139'], 'labels');
});

test('ReaderCore: the reading position survives a re-layout (text size up, then down)', () => {
  // Layout A: 6 lines, two a page. Layout B (larger text): each line its own page, line 3 runs two.
  const A = { starts: [0, 0, 1, 1, 2, 2], ends: [0, 0, 1, 1, 2, 2] };
  const B = { starts: [0, 1, 2, 3, 5, 6], ends: [0, 1, 2, 4, 5, 6] };
  const at = R.lineAtPage(A.starts, A.ends, 1);
  eq(at, 2, 'the top of page 2 in A');
  const pageB = B.starts[at];
  ok(B.starts[at] <= pageB && pageB <= B.ends[at], 'B turns to the page holding that line');
  eq(R.lineAtPage(B.starts, B.ends, pageB), at, 'and reads it back as the position');
  const back = A.starts[R.lineAtPage(B.starts, B.ends, pageB)];
  eq(back, 1, 'back in A, the same page');
  const spread = R.spreadStart(B.starts[3], 2);
  ok(spread <= B.starts[3] && B.starts[3] < spread + 2, 'a spread holds the line too');
});

test('ReaderCore: remembered positions, newest first, capped', () => {
  let st = {};
  for (let i = 0; i < 70; i++) st = R.remember(st, `s${i}`, { line: 'L0001' });
  eq(Object.keys(st).length, 60, 'capped');
  eq(Object.keys(st)[0], 's69', 'newest first');
  st = R.remember(st, 's10', { part: 'role:A' });
  eq([Object.keys(st)[0], st.s10.line, st.s10.part], ['s10', 'L0001', 'role:A'], 'an update keeps the line');
});

test('runs: every printed run maps back to its line\'s words (the anchor marks will use)', () => {
  const picked = [...bundle.map(s => ({ s })), ...libraryScripts(40)];
  let n = 0;
  for (const { s } of picked) {
    for (const line of s.lines) {
      const text = C.lineText(line);
      const runs = R.runsOf(line);
      for (const r of runs) {
        n += 1;
        if (text.slice(r.at, r.at + r.text.length) !== r.text) {
          throw new Error(`${s.id} ${line.id}: run at ${r.at} reads ${JSON.stringify(text.slice(r.at, r.at + r.text.length))}, not ${JSON.stringify(r.text)}`);
        }
      }
      ok(runs.every(r => ['say', 'aside', 'plain', 'em'].includes(r.kind)), `${s.id} ${line.id}: run kinds`);
    }
  }
  ok(n > 1000, `runs checked (${n})`);
  eq(R.runsOf({ kind: 'direction', source: '_Enter_ BEN, _slowly_.' }).map(r => [r.kind, r.text, r.at]),
    [['em', 'Enter', 1], ['plain', ' BEN, ', 7], ['em', 'slowly', 14], ['plain', '.', 21]], 'italic marks are drawn, not kept');
  eq(R.runsOf({ kind: 'speech', role: 'A', parts: [{ say: 'Hello' }, { direction: 'Looks at_ POLLY' }, { say: '. Go.' }] })
    .map(r => [r.kind, r.text, r.at, r.said]),
  [['say', 'Hello', 0, true], ['aside', 'Looks at', 6, false], ['plain', ' POLLY', 15, false], ['say', '. Go.', 22, true]],
  'a name inside an aside turns roman; the said words stay said');
  eq([R.spaceBetween('born.', 'laughing'), R.spaceBetween('laughing', '. Same'), R.spaceBetween('(', 'x'), R.spaceBetween('a', ', b')],
    [true, false, false, false], 'no space before closing punctuation or after an opening one');
});

test('the page: verse keeps its lines, a transcriber\'s wrapping is reflowed', () => {
  ok(R.isVerse(['When shall we three meet again?\nIn thunder, lightning, or in rain?']), 'a couplet is verse');
  ok(R.isVerse(['This is the sergeant\nWho, like a good and hardy soldier, fought\n’Gainst my captivity.']), 'a capital after a quote');
  ok(!R.isVerse(['I attribute it to the superior quality of the wine, sir. I have often\nobserved that in married households']), 'a lowercase turnover is prose');
  ok(!R.isVerse(['Why is it that at a bachelor’s establishment the servants invariably\nDrink the champagne? I ask merely for information, and nothing more than\nThat, sir, as anyone would.']), 'rows as long as a wrapped line are prose');
  ok(!R.isVerse(['Who is there?']), 'no break, nothing to keep');
});

test('the opening keeps the lines of verse and no other break (the reader\'s own detection)', () => {
  const said = (...parts) => ({ id: 'L1', kind: 'speech', role: 'A', parts });
  const verse = said({ direction: 'dreamily' }, { say: 'This is the sergeant\nWho, like a _good_ and hardy soldier, fought--\n   \u2019Gainst my captivity.' });
  const script = (...lines) => ({ roles: [{ name: 'A' }, { name: 'BEA' }], lines });
  eq(C.openingOf(script(verse), 4, R)[0].verse, ['This is the sergeant', 'Who, like a good and hardy soldier, fought\u2014', '\u2019Gainst my captivity.'], 'a row per printed line, tidied as the words are');
  eq(C.openingOf(script(verse), 4, R)[0].text, 'This is the sergeant Who, like a good and hardy soldier, fought\u2014 \u2019Gainst my captivity.', 'the voice is given the words in one piece');
  eq(C.openingOf(script(verse), 4)[0].verse, null, 'no reader, no verse');
  eq(C.openingOf(script(said({ say: 'I attribute it to the superior quality of the wine, sir. I have often\nobserved that in married households' })), 4, R)[0].verse, null, 'a transcriber\'s wrap is prose');
  eq(C.openingOf(script(said({ say: 'Of course.\nBEA. Yes, indeed.' })), 4, R)[0].verse, null, 'a run-in speaker is not verse');
  const row = { opening: [{ role: 'A', text: 'When shall we three meet again?\nIn thunder, lightning, or in rain?' }, { role: 'B', text: 'One line.' }] };
  eq(C.openingOf(row, 2, R).map(o => o.verse), [['When shall we three meet again?', 'In thunder, lightning, or in rain?'], null], 'an index row that keeps its breaks');
  eq(C.openingOf(row, 2, R)[0].text, 'When shall we three meet again? In thunder, lightning, or in rain?', 'and its words');
  eq(C.openingOf({ opening: [{ role: 'A', text: 'I never saw you look so\nwell in my life.' }] }, 2, R)[0].verse, null, 'an index row\'s wrapped prose keeps none');
  for (const { s } of libraryScripts(60)) for (const o of C.openingOf(s, 4, R)) if (o.verse) ok(o.verse.length > 1 && o.verse.every(r => !/\n|\s{2,}/.test(r)), s.id);
});

test('the page: a speech run into another is attributed to its speaker; cues get the sound lane', () => {
  const roles = ['CHARTERIS', 'GRACE'];
  const line = { id: 'L1', kind: 'speech', role: 'CHARTERIS', parts: [{ say: 'Of course. Why not?\nGRACE' }, { direction: 'reflecting' }, { say: '. Never mind why.' }] };
  const lay = R.layoutOf(line, roles);
  eq(lay.speeches.map(s => s.role), ['CHARTERIS', 'GRACE'], 'two speakers');
  eq(lay.speeches[1].name && [lay.speeches[1].name.text, lay.speeches[1].name.at], ['GRACE', 20], 'the printed name, at its offset');
  eq(lay.speeches[1].rows[0].runs.map(r => [r.text, r.said]), [['reflecting', false], ['Never mind why.', true]], 'the label period is not drawn');
  ok(!lay.verse, 'a run-in break is not verse');
  // A person's own script (PLAYS-DESIGN §13): brackets they typed are directions, never drawn as words said.
  const typed = { id: 'L1', kind: 'speech', role: 'ANNA', parts: [{ say: 'Words of my own' }, { direction: 'she laughs' }, { say: 'instead.' }] };
  const asides = (opts) => R.layoutOf(typed, ['ANNA'], opts).speeches[0].rows.flatMap(rw => rw.runs).filter(r => !r.said).map(r => r.text.trim());
  eq(asides({ emphasis: false }), ['she laughs'], 'an own script\'s bracketed words stay a direction');
  eq(asides(), [], 'control: a catalog text\'s short italic run is the speaker\'s emphasis');
  const radio = R.layoutOf({ id: 'L2', kind: 'speech', role: 'HANCOCK', parts: [{ direction: 'sound of gavel' }, { say: 'Order!' }, { sound: 'knock' }, { say: 'Come in.' }] }, ['HANCOCK']);
  eq(radio.speeches[0].rows.map(r => r.cue), [true, false, true, false], 'a sound piece and a sound-of aside are cue rows');
  const block = R.layoutOf({ id: 'L3', kind: 'direction', source: '[_Exeunt._]' }, []);
  eq(block.rows[0].runs.map(r => [r.kind, r.text]), [['plain', 'Exeunt.']], 'brackets left undrawn; a wholly italic direction stays italic');
  eq(R.layoutOf({ id: 'L4', kind: 'direction', source: '[Enter Lane.' }, []).rows[0].runs.map(r => r.text), ['Enter Lane.'], 'an unclosed bracket');
  const stress = R.layoutOf({ id: 'L5', kind: 'speech', role: 'A', parts: [{ say: 'It is the first in which' }, { direction: 'I' }, { say: 'have been serious.' }, { direction: 'Sits.' }, { say: 'Well.' }] }, ['A']);
  eq(stress.speeches[0].rows[0].runs.map(r => [r.text, r.said]), [['It is the first in which', true], ['I', true], ['have been serious.', true], ['Sits.', false], ['Well.', true]],
    'an italic word between lowercase said words is emphasis; a sentence direction stays a direction');
  const em = R.layoutOf({ id: 'L6', kind: 'speech', role: 'A', parts: [{ say: 'It is the first in which' }, { say: 'I' }, { say: 'have been serious.' }], em: [1] }, ['A']);
  eq(em.speeches[0].rows[0].runs.map(r => [r.text, r.kind, r.said]), [['It is the first in which', 'say', true], ['I', 'em', true], ['have been serious.', 'say', true]],
    'a part the catalog marks `em` is said, in italic');
  eq(R.cueTail('I could love anybody. Any pretty woman, that is.'), 22, 'the cue is the last sentence');
  eq(R.cueTail('Who is there?'), 0, 'one sentence is all cue');
});

test('the page: every drawn run still maps back to its line\'s words (marks anchor through layoutOf)', () => {
  const picked = [...bundle.map(s => ({ s })), ...libraryScripts(40)];
  let n = 0, split = 0;
  for (const { s } of picked) {
    const roles = (s.roles || []).map(r => r.name);
    for (const line of s.lines) {
      const text = C.lineText(line).replace(/\n/g, ' ');
      const lay = R.layoutOf(line, roles);
      const runs = [];
      for (const sp of lay.speeches || [{ rows: lay.rows }]) {
        if (sp.name) runs.push(sp.name);
        for (const rw of sp.rows) runs.push(...rw.runs);
      }
      if (lay.speeches && lay.speeches.length > 1) split += 1;
      for (const r of runs) {
        n += 1;
        const want = r.text.replace(/\n/g, ' ');
        if (text.slice(r.at, r.at + want.length) !== want) throw new Error(`${s.id} ${line.id}: run at ${r.at} reads ${JSON.stringify(text.slice(r.at, r.at + want.length))}, not ${JSON.stringify(want)}`);
      }
    }
  }
  ok(n > 1000, `runs checked (${n})`);
  // No floor on split: the parser now splits run-in speeches itself (catalog, 2026-11-15); the fixture test above covers the page's own split.
});

test('Close: back only from inside the app; a cold link goes to the play or its production', () => {
  eq(R.closeTo(true, false, null, 'p1'), 'back', 'opened in the app');
  eq(R.closeTo(false, false, null, 'p 1'), '?play=p%201', 'cold read');
  eq(R.closeTo(false, true, 'pr1', 'p1'), '?production=pr1', 'cold studio');
  eq([R.myLineStep('j'), R.myLineStep('K'), R.myLineStep('x')], [1, -1, 0], 'J and K');
});

test('read-along: the line heard comes from the listen plan; a mix finds its line by time', () => {
  const plan = [{ lineID: 'L1', source: 'take' }, { lineID: 'L3', source: 'voice' }, { lineID: 'L4', source: 'take' }];
  eq([R.alongLine(plan, 0), R.alongLine(plan, 1), R.alongLine(plan, 2)], ['L1', 'L3', 'L4'], 'plan entries in order');
  eq([R.alongLine(plan, 3), R.alongLine(plan, -1), R.alongLine([], 0)], [null, null, null], 'past the end, none');
  const pl = [{ lineID: 'L1', start: 0, frames: 100 }, { lineID: 'L2', start: 150, frames: 100 }];
  const at = (s) => R.alongLineAt(pl, 100, s);
  eq([at(0), at(0.99), at(1.2), at(1.5), at(2.49), at(2.6)], ['L1', 'L1', 'L1', 'L2', 'L2', null], 'a gap keeps the line before it; past the end, none');
  eq(R.alongLineAt([], 100, 1), null, 'no placements');
});

test('read-along: the reader turns itself while following; scrolling away stops it; Back to the line returns', () => {
  const f = R.alongFollow();
  eq(f.line('L1'), { turn: true, back: false }, 'first line turns the page');
  eq(f.away(), { turn: false, back: true }, 'away offers the return at once, before the next line');
  eq(f.line('L2'), { turn: false, back: true }, 'away: no turn, the return is offered');
  eq(f.line('L3'), { turn: false, back: true }, 'still away');
  eq(f.back(), 'L3', 'back returns to the line now heard');
  eq(f.line('L4'), { turn: true, back: false }, 'following again');
  f.away();
  f.line(null);
  eq(f.back(), null, 'nothing heard, nothing to return to');
  eq(f.away(), { turn: false, back: false }, 'away with nothing heard offers nothing');
  eq(f.line(null), { turn: false, back: false }, 'no return offered when nothing plays');
});

test('read-along (B29): a re-layout lands on the word heard and never goes back while lines advance', () => {
  // A play-through over the front and four lines, each re-laid out twice (the page height changing as the dock and the
  // transport come and go): line 0 sits on page 1 with the front, line 1 runs from page 1 onto 2, lines 2 and 3 are on 2.
  // Each line: its words' pages in order, its first page (`keep`) and its first word's page (`text`).
  const lines = [{ keep: 0, text: 0, words: [0, 0] }, { keep: 0, text: 0, words: [0, 1, 1] }, { keep: 1, text: 1, words: [1, 1] }, { keep: 1, text: 1, words: [1] }];
  const shown = [];
  lines.forEach((l, i) => {
    shown.push(R.landingPage({ keep: l.keep, heard: i, word: null, text: l.text }));
    for (const w of l.words) {
      shown.push(w);
      shown.push(R.landingPage({ keep: l.keep, heard: i, word: w, text: l.text }));
    }
  });
  for (let k = 1; k < shown.length; k++) ok(shown[k] >= shown[k - 1], `went back to page ${shown[k] + 1} at step ${k}: ${shown.join(',')}`);
  eq(R.landingPage({ keep: 3, heard: 4, word: null, text: 5 }), 5, 'before a word is marked (a take): the line heard\'s own words, not a heading on the page before');
  eq(R.landingPage({ keep: 3, heard: -1, word: 9, text: 5 }), 3, 'nothing followed: the kept line\'s first page');
  eq(R.landingPage({ keep: 3, heard: null, word: null, text: null }), 3, 'nothing heard');
  eq(R.landingPage({ keep: 3, heard: 4, word: null, text: null }), 3, 'a line printing no word: its first page');
});

test('read-along: the TV panel shows the line heard and one on each side', () => {
  const s = { lines: ['A', 'B', 'C'].map((x, i) => ({ id: `L${i}`, kind: 'speech', part: x })) };
  eq(R.alongPanel(s, 'L1').map(x => x && x.id), ['L0', 'L1', 'L2'], 'middle');
  eq(R.alongPanel(s, 'L0').map(x => x && x.id), [null, 'L0', 'L1'], 'first has no line before');
  eq(R.alongPanel(s, 'L2').map(x => x && x.id), ['L1', 'L2', null], 'last has none after');
  eq(R.alongPanel(s, 'nope'), [null, null, null], 'unknown');
});

test('read-along, finished drama: a file number is its line\'s 1-based place in the script; a revision mismatch offers nothing', () => {
  const s = { revision: 'r1', lines: ['A', 'B', 'C', 'D'].map((x, i) => ({ id: `L${i}`, kind: 'speech', part: x })) };
  const picked = { lines: ['u2', 'u4'], seqs: [2, 4] };
  eq(R.dramaPlan(picked, s, 'r1'), [{ lineID: 'L1', url: 'u2' }, { lineID: 'L3', url: 'u4' }], 'a silent line leaves a gap, never a shift');
  eq(R.dramaPlan(picked, s, undefined), null, 'a Worker that sends no revision cannot vouch for the numbering');
  eq(R.dramaPlan(picked, s, 'r2'), null, 'another revision of the script is another numbering');
  eq(R.dramaPlan({ lines: ['u9'], seqs: [9] }, s, 'r1'), null, 'a number past the script is no match');
  eq(R.dramaPlan({ whole: 'u' }, s, 'r1'), null, 'one whole recording has no line timeline');
  eq(R.dramaPlan(null, s, 'r1'), null, 'nothing playable yet');
});

atest('read-along, finished drama: the queue follows file boundaries and reports the line of the file heard', async () => {
  const plan = [{ lineID: 'L1', url: 'a' }, { lineID: 'L3', url: 'b' }, { lineID: 'L4', url: 'c' }];
  const made = [];
  const audio = (url) => {
    const a = { url, muted: false, paused: false, pause() { this.paused = true; this.finish && this.finish(); }, play() { return new Promise((res) => { this.finish = res; made.push(this); }); } };
    return a;
  };
  const seen = [];
  const q = R.dramaListen(plan, { audio, muted: () => false, onChange: (s) => seen.push(s.current() && s.current().lineID) });
  eq(q.current(), null, 'nothing is heard before play');
  q.play();
  await Promise.resolve(); await Promise.resolve();
  eq(q.current(), { lineID: 'L1', source: 'take' }, 'the first file');
  ok(q.playing, 'playing');
  made[0].finish();
  await new Promise(r => setTimeout(r, 0));
  eq(q.current(), { lineID: 'L3', source: 'take' }, 'the second file is the next line heard, by file, not by guess');
  q.stop();
  await new Promise(r => setTimeout(r, 0));
  ok(!q.playing, 'stopped');
  eq(q.current(), null, 'nothing heard once stopped');
  eq(seen.at(-1), null, 'the reader is told it stopped');
});

test('the word heard: the golden cases every stack runs (PLAYS-DESIGN 2.11 rule 3)', () => {
  const g = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'tests', 'golden', 'read_along_words.json'), 'utf8'));
  for (const c of g.spoken) {
    const sp = R.spoken(c.line);
    eq(sp.said, c.said, `the string the voice is given for ${c.line.id}`);
    for (const k of c.cases) {
      const w = R.word(sp, k.range[0], k.range[1]);
      eq(w ? [w.start, w.end] : null, k.word, `${c.line.id} range ${k.range}`);
    }
  }
  for (const t of g.textWords) eq(R.textWords(t.said), t.words, `printed words of ${JSON.stringify(t.said)}`);
  for (const k of g.kokoro) {
    const pieces = k.pieces.map(p => ({ symbols: p.symbols, frames: p.frames }));
    eq(R.kokoroWords(k.said, pieces), k.words, `Kokoro words of ${JSON.stringify(k.said)}`);
  }
  eq(R.phonemeWordCount('wˈɛl, mˈɑli.'), 2, 'phoneme words counted before the first piece plays');
  eq(R.phonemeWordStarts([{ symbols: 'ab', frames: [1, 2] }]), null, 'frames that do not fit the symbols are refused');
});

test('the string a voice is given is exactly what the mapper maps (over real scripts)', () => {
  const said = (text) => (text || '').replace(/_/g, '').trim();
  let n = 0;
  for (const { s } of [...bundle.map(x => ({ s: x })), ...libraryScripts(30)]) {
    for (const line of s.lines) {
      const sp = R.spoken(line);
      n += 1;
      eq(sp.said, said(C.spokenText(line)), `${s.id} ${line.id}: said`);
      eq(sp.toLine.length, sp.said.length, `${s.id} ${line.id}: one offset per unit`);
      const text = C.lineText(line);
      // Every unit of the spoken string comes from the same character of the printed words (italic marks aside).
      for (let i = 0; i < sp.said.length; i++) {
        if (sp.said[i] !== ' ' && text[sp.toLine[i]] !== sp.said[i]) throw new Error(`${s.id} ${line.id}: unit ${i} ${JSON.stringify(sp.said[i])} maps to ${JSON.stringify(text[sp.toLine[i]])}`);
      }
    }
  }
  ok(n > 1000, `lines checked (${n})`);
});

(async () => {
  for (const [name, fn] of later) {
    try { await fn(); passes += 1; console.log(`  ok    ${name}`); } catch (e) { failures += 1; console.log(`  FAIL  ${name}\n        ${e.message}`); }
  }
  console.log(`${passes}/${passes + failures} passed${failures ? `, ${failures} FAILED` : ''}`);
  process.exit(failures ? 1 : 0);
})();
