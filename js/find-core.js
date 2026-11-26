/**
 * Finding a play (B31 §3, WEB-DESIGN §4.15 item 3, §4.6): the facets, the ways in and the search over the play
 * library's index, as pure functions with no DOM, so js/find.test.js runs this file as shipped. Every value and
 * bound comes from the catalog (contract §4.1 "Finding a play": the rows' `form`, `era`, `balance`, `subjects`,
 * `locc`, `oneAct`, `scenes`; the index's `facets`; `collections.json`; `characters.json`; `search/said/`); this
 * file only counts and filters what the catalog computed. Nothing ranks by attention.
 */
const FindCore = (() => {
  'use strict';

  // The bins the catalog publishes (index.facets.voices / .minutes); these stand in only for a library built before
  // B31 C3 or the bundled scripts, and are the same numbers (B31 §3.1).
  const VOICE_BINS = [{ min: 1, max: 2 }, { min: 3, max: 4 }, { min: 5, max: 6 }, { min: 7, max: 10 }, { min: 11, max: null }];
  const MINUTE_BINS = [{ min: 1, max: 10 }, { min: 11, max: 20 }, { min: 21, max: 40 }, { min: 41, max: 90 }, { min: 91, max: null }];

  const FORM_LABEL = { comedy: 'Comedy', farce: 'Farce', tragedy: 'Tragedy', tragicomedy: 'Tragicomedy', history: 'History',
                       fantasy: 'Fairy and fantasy', religious: 'Religious', melodrama: 'Melodrama', libretto: 'Libretto' };
  const BALANCE_LABEL = { ensemble: 'Ensemble', mixed: 'Mixed', lead: 'A star part' };
  // The Library of Congress's own class names for its P subclasses (the record's LoCC), shortened to the language.
  const LOCC_LABEL = { PA: 'Greek and Latin', PB: 'Celtic', PC: 'Romance', PD: 'Germanic', PE: 'English language', PF: 'Dutch and Frisian',
                       PG: 'Slavic', PH: 'Finnish and Hungarian', PJ: 'Middle Eastern', PK: 'Indian and Iranian', PL: 'East Asian',
                       PM: 'Indigenous American', PN: 'General', PQ: 'French, Italian, Spanish', PR: 'English', PS: 'American',
                       PT: 'German, Dutch, Scandinavian', PZ: 'Children’s' };
  const SORTS = { voices: 'Fewest voices', short: 'Shortest', name: 'A to Z' };

  const voicesOf = (r) => (Number.isFinite(r.voices) ? r.voices : Array.isArray(r.roles) ? r.roles.length : 0);
  const minutesOf = (r) => (Number.isFinite(r.minutes) ? r.minutes : 0);
  const binKey = (b) => (b.max === null || b.max === undefined ? `${b.min}+` : `${b.min}-${b.max}`);
  const inBin = (b, n) => n >= b.min && (b.max === null || b.max === undefined || n <= b.max);

  /** The facets this library offers: each `{ key, label, values: [{ value, label }], of(row) -> [values] }`. */
  function facetsOf(index) {
    const F = (index && index.facets) || {};
    const bins = (list, fallback) => (Array.isArray(list) && list.length ? list.map(({ min, max }) => ({ min, max })) : fallback);
    const vb = bins(F.voices, VOICE_BINS), mb = bins(F.minutes, MINUTE_BINS);
    const named = (list) => new Set((list || []).map(v => v.value).filter(v => v !== null && v !== undefined));
    const forms = named(F.form), eras = named(F.era);
    const vLabel = (b) => (b.max === null || b.max === undefined ? `${b.min}+` : b.min === b.max ? String(b.min) : `${b.min}-${b.max}`);
    const mLabel = (b, i) => (b.max === null || b.max === undefined ? 'Longer' : i === 0 ? `Up to ${b.max} min` : `${b.min - 1}-${b.max} min`);
    const out = [
      { key: 'voices', label: 'Voices', values: vb.map(b => ({ value: binKey(b), label: vLabel(b) })),
        of: (r) => vb.filter(b => inBin(b, voicesOf(r))).map(binKey) },
      { key: 'length', label: 'Length', values: mb.map((b, i) => ({ value: binKey(b), label: mLabel(b, i) })),
        of: (r) => mb.filter(b => inBin(b, minutesOf(r))).map(binKey) },
    ];
    if (F.balance) out.push({ key: 'balance', label: 'How the lines are shared', filter: true,
      values: F.balance.filter(v => BALANCE_LABEL[v.value]).map(v => ({ value: v.value, label: BALANCE_LABEL[v.value] })),
      of: (r) => (BALANCE_LABEL[r.balance] ? [r.balance] : []) });
    if (F.form) out.push({ key: 'form', label: 'Form',
      values: [...F.form.filter(v => v.value !== null && FORM_LABEL[v.value]).map(v => ({ value: v.value, label: FORM_LABEL[v.value] })),
               { value: 'none', label: 'Not named' }],
      // A form on fewer plays than the catalog's foldUnder is counted with Not named, as the index counts it.
      of: (r) => [forms.has(r.form) ? r.form : 'none'] });
    if (F.era) out.push({ key: 'era', label: 'Era',
      values: [...F.era.filter(v => v.value !== null).map(v => ({ value: v.value, label: v.value })), { value: 'none', label: 'Undated' }],
      of: (r) => [eras.has(r.era) ? r.era : 'none'] });
    if (Array.isArray(F.subjects) && F.subjects.length) out.push({ key: 'subject', label: 'Subject', filter: true,
      values: F.subjects.map(v => ({ value: v.value, label: v.value })),
      of: (r) => (Array.isArray(r.subjects) ? r.subjects : []) });
    if (Array.isArray(F.locc) && F.locc.length) out.push({ key: 'locc', label: 'Literature of the original', filter: true,
      values: F.locc.filter(v => v.value && LOCC_LABEL[String(v.value).slice(0, 2)]).map(v => ({ value: v.value, label: LOCC_LABEL[String(v.value).slice(0, 2)] })),
      of: (r) => (r.locc ? [r.locc] : []) });
    if (Number.isFinite(F.oneAct) && F.oneAct > 0) out.push({ key: 'oneact', label: 'One act', filter: true,
      values: [{ value: '1', label: 'One act' }], of: (r) => (r.oneAct ? ['1'] : []) });
    return out;
  }

  /** The chosen values from the address, a value the library does not offer dropped (an old link's band). */
  function stateFrom(params, facets) {
    const get = (k) => (params && typeof params.get === 'function' ? params.get(k) : params && params[k]) || '';
    const st = { picks: {}, sort: SORTS[get('sort')] ? get('sort') : 'voices', q: get('q').trim(), collection: get('collection'),
                 scenes: /^[234]$/.test(get('scenes')) ? +get('scenes') : 0 };
    for (const f of facets) { const v = get(f.key); if (v && f.values.some(x => x.value === v)) st.picks[f.key] = v; }
    return st;
  }
  /** The share address of a state (`?view=record&voices=&length=&form=&era=&sort=` and the Filters' keys). */
  function urlOf(st, facets, over = {}) {
    const v = { ...st, ...over, picks: { ...st.picks, ...(over.picks || {}) } };
    const p = new URLSearchParams({ view: 'record' });
    for (const f of facets) if (v.picks[f.key]) p.set(f.key, v.picks[f.key]);
    if (v.sort && v.sort !== 'voices') p.set('sort', v.sort);
    if (v.collection) p.set('collection', v.collection);
    if (v.scenes) p.set('scenes', String(v.scenes));
    if (v.q) p.set('q', v.q);
    return `?${p}`;
  }
  const active = (st) => Object.keys(st.picks).length > 0;

  /** The rows that pass every pick but `skip`'s. */
  function filter(rows, facets, picks, skip = null) {
    const fs = facets.filter(f => f.key !== skip && picks[f.key]);
    return rows.filter(r => fs.every(f => f.of(r).includes(picks[f.key])));
  }
  /** Each facet's values with their counts against the other picks (WEB-DESIGN §10.5: no choice yields nothing);
      a value with no plays is left out unless it is the one chosen. */
  function counts(rows, facets, picks) {
    return facets.map(f => {
      const pool = filter(rows, facets, picks, f.key), c = new Map();
      for (const r of pool) for (const v of f.of(r)) c.set(v, (c.get(v) || 0) + 1);
      return { ...f, values: f.values.map(x => ({ ...x, count: c.get(x.value) || 0 })).filter(x => x.count || picks[f.key] === x.value) };
    });
  }

  const nameKey = (r) => r.sort_name || r.title || '';
  const byName = (a, b) => nameKey(a).localeCompare(nameKey(b), 'en', { sensitivity: 'base' });
  const SORTERS = {
    voices: (a, b) => voicesOf(a) - voicesOf(b) || minutesOf(a) - minutesOf(b) || byName(a, b),
    short: (a, b) => minutesOf(a) - minutesOf(b) || byName(a, b),
    name: byName,
  };
  const sorted = (rows, sort) => rows.slice().sort(SORTERS[sort] || SORTERS.voices);

  /* ---- The ways in (B31 §3.1, §3.2) ---- */

  // The data collections that lead, in this order, after the editor's (§3.1); the rest stay reachable by address.
  const RAIL_IDS = ['ten-minutes', 'two-voices', 'star-part', 'one-act'];

  /** The rails: the editor's collections, then Scenes for two voices, then the data rails RAIL_IDS names. A play
      appears once on the screen: a rail drops a play a rail above it holds (Decision 081 rule 5), and a rail left
      with nothing is absent. `per` is how many a rail shows. */
  function rails(rows, collections, { per = 12 } = {}) {
    const byId = new Map(rows.map(r => [r.id, r]));
    const seen = new Set(), out = [];
    const take = (ids) => { const got = []; for (const id of ids) { if (got.length >= per) break; const r = byId.get(id); if (r && !seen.has(id)) { got.push(r); seen.add(id); } } return got; };
    const C = collections || {};
    for (const c of C.editor || []) {
      const plays = take(c.plays || []);
      if (plays.length) out.push({ kind: 'editor', id: c.id, title: c.title, by: c.by || null, note: c.note || null, count: (c.plays || []).filter(id => byId.has(id)).length, plays });
    }
    const scenes = sceneRows(rows, 2);
    const sceneShown = [];
    for (const s of scenes) { if (sceneShown.length >= per) break; if (!seen.has(s.row.id)) { sceneShown.push(s); seen.add(s.row.id); } }
    if (sceneShown.length) out.push({ kind: 'scenes', id: 'scenes-2', voices: 2, title: 'Scenes for two voices', count: new Set(scenes.map(s => s.row.id)).size, scenes: sceneShown });
    const data = new Map((C.data || []).map(c => [c.id, c]));
    for (const id of RAIL_IDS) {
      const c = data.get(id);
      if (!c) continue;
      const plays = take(c.plays || []);
      if (plays.length) out.push({ kind: 'data', id: c.id, title: c.title, count: Number.isFinite(c.count) ? c.count : (c.plays || []).length, plays });
    }
    return out;
  }
  /** One collection by id, editor's or data's, its plays in the collection's own order. */
  function collection(rows, collections, id) {
    const C = collections || {}, byId = new Map(rows.map(r => [r.id, r]));
    const c = [...(C.editor || []), ...(C.data || [])].find(x => x.id === id);
    if (!c) return null;
    return { id: c.id, title: c.title, by: c.by || null, note: c.note || null, plays: (c.plays || []).map(p => byId.get(p)).filter(Boolean) };
  }
  /** Every scene for `voices` voices, a play's first one per play first (text order), then plays A to Z. */
  function sceneRows(rows, voices) {
    const out = [];
    for (const r of rows) {
      const s = (Array.isArray(r.scenes) ? r.scenes : []).find(x => x && x.voices === voices && x.line);
      if (s) out.push({ row: r, scene: s });
    }
    return out.sort((a, b) => byName(a.row, b.row));
  }

  /** Same voices and length (B31 §3.5): within one voice and 15 minutes of the play, closest first, the play left out. */
  function sameShape(rows, play, n = 12) {
    const v = voicesOf(play), m = minutesOf(play);
    return rows.filter(r => r.id !== play.id && Math.abs(voicesOf(r) - v) <= 1 && Math.abs(minutesOf(r) - m) <= 15)
      .sort((a, b) => (Math.abs(voicesOf(a) - v) + Math.abs(minutesOf(a) - m) / 15) - (Math.abs(voicesOf(b) - v) + Math.abs(minutesOf(b) - m) / 15) || byName(a, b))
      .slice(0, n);
  }
  /** More by the author: the author's collection when the catalog published one, else the rows that name them first. */
  function byAuthor(rows, collections, play, n = 12) {
    const a = Array.isArray(play.authors) && play.authors[0];
    if (!a) return { plays: [], id: null };
    const name = typeof a === 'string' ? a : a.display || a.name;
    const c = ((collections || {}).data || []).find(x => x.kind === 'author' && x.title && name && x.title.endsWith(name));
    const first = (r) => { const x = Array.isArray(r.authors) && r.authors[0]; return x && (typeof x === 'string' ? x : x.display || x.name); };
    const list = c ? collection(rows, collections, c.id).plays : rows.filter(r => first(r) === name).sort(byName);
    return { plays: list.filter(r => r.id !== play.id).slice(0, n), id: c ? c.id : null, total: list.filter(r => r.id !== play.id).length };
  }

  /* ---- Search (B31 §3.3): titles and authors, characters, spoken lines ---- */

  const tokens = (text) => (typeof API !== 'undefined' ? API.tokens(text) : String(text || '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean));
  const authorText = (r) => (Array.isArray(r.authors) ? r.authors.map(a => (typeof a === 'string' ? a : a.display || a.name || '')).join(' ') : '');

  /** Plays whose title or author has every query word as a word prefix, A to Z. */
  function titleHits(rows, q) {
    const words = tokens(q);
    if (!words.length) return [];
    return rows.filter(r => { const have = tokens(`${r.title} ${authorText(r)}`); return words.every(w => have.some(h => h.startsWith(w))); }).sort(byName);
  }
  /** Characters (characters.json `names`): a role whose name has every query word as a word prefix; each hit is
      `{ row, role, lines }`, most lines first. `rows` is the index the file was built with (play numbers are places). */
  function characterHits(rows, names, q, n = 20) {
    const words = tokens(q);
    if (!words.length || !names) return [];
    const out = [];
    for (const name in names) {
      const have = tokens(name);
      if (!words.every(w => have.some(h => h.startsWith(w)))) continue;
      for (const [num, lines] of names[name]) { const row = rows[num]; if (row) out.push({ row, role: name, lines }); }
    }
    return out.sort((a, b) => b.lines - a.lines || byName(a.row, b.row)).slice(0, n);
  }
  /** The words a line search reads: three letters or more, as the shards file them. */
  const saidWords = (q) => [...new Set(tokens(q).filter(w => w.length >= 3))];
  /** Play numbers whose spoken words hold every query word, from the shards `get(file)` returns ({word: deltas}).
      An exact word is a stronger hit than a prefix: `exact` holds the plays where every word is a whole word. */
  async function saidPlays(q, get) {
    const words = saidWords(q);
    if (!words.length) return { all: [], exact: [] };
    let all = null, exact = null;
    for (const w of words) {
      const terms = await get(termFile(w));
      const pre = new Set(), ex = new Set();
      for (const t in terms || {}) {
        if (!t.startsWith(w)) continue;
        let n = 0;
        for (const d of terms[t]) { n += d; pre.add(n); if (t === w) ex.add(n); }
      }
      all = all === null ? pre : new Set([...all].filter(n => pre.has(n)));
      exact = exact === null ? ex : new Set([...exact].filter(n => ex.has(n)));
      if (!all.size) return { all: [], exact: [] };
    }
    const asc = (s) => [...s].sort((a, b) => a - b);
    return { all: asc(all), exact: asc(exact) };
  }
  function termFile(word) {
    if (typeof API !== 'undefined' && API.termFile) return API.termFile(word);
    const p = Array.from(word).slice(0, 2).join('');
    return /^[a-z0-9]{2}$/.test(p) ? p : 'x' + Array.from(p).map(c => c.codePointAt(0).toString(16)).join('');
  }
  /** A word's line postings (search/lines, contract §4.1) as a Map of play number to its line places. */
  function decodeLines(flat) {
    const out = new Map();
    let i = 0, play = 0;
    while (i < flat.length) {
      play += flat[i];
      const n = flat[i + 1], lines = [];
      let line = 0;
      for (let k = 0; k < n; k++) { line += flat[i + 2 + k]; lines.push(line); }
      out.set(play, lines);
      i += 2 + n;
    }
    return out;
  }
  /** The plays with one speech line holding every query word, from the line shards `get(file)` returns, each
      `{ play, lines }`; the rarest word is intersected first. A word the shards hold whole is matched whole, else as
      a prefix (`prefix` names those words, for the check in the script). Null when the library has no line shards. */
  async function lineCandidates(q, get) {
    const words = saidWords(q);
    if (!words.length) return { cands: [], prefix: new Set(), words };
    const sets = [], prefix = new Set();
    for (const w of words) {
      const terms = await get(termFile(w));
      if (terms === null) return null;
      const keys = terms && terms[w] ? [w] : Object.keys(terms || {}).filter(t => t.startsWith(w));
      if (!(terms && terms[w])) prefix.add(w);
      const m = new Map();
      let size = 0;
      for (const k of keys) for (const [play, lines] of decodeLines(terms[k])) {
        const s = m.get(play) || new Set();
        lines.forEach(l => s.add(l));
        m.set(play, s);
        size += lines.length;
      }
      sets.push({ m, size });
    }
    sets.sort((a, b) => a.size - b.size);
    let cur = sets[0].m;
    for (const { m } of sets.slice(1)) {
      const next = new Map();
      for (const [play, lines] of cur) {
        const other = m.get(play);
        if (!other) continue;
        const both = new Set([...lines].filter(l => other.has(l)));
        if (both.size) next.set(play, both);
      }
      cur = next;
      if (!cur.size) break;
    }
    return { cands: [...cur].map(([play, lines]) => ({ play, lines: [...lines].sort((a, b) => a - b) })), prefix, words };
  }
  /** About how many bytes a script costs over the wire, from its spoken words (measured 2026-11-26: 2.4 to 6.8
      gzipped bytes a word, 3.3 on average, over a tenth of the library). */
  const scriptBytes = (row) => Math.round(3.3 * (Number(row.words) || 3000) + 2000);
  /** The order scripts are read in: a play whose title or author holds the words first, then the plays with the most
      lines holding them, then the index's order (A to Z). */
  function orderCandidates(cands, rows, q) {
    const words = tokens(q);
    const named = (r) => { const have = tokens(`${r.title} ${authorText(r)}`); return words.every(w => have.some(h => h.startsWith(w))); };
    return cands.filter(c => rows[c.play]).map(c => ({ ...c, row: rows[c.play], named: named(rows[c.play]) }))
      .sort((a, b) => (b.named - a.named) || ((b.lines ? b.lines.length : 0) - (a.lines ? a.lines.length : 0)) || a.play - b.play);
  }
  /** The next batch to read within `budget` bytes (at least one script). */
  function nextBatch(ordered, from, budget) {
    let i = from, used = 0;
    while (i < ordered.length && (i === from || used + scriptBytes(ordered[i].row) <= budget)) { used += scriptBytes(ordered[i].row); i += 1; }
    return { to: i, bytes: used };
  }
  /** A play's best line for a query: a line holding the exact phrase (every word in order, case and punctuation
      aside), else a line holding every word. `places` limits the check to those line places (from the line shards);
      null checks every speech. A word in `prefix` matches as a word prefix. `{ line, role, text, phrase }` or null. */
  function lineHit(script, q, places, spoken, roleName, prefix = new Set()) {
    const words = tokens(q);
    if (!words.length || !script || !Array.isArray(script.lines)) return null;
    const is = (w, h) => h === w || (prefix.has(w) && h.startsWith(w));
    let any = null;
    const at = places ? places.map(i => script.lines[i]).filter(Boolean) : script.lines;
    for (const l of at) {
      if (l.kind && l.kind !== 'speech') continue;
      const text = spoken(l);
      if (!text) continue;
      const have = tokens(text);
      if (!words.every(w => have.some(h => is(w, h)))) continue;
      const hit = { line: l.id, role: roleName(l), text, phrase: false };
      for (let i = 0; i + words.length <= have.length; i++) {
        if (words.every((w, k) => is(w, have[i + k]))) return { ...hit, phrase: true };
      }
      if (!any) any = hit;
    }
    return any;
  }
  /** What the Lines section shows: only the exact-phrase hits when there is one, else every hit. */
  const shownHits = (hits) => (hits.some(h => h.phrase) ? hits.filter(h => h.phrase) : hits);
  /** The matched line cut near `max` characters around the words, with "…" where it was cut. */
  function snippet(text, q, max = 120) {
    const t = String(text || '').replace(/_/g, '').replace(/\s+/g, ' ').trim();
    if (t.length <= max) return t;
    const w = tokens(q).sort((a, b) => b.length - a.length)[0] || '';
    const m = new RegExp(`(^|[^\\p{L}\\p{N}])${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'iu').exec(t);
    const at = m ? m.index + m[1].length : 0;
    let from = Math.max(0, at - Math.floor(max / 4));
    if (from > 0) { const sp = t.indexOf(' ', from); if (sp > 0 && sp < at) from = sp + 1; }
    let to = Math.min(t.length, from + max);
    if (to < t.length) { const sp = t.lastIndexOf(' ', to); if (sp > from + max / 2) to = sp; }
    return `${from > 0 ? '…' : ''}${t.slice(from, to)}${to < t.length ? '…' : ''}`;
  }

  return { VOICE_BINS, MINUTE_BINS, FORM_LABEL, BALANCE_LABEL, LOCC_LABEL, SORTS, RAIL_IDS, facetsOf, stateFrom, urlOf, active, filter,
           counts, sorted, rails, collection, sceneRows, sameShape, byAuthor, titleHits, characterHits, saidWords, saidPlays, decodeLines, lineCandidates, scriptBytes, orderCandidates, nextBatch, lineHit, shownHits,
           snippet, voicesOf, minutesOf };
})();
if (typeof module !== 'undefined') module.exports = FindCore;
