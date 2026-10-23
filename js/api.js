/**
 * The one data client. Views never call fetch(); everything they read comes
 * through API, from the catalog's web projection (docs/CATALOG-CONTRACT.md §4),
 * built by catalog/tools/build_web_projection.py.
 *
 * The data base is the <meta name="ed-data"> on the page (default "data/"),
 * resolved against the page. Every fetch is bounded; a failed one is reported
 * as `offline` when the browser says it is, `missing` on a 404, `error` else.
 *
 * Nothing here judges rights, ranks copies, or matches identity: the
 * projection decided all of it (the contract's one rule). The few functions
 * that must agree with the builder (fnv1a, tokens, termFile) mirror it word
 * for word and are tested against it.
 */
const API = (() => {
  'use strict';

  function dataBase() {
    const meta = typeof document !== 'undefined' && document.querySelector('meta[name="ed-data"]');
    const href = (typeof location !== 'undefined' && location.href) || 'http://localhost/';
    return new URL((meta && meta.content) || 'data/', href);
  }

  const cache = new Map();

  class DataError extends Error {
    constructor(kind, message) { super(message); this.kind = kind; }
  }

  async function getJSON(path, timeout = 15000) {
    if (cache.has(path)) return cache.get(path);
    const p = (async () => {
      let resp;
      // One retry after a refused connection: a burst of shard fetches can
      // overflow a small server's accept queue (python's http.server, measured),
      // and a phone's network drops single requests the same way.
      for (let attempt = 0; ; attempt++) {
        try {
          resp = await fetch(new URL(path, dataBase()), { signal: AbortSignal.timeout(timeout) });
          break;
        } catch (e) {
          const off = typeof navigator !== 'undefined' && navigator.onLine === false;
          if (off || attempt >= 1 || e.name === 'TimeoutError') {
            throw new DataError(off ? 'offline' : 'error', `${e.message} ${path}`);
          }
          await new Promise(r => setTimeout(r, 300 + Math.random() * 300));
        }
      }
      if (resp.status === 404) throw new DataError('missing', path);
      if (!resp.ok) throw new DataError('error', `${resp.status} ${path}`);
      return resp.json();
    })();
    cache.set(path, p);
    p.catch(() => cache.delete(path));   // a failure is never cached; Retry refetches
    return p;
  }

  /* ---- Mirrors of the builder (catalog/tools/build_web_projection.py) ---- */

  function fnv1a(str) {
    let h = 0x811c9dc5;
    for (const b of new TextEncoder().encode(str)) {
      h ^= b;
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    return h >>> 0;
  }

  function shardOf(id, mask = 0xfff) {
    return (fnv1a(id) & mask).toString(16).padStart(3, '0');
  }

  /** FTS5 unicode61's words: diacritics and case folded, split on anything not a letter or digit. */
  function tokens(text) {
    if (!text) return [];
    return text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
      .split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  }

  function termFile(word) {
    const p = Array.from(word).slice(0, 2).join('');
    return /^[a-z0-9]{2}$/.test(p) ? p : 'x' + Array.from(p).map(c => c.codePointAt(0).toString(16)).join('');
  }

  /* ---- Positional rows to objects ---- */

  function rowsOf(fields, rows) {
    return rows.map(r => {
      const o = {};
      fields.forEach((f, i) => { o[f] = r[i] === undefined ? null : r[i]; });
      return o;
    });
  }

  /* ---- The verbs (contract §5) ---- */

  const manifest = () => getJSON('manifest.json');

  let indexP = null;
  /** The gatekeeper: every served series. Loaded only when a view needs it. */
  function seriesIndex() {
    if (!indexP) {
      indexP = getJSON('index/series.json').then(d => {
        const rows = rowsOf(d.fields, d.rows);
        return { rows, byKey: new Map(rows.map(r => [r.key, r])) };
      });
      indexP.catch(() => { indexP = null; });
    }
    return indexP;
  }

  async function listen() {
    const d = await getJSON('index/listen.json');
    return {
      most: rowsOf(d.fields, d.most),
      shelves: d.shelves.map(s => ({ ...s, series: rowsOf(d.fields, s.series) })),
    };
  }

  /** This Day in Radio: episodes that aired on this month and day, oldest first. */
  async function thisDay(date = new Date()) {
    const md = `${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    try {
      const d = await getJSON(`index/days/${md}.json`);
      return rowsOf(d.fields, d.rows);
    } catch (e) {
      if (e.kind === 'missing') return [];
      throw e;
    }
  }

  async function seriesPage(key) {
    const d = await getJSON(`series/${encodeURIComponent(key)}.json`);
    const episodes = rowsOf(d.fields, d.episodes).map(e => ({ ...e, series: d.key, seriesName: d.name }));
    return { ...d, episodes };
  }

  let aliasesP = null;
  function aliases() {
    if (!aliasesP) aliasesP = getJSON('index/aliases.json').catch(() => ({}));
    return aliasesP;
  }

  /** Detail for one episode, with alias forwarding. Null when the catalog does not serve it. */
  async function episodeDetail(id) {
    const m = await manifest();
    const look = async (eid) => (await getJSON(`episodes/${shardOf(eid, m.shard.mask)}.json`))[eid];
    let rec = await look(id);
    let resolved = id;
    if (!rec) {
      const fwd = (await aliases())[id];
      if (fwd) { rec = await look(fwd); resolved = fwd; }
    }
    if (!rec) return null;
    const f = m.fields;
    const o = rowsOf(f.detail, [rec])[0];
    o.id = resolved;
    o.recordings = rowsOf(f.recording, o.recordings || []);
    o.credits = rowsOf(f.credit, o.credits || []);
    return o;
  }

  /** Phase 1 of search: series names from the index. */
  async function searchSeries(q, limit = 8) {
    const words = tokens(q).filter(w => w.length >= 2);
    if (!words.length) return { total: 0, rows: [] };
    const { rows } = await seriesIndex();
    const hits = rows.filter(r => {
      const t = tokens(r.name);
      return words.every(w => t.some(x => x.startsWith(w)));
    }).sort((a, b) => b.episodes - a.episodes);
    return { total: hits.length, rows: hits.slice(0, limit) };
  }

  /** Phase 2: episodes, word-prefix on every word, never substring. Doc numbers come back ranked. */
  async function searchEpisodeNumbers(q) {
    const words = [...new Set(tokens(q).filter(w => w.length >= 2))];
    if (!words.length) return [];
    let hits = null;
    for (const w of words) {
      let terms;
      try {
        terms = await getJSON(`search/terms/${termFile(w)}.json`);
      } catch (e) {
        if (e.kind === 'missing') return [];
        throw e;
      }
      const ns = new Set();
      for (const t in terms) {
        if (!t.startsWith(w)) continue;
        let n = 0;
        for (const d of terms[t]) { n += d; ns.add(n); }
      }
      hits = hits === null ? ns : new Set([...hits].filter(n => ns.has(n)));
      if (!hits.size) return [];
    }
    return [...hits].sort((a, b) => a - b);
  }

  async function searchDocs(numbers) {
    const m = await manifest();
    const chunk = m.search.docChunk;
    const files = await Promise.all([...new Set(numbers.map(n => Math.floor(n / chunk)))]
      .map(async k => [k, await getJSON(`search/docs/${k}.json`)]));
    const byChunk = new Map(files);
    return numbers.map(n => rowsOf(m.fields.doc, [byChunk.get(Math.floor(n / chunk))[n % chunk]])[0]);
  }

  /**
   * DECISIONS 061: play at -21 LUFS, reached by cutting. A volume factor in (0, 1]:
   * the gain is -21 - I, clamped so the true peak stays at or below -1 dBTP, and
   * never above 0 dB (a media element cannot boost). Unmeasured plays at 1.
   */
  const LOUDNESS_TARGET = -21;
  function playbackVolume(li, ltp) {
    if (li == null || !isFinite(li)) return 1;
    let g = LOUDNESS_TARGET - li;
    if (ltp != null && isFinite(ltp)) g = Math.min(g, -1 - ltp);
    g = Math.min(g, 0);
    return Math.pow(10, g / 20);
  }

  /* ---- Tonight in 19xx (contract §8): the evenings are published; the client only reads the clock ---- */

  /** The person's own calendar date, YYYY-MM-DD, in this device's time zone. */
  function localDate(d = new Date()) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  /** The evening published for `date` (the person's own), or null when none is. */
  async function tonight(date = localDate()) {
    let d;
    try {
      d = await getJSON('tonight.json');
    } catch (e) {
      if (e.kind === 'missing') return null;
      throw e;
    }
    const day = d.days && d.days[date];
    return day ? { ...day, zone: d.zone } : null;
  }

  /**
   * Where the one clock stands in an evening at `now` (ms): the index of the slot on the air,
   * and whether the evening is before, during, or after. Every instant is the file's own
   * (utc_start, utc_end); nothing is computed from a time zone here.
   */
  function onAir(slots, now) {
    if (!slots || !slots.length) return { phase: 'after', index: -1 };
    if (now < Date.parse(slots[0].utc_start)) return { phase: 'before', index: -1 };
    const end = Math.max(...slots.map(s => Date.parse(s.utc_end)));
    if (now >= end) return { phase: 'after', index: -1 };
    const index = slots.findIndex(s => Date.parse(s.utc_start) <= now && now < Date.parse(s.utc_end));
    return { phase: 'during', index };
  }

  /** The rights line, worded by the projection (contract §5.5); never "public domain". */
  async function rightsLine(rights, basis) {
    const m = await manifest();
    if (rights === 'unclaimed') return m.rightsLines.unclaimed;
    return m.rightsLines[basis] || null;
  }

  return {
    DataError, dataBase, getJSON, fnv1a, shardOf, tokens, termFile, rowsOf,
    manifest, seriesIndex, listen, thisDay, seriesPage, episodeDetail,
    searchSeries, searchEpisodeNumbers, searchDocs, rightsLine, playbackVolume, LOUDNESS_TARGET,
    localDate, tonight, onAir,
  };
})();

/**
 * Cross-platform share — Web Share API with clipboard fallback.
 * Returns 'shared', 'copied', or null when the person canceled.
 */
async function shareTarget({ title, text, url }) {
  if (navigator.share) {
    try {
      await navigator.share({ title, text, url });
      return 'shared';
    } catch (e) {
      if (e.name === 'AbortError') return null;
    }
  }
  await navigator.clipboard.writeText(url);
  return 'copied';
}
