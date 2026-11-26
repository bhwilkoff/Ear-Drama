/**
 * Finding a play (B31 §3, WEB-DESIGN §4.15 item 3, §4.6), run against the SHIPPED js/api.js and js/find-core.js
 * over a fixture index shaped as contract §4.1 "Finding a play" publishes it (never the real catalog's contents):
 * the facets and their counts against each other (no choice yields nothing), a value an old link names dropped,
 * share URLs that round-trip, rails that never repeat a play and lead with the editor's, an empty editor file that
 * draws nothing, search by title, character and spoken line (the words in order before scattered ones), and
 * negative controls that must fail.
 *   node js/find.test.js
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const API_SRC = fs.readFileSync(path.join(__dirname, 'api.js'), 'utf8');
const CORE_SRC = fs.readFileSync(path.join(__dirname, 'find-core.js'), 'utf8');
function load(core) {
  const ctx = vm.createContext({ console, URL, URLSearchParams, setTimeout, clearTimeout });
  vm.runInContext(API_SRC, ctx, { filename: 'api.js' });
  vm.runInContext(core.replace(/^if \(typeof module[^\n]*$/m, ''), ctx, { filename: 'find-core.js' });
  return vm.runInContext('FindCore', ctx);
}
const F = load(CORE_SRC);

let passes = 0, failures = 0;
async function test(name, fn) {
  try { await fn(); passes += 1; console.log(`  ok    ${name}`); }
  catch (e) { failures += 1; console.log(`  FAIL  ${name}\n        ${e.message}`); }
}
function ok(v, msg) { if (!v) throw new Error(msg); }

const row = (id, title, o = {}) => ({ id, title, sort_name: title.replace(/^(The|A) /, ''), authors: [o.author || 'Ann Writer'], voices: o.voices || 2,
  minutes: o.minutes || 10, cast: o.cast || [10, 8], ...o });
const rows = [
  row('a', 'Alpha', { voices: 2, minutes: 8, form: 'comedy', era: '1900-1930', balance: 'ensemble', oneAct: true, subjects: ['Ireland'], locc: 'PR',
    scenes: [{ line: 'L0003', heading: 'Scene I', voices: 2, minutes: 4, parts: ['JACK', 'JILL'] }] }),
  row('b', 'Beta', { voices: 4, minutes: 35, form: 'tragedy', era: '1800s', balance: 'lead', locc: 'PT' }),
  row('c', 'The Gamma', { voices: 2, minutes: 15, era: '1800s', balance: 'mixed', locc: 'PR',
    scenes: [{ line: 'L0010', heading: 'Act II', voices: 2, minutes: 6, parts: ['ANN', 'BOB'] }, { line: 'L0090', heading: 'Act III', voices: 3, minutes: 3, parts: ['A', 'B', 'C'] }] }),
  row('d', 'Delta', { voices: 12, minutes: 120, form: 'melodrama', balance: 'ensemble', locc: 'PS' }),
  row('e', 'Epsilon', { voices: 6, minutes: 50, form: 'comedy', era: '1600s', balance: 'mixed', author: 'Ben Bard', locc: 'PR' }),
  row('f', 'Zeta', { voices: 3, minutes: 9, form: 'comedy', era: '1600s', balance: 'mixed', author: 'Ben Bard', locc: 'PR' }),
];
const index = { format: 1, plays: rows, facets: {
  voices: [{ min: 1, max: 2, count: 2 }, { min: 3, max: 4, count: 2 }, { min: 5, max: 6, count: 1 }, { min: 7, max: 10, count: 0 }, { min: 11, max: null, count: 1 }],
  minutes: [{ min: 1, max: 10, count: 2 }, { min: 11, max: 20, count: 1 }, { min: 21, max: 40, count: 1 }, { min: 41, max: 90, count: 1 }, { min: 91, max: null, count: 1 }],
  // melodrama is on one play, under foldUnder: the index counts it under "Not named" (value null).
  form: [{ value: 'comedy', count: 3 }, { value: 'tragedy', count: 1 }, { value: null, count: 2 }],
  era: [{ value: '1600s', count: 2 }, { value: '1800s', count: 2 }, { value: '1900-1930', count: 1 }, { value: null, count: 1 }],
  balance: [{ value: 'ensemble', count: 2 }, { value: 'mixed', count: 3 }, { value: 'lead', count: 1 }],
  subjects: [{ value: 'Ireland', count: 1 }], locc: [{ value: 'PR', count: 4 }, { value: 'PT', count: 1 }, { value: 'PS', count: 1 }], oneAct: 1,
} };
const collections = { format: 1, editor: [], data: [
  { id: 'two-voices', title: 'Plays for two voices', rule: 'voices 2', count: 2, plays: ['a', 'c'] },
  { id: 'ten-minutes', title: 'Ten minutes or less', rule: 'minutes <= 10', count: 2, plays: ['a', 'f'] },
  { id: 'one-act', title: 'One Act Plays', count: 1, plays: ['a'] },
  { id: 'author-bard', kind: 'author', title: 'Ben Bard', count: 2, plays: ['e', 'f'] },
] };

(async () => {
  const facets = F.facetsOf(index);

  await test('the facets are the index\'s: voices and length bins, form with Not named, era with Undated, the Filters\' four', () => {
    ok(facets.map(f => f.key).join() === 'voices,length,balance,form,era,subject,locc,oneact', facets.map(f => f.key).join());
    const form = facets.find(f => f.key === 'form');
    ok(form.values.map(v => v.label).join() === 'Comedy,Tragedy,Not named', form.values.map(v => v.label).join());
    ok(form.of(rows[3]).join() === 'none', 'a folded form (melodrama, under five) counts as Not named');
    ok(facets.find(f => f.key === 'length').values.map(v => v.label).join() === 'Up to 10 min,10-20 min,20-40 min,40-90 min,Longer', 'length labels');
    ok(facets.find(f => f.key === 'voices').values.map(v => v.label).join() === '1-2,3-4,5-6,7-10,11+', 'voice labels');
  });

  await test('counts run against the other picks; a value with nothing is left out unless chosen', () => {
    const c = F.counts(rows, facets, { form: 'comedy' });
    const v = c.find(f => f.key === 'voices').values;
    ok(v.map(x => `${x.value}:${x.count}`).join() === '1-2:1,3-4:1,5-6:1', v.map(x => `${x.value}:${x.count}`).join());
    const form = c.find(f => f.key === 'form').values;
    ok(form.find(x => x.value === 'comedy').count === 3 && form.find(x => x.value === 'tragedy').count === 1, 'form counts ignore the form pick');
    const chosen = F.counts(rows, facets, { voices: '7-10' }).find(f => f.key === 'voices').values;
    ok(chosen.some(x => x.value === '7-10' && x.count === 0), 'a chosen empty value stays');
    for (const f of F.counts(rows, facets, { era: '1600s' })) for (const x of f.values) {
      ok(F.filter(rows, facets, { era: '1600s', [f.key]: x.value }).length === x.count, `${f.key}=${x.value} yields ${x.count}`);
    }
  });

  await test('the address: a state round-trips, an old link\'s band is dropped, and the default sort is not written', () => {
    const st = F.stateFrom(new URLSearchParams('view=record&voices=1-2&form=comedy&sort=name&oneact=1&length=short'), facets);
    ok(st.picks.voices === '1-2' && st.picks.form === 'comedy' && st.picks.oneact === '1' && !st.picks.length, JSON.stringify(st.picks));
    const url = F.urlOf(st, facets);
    ok(url === '?view=record&voices=1-2&form=comedy&oneact=1&sort=name', url);
    ok(JSON.stringify(F.stateFrom(new URLSearchParams(url.slice(1)), facets).picks) === JSON.stringify(st.picks), 'round trip');
    ok(F.urlOf(F.stateFrom(new URLSearchParams('view=record'), facets), facets) === '?view=record', 'bare');
    ok(F.urlOf(st, facets, { picks: { form: '' } }) === '?view=record&voices=1-2&oneact=1&sort=name', 'clearing one pick');
  });

  await test('the ways in: scenes, then the data rails in order; a play appears once; an empty editor file draws nothing', () => {
    const rs = F.rails(rows, collections);
    ok(rs.map(r => r.id).join() === 'scenes-2,ten-minutes', rs.map(r => r.id).join());
    ok(rs[1].plays.map(p => p.id).join() === 'f', 'Ten minutes drops Alpha, which the scenes rail holds');
    const seen = new Set();
    for (const r of rs) for (const id of (r.plays || r.scenes.map(s => s.row)).map(x => x.id)) { ok(!seen.has(id), `${id} twice`); seen.add(id); }
    ok(rs[0].count === 2, 'the scenes rail counts every play with a scene for two');
    ok(!rs.some(r => r.kind === 'editor'), 'no editor rail from an empty file');
    const ed = F.rails(rows, { ...collections, editor: [{ id: 'ed1', title: 'For a pair', by: 'Ben', plays: ['c', 'a', 'gone'] }] });
    ok(ed[0].kind === 'editor' && ed[0].by === 'Ben' && ed[0].plays.map(p => p.id).join() === 'c,a', 'the editor\'s rail leads, ids that do not resolve dropped');
    ok(F.rails(rows, null).map(r => r.id).join() === 'scenes-2', 'no collections file: the scenes rail alone');
    const mutant = load(CORE_SRC.replace("if (r && !seen.has(id))", 'if (r)'));
    const again = mutant.rails(rows, { ...collections, editor: [{ id: 'ed1', title: 'x', plays: ['a', 'f'] }] });
    const ids = again.flatMap(r => (r.plays || []).map(p => p.id));
    ok(ids.length !== new Set(ids).size, 'negative control: the mutant repeats a play');
  });

  await test('a collection keeps its own order; same voices and length; more by the author', () => {
    ok(F.collection(rows, collections, 'ten-minutes').plays.map(p => p.id).join() === 'a,f', 'order');
    ok(F.collection(rows, collections, 'nope') === null, 'unknown');
    ok(F.sameShape(rows, rows[0]).map(p => p.id).join() === 'c,f', F.sameShape(rows, rows[0]).map(p => p.id).join());
    const by = F.byAuthor(rows, collections, rows[4]);
    ok(by.id === 'author-bard' && by.plays.map(p => p.id).join() === 'f', JSON.stringify(by));
  });

  await test('search: title and author prefixes; characters by name, most lines first', () => {
    ok(F.titleHits(rows, 'gam').map(r => r.id).join() === 'c', 'title prefix');
    ok(F.titleHits(rows, 'ben').map(r => r.id).join() === 'e,f', 'author');
    const names = { CANDIDA: [[0, 141], [3, 77]], 'LADY CANDIDA': [[1, 5]], BOB: [[2, 9]] };
    const c = F.characterHits(rows, names, 'candida');
    ok(c.map(h => `${h.row.id}:${h.lines}`).join() === 'a:141,d:77,b:5', c.map(h => `${h.row.id}:${h.lines}`).join());
  });

  await test('lines: the shards intersect every word; an exact word is kept apart from a prefix', async () => {
    const shards = { qu: { quality: [0, 2], qualityless: [1] }, me: { mercy: [2, 1], mercyful: [1], merry: [0] } };
    const got = await F.saidPlays('quality of mercy', (f) => Promise.resolve(shards[f] || {}));
    ok(got.exact.join() === '2', `exact ${got.exact}`);
    ok(got.all.join() === '1,2', `all ${got.all}`);
    ok((await F.saidPlays('the quality', (f) => Promise.resolve(shards[f] || {}))).all.length === 0, 'a word no play says finds nothing');
    ok((await F.saidPlays('of', () => ({}))).all.length === 0, 'short words alone search nothing');
  });

  await test('the best line: the words in order before scattered ones', () => {
    const script = { lines: [
      { id: 'L1', kind: 'speech', role: 'ANN', text: 'Of mercy, the quality is great.' },
      { id: 'L2', kind: 'speech', role: 'PORTIA', text: 'The quality of mercy is not strained.' },
    ] };
    const b = F.bestLine(script, 'quality of mercy', (l) => l.text, (l) => l.role);
    ok(b && b.line === 'L2' && b.order === true && b.role === 'PORTIA', JSON.stringify(b));
    const s = F.bestLine({ lines: [script.lines[0]] }, 'quality of mercy', (l) => l.text, (l) => l.role);
    ok(s && s.order === false, 'scattered when nothing is in order');
    const mutant = load(CORE_SRC.replace('return { ...hit, order: true, at: i };', 'continue;'));
    ok(mutant.bestLine(script, 'quality of mercy', (l) => l.text, (l) => l.role).line === 'L1', 'negative control: without the order rule the first scattered line wins');
    ok(F.snippet('word '.repeat(60) + 'mercy ' + 'tail '.repeat(40), 'mercy', 60).startsWith('…'), 'a long line is cut with …');
    const cand = { lines: [
      { id: 'L1', kind: 'direction', text: 'Candida enters.' },
      { id: 'L2', kind: 'speech', role: 'DUNN', text: 'He is not a candidate.' },
      { id: 'L3', kind: 'speech', role: 'MORELL', text: 'A wife like my Candida.' },
    ] };
    ok(F.bestLine(cand, 'candida', (l) => l.text, (l) => l.role).line === 'L3', 'the whole word before a prefix, and never a direction');
    ok(F.snippet('beside _Geltrude_ and _Candida_', 'candida') === 'beside Geltrude and Candida', 'italic marks are not shown');
  });

  await test('a library built before B31 (no facets): voices and length from the stand-in bins, nothing else', () => {
    const fs0 = F.facetsOf({ plays: rows });
    ok(fs0.map(f => f.key).join() === 'voices,length', fs0.map(f => f.key).join());
    ok(F.counts(rows, fs0, {}).find(f => f.key === 'voices').values.reduce((a, v) => a + v.count, 0) === rows.length, 'every play in one bin');
  });

  console.log(`${failures ? 'FAIL' : 'PASS'}: ${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})();
