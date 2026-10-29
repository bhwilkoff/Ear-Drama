/**
 * Vanilla test harness — no framework, no build step.
 *
 * Run in a browser:
 *   1. python3 -m http.server 8080
 *   2. open http://localhost:8080/js/api.test.html
 *      (or load this file from a <script> tag in an HTML page)
 * Run in node 22+:
 *   node js/api.test.js
 *
 * Pattern: every `test(...)` runs synchronously or as a Promise; results
 * print to console + (in the browser) the page. Add more tests as the
 * api.js surface grows. Mirrors the iOS Swift Testing + Android JUnit
 * + Turbine pattern — same shape, native tools.
 */

// Node fallback: api.js is a browser IIFE that attaches `API` to its
// closure. When run under node, we eval the script into the current
// context so the IIFE exports `API` and `shareTarget` as globals.
if (typeof window === 'undefined' && typeof API === 'undefined') {
  const fs = require('node:fs');
  const vm = require('node:vm');
  const src = fs.readFileSync(__dirname + '/api.js', 'utf-8');
  vm.runInThisContext(src);
}

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) {
  if (a !== b) throw new Error(msg || `expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}

// --- TESTS -----------------------------------------------------------

test('art: one helper, Commons standard widths only (contract §3.3)', () => {
  const art = API.artOf(['https://commons.wikimedia.org/wiki/Special:FilePath/A.jpg', 600, 800, null, 'https://x']);
  assertEq(art.width, 600, 'positional fields become named');
  assertEq(art.credit, null, 'no credit when none is owed');
  assertEq(API.artURL(art, 80), `${art.url}?width=120`, 'a 40 px tile at 2x takes the 120 step');
  assertEq(API.artURL(art, 224), `${art.url}?width=330`, 'a head takes the 330 step');
  assertEq(API.artURL(art, 384), `${art.url}?width=500`, 'a phone band at 2x takes the 500 step');
  assertEq(API.artURL(art, 512), `${art.url}?width=960`, 'a wide band or Now Playing takes the 960 step');
  assertEq(API.artURL(art, 2000), `${art.url}?width=960`, 'never beyond the largest step');
  assertEq(API.artOf(null), null, 'control: no art is null, never an empty picture');
  assertEq(API.artURL(null, 40), null, 'control: no art, no URL');
});

test('art: the shape decides the layout, from the published size (§6.4a)', () => {
  const at = (w, h) => API.artOf(['https://x/A.jpg', w, h, null, null]);
  assertEq(API.artShape(at(600, 800)), 'upright', 'a portrait is the print');
  assertEq(API.artShape(at(1000, 1000)), 'upright', 'a square is the print too');
  assertEq(API.artShape(at(1150, 1000)), 'upright', 'the threshold itself is still upright');
  assertEq(API.artShape(at(1830, 1000)), 'wide', 'a wide picture is the plate');
  assertEq(API.artShape(at(null, null)), 'upright', 'control: an unknown size is drawn upright, never guessed wide');
  assertEq(API.artAspect(at(null, null)), null, 'control: an unknown size has no aspect');
});

test('art: a small crop is the square around the published face (contract §3.3a golden cases)', () => {
  const at = (w, h, face) => API.artOf(['https://x/A.jpg', w, h, null, null, face]);
  const near = (got, want, msg) => {
    if (want === null) return assertEq(got, null, msg);
    assert(got && ['x', 'y', 'w', 'h'].every(k => Math.abs(got[k] - want[k]) < 1e-6),
      `${msg}: expected ${JSON.stringify(want)}, got ${JSON.stringify(got)}`);
  };
  near(API.cropRect(at(1000, 500, [0.5, 0.2, 0.1, 0.2])), { x: 0.45, y: 0.1, w: 0.2, h: 0.4 }, 'wide, small face: zoomed onto it');
  near(API.cropRect(at(1000, 500, [0.85, 0, 0.15, 0.6])), { x: 0.5, y: 0, w: 0.5, h: 1 }, 'wide, big face: the edge square');
  near(API.cropRect(at(500, 1000, [0.3, 0.25, 0.4, 0.2])), { x: 0.1, y: 0.15, w: 0.8, h: 0.4 }, 'tall: around the face');
  near(API.cropRect(at(1000, 1000, [0.4, 0.4, 0.5, 0.5])), { x: 0, y: 0, w: 1, h: 1 }, 'square, big face: the whole');
  near(API.cropRect(at(1000, 1000, [0.5, 0.5, 0.01, 0.01])), { x: 0.38, y: 0.38, w: 0.25, h: 0.25 }, 'a tiny face: at most 4x');
  near(API.cropRect(at(500, 1000, null)), { x: 0, y: 0.1, w: 1, h: 0.5 }, 'control: upright without a face keeps the top');
  near(API.cropRect(at(1000, 1000, null)), { x: 0, y: 0, w: 1, h: 1 }, 'control: a square without a face is whole');
  near(API.cropRect(at(1000, 500, null)), null, 'control: a wide picture without a face is not cropped');
  near(API.cropRect(at(null, null, [0.6, 0.1, 0.2, 0.2])), null, 'control: an unknown size keeps the plain crop');
  near(API.cropRect(API.artOf(['https://x/A.jpg', 1000, 500, null, null])), null, 'control: an older catalog without the field');
});

test('transcript fetches the URL once, as text, and never caches a failure (DECISIONS 058)', async () => {
  const real = globalThis.fetch;
  const seen = [];
  let fail = true;
  globalThis.fetch = async (url) => {
    seen.push(String(url));
    if (fail) throw new TypeError('Failed to fetch');
    return { ok: true, status: 200, text: async () => 'One.\n\n  Two.  \r\nThree.\n' };
  };
  try {
    const url = 'https://archive.org/download/x/a%20b.autogenerated.txt';
    let kind = null;
    try { await API.transcript(url); } catch (e) { kind = e.kind; }
    assertEq(kind, 'error', 'control: a refused fetch is reported, not swallowed');
    fail = false;
    const text = await API.transcript(url);
    await API.transcript(url);
    assertEq(seen.length, 2, 'the failure was retried once and the success is kept');
    assertEq(seen[1], url, 'fetched from its own URL, never re-hosted');
    assertEq(JSON.stringify(API.transcriptLines(text)), JSON.stringify(['One.', 'Two.', 'Three.']));
    assertEq(API.transcriptLabel, 'Automatic transcript');
  } finally {
    globalThis.fetch = real;
  }
});

test('onAir reads the one clock from the published instants (R10, R14)', () => {
  const slots = [
    { utc_start: '2026-10-22T23:00:00Z', utc_end: '2026-10-22T23:30:00Z' },
    { utc_start: '2026-10-22T23:30:00Z', utc_end: '2026-10-23T00:00:00Z' },
    { utc_start: '2026-10-23T00:00:00Z', utc_end: '2026-10-23T00:30:00Z' },
  ];
  const at = (iso) => API.onAir(slots, Date.parse(iso));
  assertEq(at('2026-10-22T22:59:59Z').phase, 'before', 'before the first slot');
  assertEq(at('2026-10-22T23:00:00Z').index, 0, 'the first slot starts on its instant');
  assertEq(at('2026-10-22T23:45:00Z').index, 1, 'the slot whose instants hold now');
  assertEq(at('2026-10-23T00:29:59Z').index, 2, 'the last slot until its end');
  assertEq(at('2026-10-23T00:30:00Z').phase, 'after', 'the evening ends when its last slot does (R14)');
  assertEq(API.onAir([], Date.now()).phase, 'after', 'no slots: nothing on the air');
});

test('onNow finds what a station has on, and where in it (contract §8)', () => {
  // The cases are Apple's StationsTests and Android's StationsTest.
  const slots = [
    { utc_start: '2026-10-24T18:00:00Z', utc_end: '2026-10-24T18:29:51Z', length_s: 1791,
      episode: { id: 'suspense|1947-10-16', series: 'Suspense', title: 'Self Defense' } },
    { utc_start: '2026-10-24T18:29:51Z', utc_end: '2026-10-24T18:44:51Z', length_s: 900, withheld: true },
    { utc_start: '2026-10-24T18:44:51Z', utc_end: '2026-10-24T19:14:51Z', length_s: 1800,
      episode: { id: 'whistler|1947-10-20', series: 'The Whistler' } },
  ];
  const at = (iso) => API.onNow(slots, Date.parse(iso));
  assertEq(at('2026-10-24T17:59:59Z'), null, 'before the first slot nothing is on');
  assertEq(at('2026-10-24T18:00:00Z').index, 0, 'the first slot starts on its instant');
  assertEq(at('2026-10-24T18:10:00Z').offset, 600, 'where in the slot the clock stands');
  assertEq(at('2026-10-24T18:29:50Z').index, 0, 'the slot until its end');
  assertEq(at('2026-10-24T18:29:51Z').index, 1, 'a boundary belongs to the slot that starts');
  assertEq(at('2026-10-24T18:44:51Z').offset, 0, 'the next slot starts at its own instant');
  assertEq(at('2026-10-24T19:14:50Z').index, 2, 'the last slot until its end');
  assertEq(at('2026-10-24T19:14:51Z'), null, 'after the last slot nothing is on');
  assertEq(API.onNow([], Date.now()), null, 'no slots: nothing is on');
  const from = Date.parse('2026-10-24T18:10:00Z');
  assertEq(API.ahead(slots, from, 600 * 1000).length, 1, 'ahead: only the slot on now within 10 minutes');
  assertEq(API.ahead(slots, from, 3600 * 1000).length, 3, 'ahead: every slot starting within an hour');
  assertEq(API.ahead(slots, Date.parse('2026-10-24T20:00:00Z')).length, 0, 'ahead: nothing after the window');
});

test('localDate is the person\'s own calendar date, not UTC', () => {
  assertEq(API.localDate(new Date(2026, 9, 22, 23, 30)), '2026-10-22', '11:30 PM local stays on its own date');
  assertEq(API.localDate(new Date(2026, 0, 5, 0, 5)), '2026-01-05', 'control: padding');
});

test('API exposes the data verbs', () => {
  assert(typeof API === 'object', 'API should be an object');
  for (const f of ['getJSON', 'manifest', 'seriesIndex', 'listen', 'thisDay', 'seriesPage', 'episodeDetail',
                   'searchSeries', 'searchEpisodeNumbers', 'searchDocs', 'rightsLine', 'transcript', 'tonight', 'onAir', 'stations', 'onNow', 'ahead']) {
    assert(typeof API[f] === 'function', `API.${f} should be a function`);
  }
});

// --- Listen shelves (contract §5.1) ---

test('onThisDay returns catalog/tests/golden/on_this_day.json (Feb 29, partial dates, recommendAnd)', () => {
  if (typeof require === 'undefined') return;
  const g = JSON.parse(require('node:fs').readFileSync(__dirname + '/../catalog/tests/golden/on_this_day.json', 'utf-8'));
  const rows = g.episodes.map(([id, , date, , noRecommend]) => ({ id, date, noRecommend }));
  for (const c of g.cases) {
    const got = API.onThisDay(rows, c.month, c.day, c.limit).map(e => e.id);
    assertEq(JSON.stringify(got), JSON.stringify(c.want), `${c.month}/${c.day} limit ${c.limit}`);
  }
  // Control: the flagged 1939 row is on May 25, so the case above drops it by recommendAnd, not by date.
  const cleared = rows.map(r => ({ ...r, noRecommend: null }));
  assertEq(API.onThisDay(cleared, 5, 25)[0].id, 'n|1939-05-25');
});

/** A data plane in memory: `get` answers paths like getJSON, and records what was read. */
function plane(manifestExtra, files = {}) {
  const DETAIL = ['series', 'title', 'date', 'length', 'recordings', 'li', 'ltp'];
  const detail = (series, title, date) => [series, title, date, 1770, [[`https://archive.org/download/x/${title}.mp3`]], null, null];
  const eps = {
    'comedy1|1950-01-01': detail('comedy1', 'C1', '1950-01-01'),
    'comedy2|1948-01-01': detail('comedy2', 'C2', '1948-01-01'),
    'drama1|1940-01-01': detail('drama1', 'D1', '1940-01-01'),
  };
  const data = {
    'manifest.json': { shard: { mask: 0xfff }, fields: { detail: DETAIL, recording: ['url'] }, genreNames: {}, ...manifestExtra },
    'index/series.json': { fields: ['key', 'name'], rows: [['comedy1', 'Comedy One'], ['comedy2', 'Comedy Two'], ['drama1', 'Drama One']] },
    'index/days/05-25.json': { fields: ['id', 'date', 'title', 'series', 'length', 'url', 'seriesName'], rows: [
      ['b|1950-05-25', '1950-05-25', 'B', 'b', 1, 'u', 'Bee'], ['a|1943-05-25', '1943-05-25', 'A', 'a', 1, 'u', 'Ay']] },
    ...files,
  };
  for (const [id, rec] of Object.entries(eps)) {
    const p = `episodes/${API.shardOf(id)}.json`;
    data[p] = { ...(data[p] || {}), [id]: rec };
  }
  const read = [];
  const get = async (p) => {
    read.push(p);
    if (!(p in data)) throw new API.DataError('missing', p);
    return data[p];
  };
  return { get, read };
}

test('listenShelves follows the published order and draws each id in order', async () => {
  const { get, read } = plane({ listenShelves: [
    { rule: 'genreFirsts', genre: 'comedy', episodes: ['comedy2|1948-01-01', 'comedy1|1950-01-01'] },
    { rule: 'onThisDay' },
    { rule: 'genreFirsts', genre: 'drama', episodes: ['drama1|1940-01-01', 'gone|1900-01-01'] },
    { rule: 'mostEpisodes' },
    { rule: 'genreFirsts', genre: 'western', episodes: [] },
  ] });
  const got = await API.listenShelves(new Date(2026, 4, 25), get);
  assertEq(got.map(s => s.genre ? `${s.rule}:${s.genre}` : s.rule).join(','), 'genreFirsts:comedy,onThisDay,genreFirsts:drama',
    'published order; an unknown rule ignored; an empty shelf dropped');
  assertEq(got[0].rows.map(e => e.id).join(','), 'comedy2|1948-01-01,comedy1|1950-01-01', 'ids in published order, not date order');
  assertEq(got[0].rows[0].seriesName, 'Comedy Two');
  assertEq(got[0].rows[0].url, 'https://archive.org/download/x/C2.mp3', 'playable from its first recording');
  assertEq(got[1].rows.map(e => e.id).join(','), 'a|1943-05-25,b|1950-05-25', "the person's own date, oldest first");
  assertEq(got[2].rows.map(e => e.id).join(','), 'drama1|1940-01-01', 'an id not served is dropped');
  assert(!read.includes('index/listen.json'), 'the old index is not read when the key is published');
});

test('067: listenShelves draws mostDownloaded as published ids, in order', async () => {
  const { get } = plane({ listenShelves: [
    { rule: 'onThisDay' },
    { rule: 'mostDownloaded', episodes: ['drama1|1940-01-01', 'comedy2|1948-01-01'] },
  ] });
  const got = await API.listenShelves(new Date(2026, 4, 25), get);
  const pop = got.find(s => s.rule === 'mostDownloaded');
  assert(pop, 'the popularity shelf is drawn');
  assertEq(pop.rows.map(e => e.id).join(','), 'drama1|1940-01-01,comedy2|1948-01-01', 'in the published order');
});

test('067: arcOf reads the published arc, with the next part and, on the last part, the next story', async () => {
  const DETAIL = ['series', 'title', 'date', 'length', 'recordings', 'li', 'ltp', 'arc'];
  const row = (title, arc) => ['jd', title, null, 1770, [[`https://archive.org/download/jd/${title}.mp3`]], null, null, arc];
  const rows = {
    'jd|1': row('A1', ['jd|arc|1', 1, 2, 'jd|2', null]),
    'jd|2': row('A2', ['jd|arc|1', 2, 2, null, 'jd|3']),
    'jd|3': row('B1', null),
  };
  const files = {};
  for (const [id, r] of Object.entries(rows)) {
    const p = `episodes/${API.shardOf(id)}.json`;
    files[p] = { ...(files[p] || {}), [id]: r };
  }
  const arcFields = ['id', 'part', 'parts', 'next', 'nextStory'];
  const { get } = plane({ fields: { detail: DETAIL, recording: ['url'], arc: arcFields } }, files);
  const first = await API.arcOf('jd|1', get);
  assertEq(JSON.stringify([first.part, first.parts, first.next.id, first.nextStory]), '[1,2,"jd|2",null]', 'part 1 of 2');
  assertEq(first.next.url, 'https://archive.org/download/jd/A2.mp3', 'the next part is a playable card');
  const last = await API.arcOf('jd|2', get);
  assertEq(JSON.stringify([last.next, last.nextStory.id]), '[null,"jd|3"]', 'the last part names the next story');
  assertEq(await API.arcOf('jd|3', get), null, 'outside an arc');
  assertEq(await API.arcOf('gone|1', get), null, 'an id not served');
  const old = plane({ fields: { detail: DETAIL.slice(0, 7), recording: ['url'] } }, files);
  assertEq(await API.arcOf('jd|1', old.get), null, 'control: a catalog that predates arcs has none');
});

test('series index rows expose sortName, and A to Z by it skips quotes and articles', () => {
  const rows = API.rowsOf(['key', 'name', 'sortName'],
    [['q', '"Fixture Quoted"', 'fixture quoted"'], ['t', 'The Fixture Hour', 'fixture hour']]);
  assertEq(rows.map(r => r.sortName).join('|'), 'fixture quoted"|fixture hour');
  const byName = (a, b) => (a.sortName || a.name).localeCompare(b.sortName || b.name, 'en', { sensitivity: 'base' });
  assertEq(rows.slice().sort(byName).map(r => r.key).join(''), 'tq', 'sorted by sortName, not by the raw name');
});

test('Popular: counted series first, most downloaded first; no count (a play, an older catalog) after, A to Z', () => {
  const byName = (a, b) => (a.sortName || a.name).localeCompare(b.sortName || b.name, 'en', { sensitivity: 'base' });
  const rows = API.rowsOf(['key', 'name', 'sortName', 'downloads'],
    [['01', '01 03-02', '01 03-02', null], ['s', 'Suspense', 'suspense', 900], ['g', 'Gunsmoke', 'gunsmoke', 4000],
     ['z', 'Zero', 'zero', 0], ['b', 'Bob', 'bob']]);
  rows.push({ key: 'p', name: 'A Play', sortName: 'play', kind: 'plays' });
  assertEq(rows.slice().sort(API.byDownloads(byName)).map(r => r.key).join(' '), 'g s 01 b p z',
    'counted by count, then the rest by sortName');
  const old = API.rowsOf(['key', 'name', 'sortName'], [['s', 'Suspense', 'suspense'], ['01', '01 03-02', '01 03-02']]);
  assertEq(old.sort(API.byDownloads(byName)).map(r => r.key).join(' '), '01 s', 'control: no field is A to Z');
});

test('listenShelves runs onThisDay on 29 February only on 29 February', async () => {
  const leap = { 'index/days/02-29.json': { fields: ['id', 'date'], rows: [['l|1948-02-29', '1948-02-29']] } };
  const { get } = plane({ listenShelves: [{ rule: 'onThisDay' }] }, leap);
  assertEq((await API.listenShelves(new Date(2028, 1, 29), get))[0].rows[0].id, 'l|1948-02-29');
  assertEq((await API.listenShelves(new Date(2027, 1, 28), get)).length, 0, 'control: the 28th draws nothing');
});

test('listenShelves falls back to index/listen.json when the catalog predates the key', async () => {
  const legacy = { 'index/listen.json': { fields: ['key', 'name', 'genre'],
    most: [['drama1', 'Drama One', 'drama']],
    shelves: [{ rule: 'genre', genre: 'drama', series: [['drama1', 'Drama One', 'drama']] },
              { rule: 'genre', genre: 'news', series: [] }] } };
  const { get, read } = plane({}, legacy);
  const got = await API.listenShelves(new Date(2026, 4, 25), get);
  assertEq(got.map(s => `${s.rule}:${s.genre || ''}`).join(','), 'onThisDay:,genre:drama', 'nothing goes blank; no Most episodes');
  assertEq(got[1].series[0].name, 'Drama One');
  assert(read.includes('index/listen.json'), 'control: the fallback read the old index');
});

test('shareTarget is exposed as an async function', () => {
  assert(typeof shareTarget === 'function', 'shareTarget should be a function');
  assert(shareTarget.constructor.name === 'AsyncFunction', 'shareTarget should be async');
});

// Golden vectors printed by catalog/tools/build_web_projection.py: the browser
// must find the same shard and the same words as the builder that wrote them.
test('fnv1a and shardOf match the builder', () => {
  assertEq(API.fnv1a(''), 2166136261);
  assertEq(API.fnv1a('suspense|1948-11-18'), 2877880940);
  assertEq(API.shardOf('suspense|1948-11-18'), 'a6c');
  assertEq(API.shardOf('familytheater|1948-09-30'), '000');
  assertEq(API.shardOf('Caf\u00e9 No\u00ebl|x'), '3da');
});

test('control: a different id lands in a different shard', () => {
  assert(API.shardOf('suspense|1948-11-19') !== 'a6c', 'one day later should not collide here');
});

test('tokens fold like unicode61 and match the builder', () => {
  assertEq(JSON.stringify(API.tokens('Sorry, Wrong Number (Agnes Moorehead) \u2014 Caf\u00e9 \u00d1and\u00fa 1948')),
    JSON.stringify(['sorry', 'wrong', 'number', 'agnes', 'moorehead', 'cafe', 'nandu', '1948']));
  assertEq(API.termFile('\u00f1andu'), 'xf161');
  assertEq(API.termFile('1948'), '19');
});

// --- People (contract §4 people shards, §5 withPerson) ---

test('withPerson: one row per episode with every role, grouped by series, either order, undated last', () => {
  const c = (id, date, series, role, character = null) => ({ id, date, title: id, num: null, series, role, character });
  const credits = [c('a|1940-01-01', '1940-01-01', 'a', 'cast', 'Ann'), c('a|1940-01-01', '1940-01-01', 'a', 'writer'),
                   c('b|1942-01-01', '1942-01-01', 'b', 'host'), c('a|1945-01-01', '1945-01-01', 'a', 'cast'),
                   c('b|undated', null, 'b', 'host')];
  const oldest = API.personGroups(credits);
  assertEq(oldest.map(g => `${g.series}:${g.episodes.map(e => e.id).join('+')}`).join(','),
    'a:a|1940-01-01+a|1945-01-01,b:b|1942-01-01+b|undated', 'oldest first, by series in first appearance');
  assertEq(oldest[0].episodes[0].roles.map(r => r.role).join(','), 'cast,writer', 'two credits, one row');
  assertEq(oldest[0].episodes[0].roles[0].character, 'Ann');
  const newest = API.personGroups(credits, true);
  assertEq(newest.map(g => `${g.series}:${g.episodes.map(e => e.id).join('+')}`).join(','),
    'a:a|1945-01-01+a|1940-01-01,b:b|1942-01-01+b|undated', 'newest first, undated still last');
  assertEq(API.personGroups([]).length, 0, 'control: no credits, no groups');
});

test('withPerson: years from the people row only', () => {
  assertEq(API.lifeYears('1900-12-21', '1974-04-30'), '1900–1974');
  assertEq(API.lifeYears('1915', null), 'Born 1915');
  assertEq(API.lifeYears(null, '1985'), 'Died 1985');
  assertEq(API.lifeYears(null, null), null, 'control: no facts, no line');
});

test('episodeDetail forwards a moved id (contract §3.5); a tombstoned or unknown one is not served', async () => {
  const real = globalThis.fetch;
  const files = {
    // getJSON keeps the first manifest a page reads, so this one carries the person test's fields too.
    'manifest.json': { shard: { mask: 0xfff }, fields: { detail: ['series', 'date', 'title', 'recordings', 'credits'],
      recording: ['url'], credit: ['name'], person: ['name', 'birth', 'death', 'art', 'credits'],
      personCredit: ['id', 'date', 'title', 'num', 'series', 'role', 'character'],
      people: ['id', 'name', 'episodes', 'art'] } },
    'index/aliases.json': { 'jb|1921-03-11': 'jb|1943-11-21' },
    'index/tombstones.json': ['jb|gone'],
    [`episodes/${API.shardOf('jb|1943-11-21')}.json`]: { 'jb|1943-11-21': ['jb', '1943-11-21', 'Show', [['u']], []] },
  };
  let reads = 0;
  globalThis.fetch = async (url) => {
    const path = String(url).replace(/^.*?\/data\//, '');
    if (path.startsWith('index/')) reads++;
    if (!(path in files)) return { ok: false, status: 404 };
    return { ok: true, status: 200, json: async () => files[path] };
  };
  try {
    const d = await API.episodeDetail('jb|1921-03-11');
    assertEq(d && d.id, 'jb|1943-11-21', 'the old id opens the episode it now is, under its new id');
    assertEq(await API.episodeDetail('jb|gone'), null, 'a tombstoned id is not served');
    assertEq(await API.episodeDetail('jb|1999-01-01'), null, 'control: an unknown id is not served either');
    const f = await API.forwarding();
    assertEq(f.gone('jb|gone'), true, 'the tombstones are read');
    assertEq(reads, 2, 'aliases and tombstones are read once a page');
  } finally {
    globalThis.fetch = real;
  }
});

test('withPerson and searchPeople read the person shards the builder writes', async () => {
  const real = globalThis.fetch;
  const files = {
    'manifest.json': { shard: { mask: 0xfff }, fields: {
      person: ['name', 'birth', 'death', 'art', 'credits'],
      personCredit: ['id', 'date', 'title', 'num', 'series', 'role', 'character'],
      people: ['id', 'name', 'episodes', 'art'] } },
    [`people/${API.shardOf('fx:1')}.json`]: { 'fx:1': ['Agnes Moorehead', '1900', '1974', null,
      [['suspense|1943-05-25', '1943-05-25', 'Sorry, Wrong Number', 46, 'suspense', 'cast', 'Mrs. Stevenson']]] },
    'search/people/mo.json': { fields: ['id', 'name', 'episodes', 'art'],
      rows: [['fx:1', 'Agnes Moorehead', 1, null], ['fx:2', 'Moore Jones', 3, null]] },
  };
  globalThis.fetch = async (url) => {
    const path = String(url).replace(/^.*?\/data\//, '');
    if (!(path in files)) return { ok: false, status: 404 };
    return { ok: true, status: 200, json: async () => files[path] };
  };
  try {
    const p = await API.personPage('fx:1');
    assertEq(p.name, 'Agnes Moorehead');
    assertEq(p.credits[0].character, 'Mrs. Stevenson', 'positional credit rows become named');
    assertEq(p.credits[0].series, 'suspense');
    assertEq(await API.personPage('fx:none'), null, 'control: a person with no shard is not served');
    const found = await API.searchPeople('moore agn');
    assertEq(found.rows.map(r => r.id).join(','), 'fx:1', 'every word a word prefix');
    assertEq((await API.searchPeople('moore')).rows.map(r => r.id).join(','), 'fx:1,fx:2', 'published order kept');
    assertEq((await API.searchPeople('oore')).total, 0, 'control: never substring');
  } finally {
    globalThis.fetch = real;
  }
});

test('search text: dates and snippets hold to catalog/tests/golden/search_text.json', () => {
  if (typeof require === 'undefined') return;
  const g = JSON.parse(require('node:fs').readFileSync(__dirname + '/../catalog/tests/golden/search_text.json', 'utf-8'));
  for (const c of g.dates) {
    const d = API.dateQuery(c.q);
    assertEq(d ? d.prefix : null, c.prefix, `date of ${c.q}`);
    if (d) {
      assertEq(d.rest, c.rest, `rest of ${c.q}`);
      assertEq(API.dateLabel(d.prefix), c.label, `label of ${c.q}`);
    }
  }
  for (const c of g.snippets.cases) {
    assertEq(API.transcriptSnippet(g.snippets.text, c.words, g.snippets.max), c.snippet, `snippet for ${c.words}`);
  }
  const lines = API.transcriptLines(g.snippets.text).join(' ');
  for (const c of g.snippets.cases.filter(c => c.snippet)) {
    assert(lines.includes(c.snippet.replace(/^…|…$/g, '')), `verbatim: ${c.snippet}`);
  }
});

test('searchSaidNumbers and searchAired read search/said and search/dates', async () => {
  const files = {
    'manifest.json': { search: { docChunk: 500, minWord: 2, saidMinWord: 3 } },
    'search/said/za.json': { zanzibar: [2, 5], zany: [4] },
    'search/said/ph.json': { phone: [4, 3] },
    'search/terms/su.json': { suspense: [2, 5] },
    'search/dates/1943.json': { fields: ['id', 'title', 'date', 'series', 'doc'], rows: [
      ['a|1943-05-25', 'Sorry', '1943-05-25', 'suspense', 2], ['b|1943-06-01', 'Loop', '1943-06-01', 'other', 3],
      ['c|1943-06-08', 'Late', '1943-06-08', 'suspense', 7]] },
  };
  const get = async (p) => {
    if (p in files) return files[p];
    throw Object.assign(new Error(p), { kind: 'missing' });
  };
  assertEq((await API.searchSaidNumbers('zan', get)).join(','), '2,4,7', 'word prefix, every term, ascending');
  assertEq((await API.searchSaidNumbers('zan phone', get)).join(','), '4,7', 'every word must be said');
  assertEq((await API.searchSaidNumbers('of zanz', get)).join(','), '2,7', 'a word under saidMinWord is not searched');
  assertEq((await API.searchSaidNumbers('anzi', get)).length, 0, 'control: never substring');
  assertEq((await API.searchSaidNumbers('of', get)).length, 0, 'control: only short words, nothing searched');
  const june = await API.searchAired('June 1943', get);
  assertEq(june.prefix, '1943-06');
  assertEq(june.rows.map(r => r.id).join(','), 'b|1943-06-01,c|1943-06-08', 'the month, oldest first');
  assertEq((await API.searchAired('1943-05-25', get)).rows.map(r => r.id).join(','), 'a|1943-05-25', 'the day');
  assertEq((await API.searchAired('1944', get)).rows.length, 0, 'control: a year with no file is empty');
  assertEq((await API.searchAired('Suspense 1943', get)).rows.map(r => r.id).join(','), 'a|1943-05-25,c|1943-06-08',
    'the other words narrow the date by title, series, people');
  assertEq(await API.searchAired('sorry wrong', get), null, 'control: no date named, no section');
});

// Plain JS has no compiler: every API.x a script calls must be exported.
test('every API.x called in js/*.js is exported', () => {
  if (typeof require === 'undefined') return;
  const fs = require('node:fs');
  const called = new Set();
  for (const f of fs.readdirSync(__dirname).filter(f => f.endsWith('.js') && !f.endsWith('.test.js'))) {
    for (const m of fs.readFileSync(__dirname + '/' + f, 'utf-8').matchAll(/\bAPI\.([A-Za-z]+)/g)) called.add(m[1]);
  }
  const missing = [...called].filter(n => !(n in API));
  assertEq(missing.join(','), '');
  assert(!('notAVerb' in API), 'control: the check can fail');
});

test('the offline line comes with no network and goes when it returns; ?offline=1 holds it (WEB-DESIGN §7.3)', () => {
  const had = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  const setOnline = (v) => Object.defineProperty(globalThis, 'navigator', { value: { onLine: v }, configurable: true });
  try {
    setOnline(false);
    assertEq(API.offlineLine(), 'You are offline.', 'offline shows the line');
    assertEq(API.isOffline(), true);
    setOnline(true);
    assertEq(API.offlineLine(), null, 'back online, the line goes');
    if (typeof require === 'function') {
      const vm = require('node:vm');
      const src = require('node:fs').readFileSync(__dirname + '/api.js', 'utf-8');
      const door = (search) => {
        const ctx = vm.createContext({ URL, URLSearchParams, AbortSignal, setTimeout, navigator: { onLine: true },
          location: { protocol: 'http:', href: 'http://localhost/', search } });
        vm.runInContext(src + ';globalThis.API = API;', ctx);
        return ctx.API;
      };
      assertEq(door('?offline=1').offlineLine(), 'You are offline.', 'the door holds the line while the network is up');
      assertEq(door('?view=home').offlineLine(), null, 'control: no door, no line');
    }
  } finally {
    if (had) Object.defineProperty(globalThis, 'navigator', had); else delete globalThis.navigator;
  }
});

test('cropBlobURL draws the face square into the canvas, or keeps the plain URL', async () => {
  const art = API.artOf(['https://x/A.jpg', 1000, 500, null, null, [0.5, 0.2, 0.1, 0.2]]);
  const calls = [];
  const env = (ok) => ({
    fetch: async (u, o) => { calls.push([u, o.mode]); return { ok, blob: async () => 'b' }; },
    createImageBitmap: async () => ({ width: 1000, height: 500 }),
    canvas: () => ({ getContext: () => ({ drawImage: (...a) => calls.push(a) }), toBlob: (cb) => cb('png') }),
    createObjectURL: () => 'blob:crop',
  });
  assertEq(await API.cropBlobURL(art, 500, env(true)), 'blob:crop');
  assertEq(calls[0][1], 'cors', 'a CORS fetch, so the canvas stays readable');
  const d = calls[1];
  assertEq([d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8]].map(v => Math.round(v)).join(','), '450,50,200,200,0,0,500,500', 'the cropRect square');
  assertEq(await API.cropBlobURL(art, 500, env(false)), null, 'control: a refused fetch keeps the plain URL');
  const wide = API.artOf(['https://x/A.jpg', 1000, 500, null, null]);
  assertEq(await API.cropBlobURL(wide, 500, env(true)), null, 'control: nothing to crop');
});

// --- RUNNER ----------------------------------------------------------

async function run() {
  let passed = 0, failed = 0;
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`✓ ${name}`);
      passed++;
    } catch (e) {
      console.error(`✗ ${name}: ${e.message}`);
      failed++;
    }
  }
  const summary = `${passed} passed, ${failed} failed`;
  console.log(summary);
  if (typeof document !== 'undefined') {
    const el = document.createElement('pre');
    el.textContent = summary;
    document.body.appendChild(el);
  }
  if (typeof process !== 'undefined' && failed > 0) process.exit(1);
}

// Auto-run in browser; explicit invocation in node.
if (typeof window !== 'undefined') {
  window.addEventListener('load', run);
} else {
  run();
}
