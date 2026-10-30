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

  // A packaged TV app (webOS .ipk, Tizen .wgt) runs its page from file://,
  // where a relative base names a folder that is not in the package; it reads
  // the site's projection instead (tools/test_packaged_origin.mjs).
  const CANONICAL_ROOT = new URL('https://eardrama.org/');
  const PAGES_ROOT = typeof location === 'undefined' ? new URL('http://localhost/')
    : /^https?:$/.test(location.protocol) ? new URL('.', location.href) : CANONICAL_ROOT;

  function dataBase() {
    const meta = typeof document !== 'undefined' && document.querySelector('meta[name="ed-data"]');
    return new URL((meta && meta.content) || 'data/', PAGES_ROOT);
  }

  // The ?offline=1 door (tools/app_config.py HOOK_FORCE_OFFLINE) is read once, at load, so it
  // outlives navigation: it fakes the offline state for a screenshot, never the network.
  const forcedOffline = (() => {
    if (typeof location === 'undefined' || !location.search) return false;
    const params = new URLSearchParams(location.search);
    return params.get('offline') === '1';
  })();

  /** Offline is the browser's word (WEB-DESIGN §7.3), or the door's. */
  function isOffline() {
    return forcedOffline || (typeof navigator !== 'undefined' && navigator.onLine === false);
  }

  /** The status line while offline, else null. */
  function offlineLine() { return isOffline() ? 'You are offline.' : null; }

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
          const off = isOffline();
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

  /** Browse's "Popular" (contract §3.3 `downloads`): counted rows first, most downloaded
      first; a row with no count (a play, a series never read, an older catalog) after,
      in `then`'s order, so a catalog without the field is A to Z. */
  function byDownloads(then) {
    return (a, b) => {
      const x = a.downloads > 0 ? a.downloads : null, y = b.downloads > 0 ? b.downloads : null;
      if (x !== y) {
        if (x === null) return 1;
        if (y === null) return -1;
        return y - x;
      }
      return then(a, b);
    };
  }

  /* ---- Art (contract §3.3a, Decision 069) ---- */

  const ART_FIELDS = ['url', 'width', 'height', 'credit', 'evidence', 'face'];
  /** A published art array as an object, or null. */
  function artOf(a) {
    if (!Array.isArray(a) || !a[0]) return null;
    return rowsOf(ART_FIELDS, [a])[0];
  }
  /** Commons' standard thumbnail steps; any other width is refused upstream. */
  const ART_STEPS = [120, 330, 500, 960];
  /** The one image helper: the served file at the smallest standard width at least `px` wide. */
  function artURL(art, px) {
    if (!art || !art.url) return null;
    const w = ART_STEPS.find(x => x >= px) || ART_STEPS[ART_STEPS.length - 1];
    return `${art.url}?width=${w}`;
  }

  /** A picture's shape (WEB-DESIGN §6.4a): wide past this width over height, else upright. The
      same number on every platform (iOS-DESIGN and ANDROID-DESIGN R11a). */
  const wideAspect = 1.15;
  /** Width over height from the projection, or null when the size was never read. */
  function artAspect(art) {
    return art && art.width > 0 && art.height > 0 ? art.width / art.height : null;
  }
  function artShape(art) {
    const a = artAspect(art);
    return a !== null && a > wideAspect ? 'wide' : 'upright';
  }
  /** The app's query for a path link (DEEP_LINKS.md): /series/{key} is ?series=, /episode/{id} is ?item=,
      the id percent-decoded once; null for any other path or a malformed escape. The router tries this
      first and falls back to the address's own query, so old ?series= links keep working. */
  function pathQuery(pathname) {
    const m = /^\/(series|episode)\/(.+?)\/?$/.exec(pathname || '');
    if (!m) return null;
    let id;
    try { id = decodeURIComponent(m[2]); } catch { return null; }
    return new URLSearchParams({ [m[1] === 'series' ? 'series' : 'item']: id });
  }

  /** The one link people share for a series or an episode: the path the apps share and the static page serves. */
  function shareLink(kind, id) {
    return `/${kind === 'series' ? 'series' : 'episode'}/${encodeURIComponent(id)}`;
  }

  /** The square a small slot (a tile, a cast face) shows, as {x, y, w, h} normalized to the
      image (contract §3.3a, WEB-DESIGN §6.4): around the published face box, the face about half
      the square and at most 4x zoom; without a face the largest square at 50% across and 20%
      down; null when the picture is wide with no face (not cropped) or its size is unknown (the
      caller keeps the plain fill crop). The same formula and golden cases on Apple and Android. */
  function cropRect(art) {
    const a = artAspect(art);
    if (a === null) return null;
    const f = Array.isArray(art.face) && art.face.length === 4 ? art.face : null;
    if (!f && a > wideAspect) return null;
    const full = Math.min(a, 1);
    const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
    let s = full, left = 0.5 * (a - full), top = 0.2 * (1 - full);
    if (f) {
      s = clamp(2 * Math.max(f[2] * a, f[3]), full / 4, full);
      left = clamp((f[0] + f[2] / 2) * a - s / 2, 0, a - s);
      top = clamp(f[1] + f[3] / 2 - s / 2, 0, 1 - s);
    }
    return { x: left / a, y: top, w: s / a, h: s };
  }

  /* ---- The grammar's decisions (WEB-DESIGN §6.4b, catalog-experience-design rule 11) ----
     The same rules and golden cases on Apple (Grammar.swift) and Android (Grammar.kt). */

  const MONO_STOP = new Set(['the', 'a', 'an', 'of', 'and', '&', 'in', 'on', 'to', 'for', 'el', 'la', 'le', 'de', 'der', 'die']);
  /** The title block's monogram: the initials of the first two words that start with a letter
      (articles and short joining words skipped), else the first letter or number. */
  function monogram(name) {
    const words = String(name || '').split(/[\s\-\u2013/]+/).map(w => w.replace(/^[^\p{L}\p{N}]+/u, '')).filter(Boolean);
    const lettered = words.filter(w => /^\p{L}/u.test(w) && !MONO_STOP.has(w.toLowerCase()));
    const m = lettered.slice(0, 2).map(w => w.charAt(0).toUpperCase()).join('');
    if (m) return m;
    const first = String(name || '').match(/[\p{L}\p{N}]/u);
    return first ? first[0].toUpperCase() : '';
  }
  /** The monogram's size in hundredths of the window, so it stands inside it: Big Shoulders
      capitals are at most 0.50 em wide, M 0.76, W 0.78, J 0.45, I and 1 0.27 (the bundled Bold, the widest cut we ship, measured 2026-10-30); at most 104. */
  function blockSize(m) {
    const w = [...String(m || '')].reduce((a, c) => a + (c === 'M' ? 0.76 : c === 'W' ? 0.78 : c === 'J' ? 0.45 : /[I1]/.test(c) ? 0.27 : 0.5) + 0.02, 0);
    return w ? Math.min(104, Math.floor(86 / w)) : 104;
  }
  /** A name's type step: 0 as set, 1 one level down (a word past 10 letters), 2 two (past 14). */
  function nameStep(name) {
    const L = Math.max(0, ...String(name || '').split(/[\s\-\u2013]+/).map(w => [...w].length));
    return L > 14 ? 2 : L > 10 ? 1 : 0;
  }
  /** What a window of `slot` CSS px holds: {kind: 'crop', rect} around the face, {kind: 'whole'}
      for a wide picture with no face, or {kind: 'block'} (the title block) for no picture or one
      under the size floor (uniform-imagery-design §4: the crop's pixel height at least the slot;
      a whole picture's short side at least half of it). An unknown size is a block. */
  function windowFill(art, slot) {
    if (!art || !art.url || !(art.width > 0 && art.height > 0)) return { kind: 'block' };
    const rect = cropRect(art);
    if (!rect) return Math.min(art.width, art.height) >= slot / 2 ? { kind: 'whole' } : { kind: 'block' };
    return rect.h * art.height >= slot ? { kind: 'crop', rect } : { kind: 'block' };
  }
  /** An event line's pieces: each fact with the separator kept at its end, so a line may end on a
      dot and never opens with one. Empty facts drop out. */
  function eventParts(facts) {
    const v = (facts || []).filter(x => x !== null && x !== undefined && String(x).trim() !== '').map(String);
    return v.map((x, i) => (i < v.length - 1 ? `${x} \u00b7` : x));
  }
  /** The run strip's fixed axis (WEB-DESIGN §6.4b): every show's strip is the same object. */
  const RUN_AXIS = [1930, 1962];
  /** The strip's bar, as fractions of the axis, from the first to the last broadcast year; null
      when undated (the baseline alone). */
  function runSpan(first, last) {
    const y = (d) => (d && /^\d{4}/.test(d) ? +d.slice(0, 4) : null);
    const a = y(first), b = y(last) ?? a;
    if (a === null) return null;
    const [lo, hi] = RUN_AXIS, n = hi - lo + 1;
    const c = (v) => Math.min(hi, Math.max(lo, v));
    return { from: (c(a) - lo) / n, to: (c(Math.max(a, b)) - lo + 1) / n };
  }
  /** The grade a picture takes (uniform-imagery-design §2): monochrome, then `k * v + o`. The
      projection does not publish art.grade yet, so this is the documented identity default. */
  const DEFAULT_GRADE = { k: 1, o: 0 };
  function gradeOf(art) {
    const g = art && Array.isArray(art.grade) && art.grade.length === 2 ? art.grade : null;
    return g ? { k: +g[0], o: +g[1] } : DEFAULT_GRADE;
  }

  /** The face-cropped square for the lock screen (Media Session), as an object URL, or null
      to keep the uncropped file. A canvas can only be read back from a CORS fetch; the final
      Commons host sends access-control-allow-origin: * but its Special:FilePath redirect hops
      may not, so a refused fetch (or no crop, no canvas) returns null and the caller keeps the
      plain URL. `env` is for tests. */
  async function cropBlobURL(art, size, env = {}) {
    const r = cropRect(art);
    const url = artURL(art, size / (r ? r.w : 1));
    if (!r || !url) return null;
    try {
      const doFetch = env.fetch || fetch;
      const resp = await doFetch(url, { mode: 'cors' });
      if (!resp.ok) return null;
      const bmp = await (env.createImageBitmap || createImageBitmap)(await resp.blob());
      const c = env.canvas ? env.canvas() : Object.assign(document.createElement('canvas'), { width: size, height: size });
      const g = c.getContext('2d');
      g.drawImage(bmp, r.x * bmp.width, r.y * bmp.height, r.w * bmp.width, r.h * bmp.height, 0, 0, size, size);
      const blob = await new Promise(res => c.toBlob(res, 'image/jpeg', 0.9));
      return blob ? (env.createObjectURL || URL.createObjectURL)(blob) : null;
    } catch { return null; }
  }

  /* ---- The verbs (contract §5) ---- */

  const manifest = () => getJSON('manifest.json');

  let indexP = null;
  /** The gatekeeper: every served series. Loaded only when a view needs it. */
  function seriesIndex() {
    if (!indexP) {
      indexP = getJSON('index/series.json').then(d => {
        const rows = rowsOf(d.fields, d.rows).map(r => ({ ...r, art: artOf(r.art), picture: artOf(r.picture) }));
        return { rows, byKey: new Map(rows.map(r => [r.key, r])) };
      });
      indexP.catch(() => { indexP = null; });
    }
    return indexP;
  }

  /** The pre-listenShelves Listen index: genre shelves of series. Read only for an older catalog. */
  async function listen(get = getJSON) {
    // A missing index means the data plane is not there (not yet published, or
    // a packaged TV app before the site is live), never "not in the catalog":
    // reported as an error, so Listen offers Try again.
    const d = await get('index/listen.json').catch(e => {
      throw e.kind === 'missing' ? new DataError('error', e.message) : e;
    });
    return { shelves: d.shelves.map(s => ({ ...s, series: rowsOf(d.fields, s.series).map(r => ({ ...r, art: artOf(r.art), picture: artOf(r.picture) })) })) };
  }

  const SHELF_LIMIT = 20;
  const FULL_DATE = /^\d{4}-\d{2}-\d{2}$/;
  const byCodePoint = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

  /** Contract §5.1 `onThisDay`: a full date on this month and day, any year, recommendAnd,
      oldest first, ties by id. Held to catalog/tests/golden/on_this_day.json. */
  function onThisDay(rows, month, day, limit = SHELF_LIMIT) {
    const md = `-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    return rows.filter(e => !e.noRecommend && typeof e.date === 'string' && FULL_DATE.test(e.date) && e.date.endsWith(md))
      .sort((a, b) => byCodePoint(a.date, b.date) || byCodePoint(a.id, b.id))
      .slice(0, limit);
  }

  /** This Day in Radio: the day file for the person's own month and day, through the contract's query. */
  async function thisDay(date = new Date(), get = getJSON) {
    const month = date.getMonth() + 1, day = date.getDate();
    const md = `${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    try {
      const d = await get(`index/days/${md}.json`);
      return onThisDay(rowsOf(d.fields, d.rows), month, day);
    } catch (e) {
      if (e.kind === 'missing') return [];
      throw e;
    }
  }

  /** Episode rows for published ids, in the given order; an id not served is dropped. */
  async function episodesByIds(ids, get = getJSON) {
    const [m, index] = await Promise.all([get('manifest.json'), get('index/series.json')]);
    const names = new Map(rowsOf(index.fields, index.rows).map(r => [r.key, r.name]));
    const recs = await Promise.all(ids.map(async id => {
      const shard = await get(`episodes/${shardOf(id, m.shard.mask)}.json`).catch(e => {
        if (e.kind === 'missing') return {};
        throw e;
      });
      const rec = shard[id];
      if (!rec) return null;
      const d = rowsOf(m.fields.detail, [rec])[0];
      const first = rowsOf(m.fields.recording, d.recordings || [])[0];
      return { id, date: d.date, title: d.title, series: d.series, seriesName: names.get(d.series) || null,
        length: d.length, url: first ? first.url : null, li: d.li, ltp: d.ltp };
    }));
    return recs.filter(Boolean);
  }

  /**
   * Listen's shelves (contract §5.1): the manifest's `listenShelves`, in order. onThisDay runs
   * on the person's own date; genreFirsts draws its published ids. An unknown rule is ignored and
   * an empty shelf dropped. A catalog without the key falls back to index/listen.json's genre
   * shelves of series (`rule: 'genre'`).
   */
  async function listenShelves(date = new Date(), get = getJSON) {
    const m = await get('manifest.json');
    if (!Array.isArray(m.listenShelves)) {
      const [day, legacy] = await Promise.all([thisDay(date, get), listen(get)]);
      return [{ rule: 'onThisDay', rows: day }, ...legacy.shelves.map(s => ({ rule: 'genre', genre: s.genre, series: s.series }))]
        .filter(s => (s.rows || s.series).length);
    }
    const out = await Promise.all(m.listenShelves.map(async s => {
      if (s && s.rule === 'onThisDay') return { rule: 'onThisDay', rows: await thisDay(date, get) };
      if (s && s.rule === 'mostDownloaded' && Array.isArray(s.episodes)) {
        return { rule: 'mostDownloaded', rows: await episodesByIds(s.episodes, get) };
      }
      if (s && s.rule === 'genreFirsts' && Array.isArray(s.episodes)) {
        return { rule: 'genreFirsts', genre: s.genre, rows: await episodesByIds(s.episodes, get) };
      }
      return null;
    }));
    return out.filter(s => s && s.rows.length);
  }

  /** One series page; a key the catalog moved opens the series it now is, under its new key (§3.5). */
  async function seriesPage(key) {
    const page = (k) => getJSON(`series/${encodeURIComponent(k)}.json`);
    let d;
    try {
      d = await page(key);
    } catch (e) {
      const to = e && e.kind === 'missing' ? (await forwarding().catch(() => forwardingOf())).resolveSeries(key) : key;
      if (to === key) throw e;
      d = await page(to);
    }
    const episodes = rowsOf(d.fields, d.episodes).map(e => ({ ...e, series: d.key, seriesName: d.name }));
    return { ...d, art: artOf(d.art), picture: artOf(d.picture), episodes };
  }

  /**
   * Forwarding ids (contract §3.5), the one place the web resolves an episode id or a series key:
   * `resolve(id)` / `resolveSeries(key)` is what it now is (itself when it never moved), and
   * `gone(id)` / `seriesGone(key)` is true when it left with no successor. Any other id or key this
   * catalog does not serve may come from a newer one, and is kept.
   */
  function forwardingOf(aliases, tombstones, seriesAliases, seriesTombstones) {
    const mapOf = (x) => (x && typeof x === 'object' && !Array.isArray(x) ? x : {});
    const via = (map) => (k) => (Object.prototype.hasOwnProperty.call(map, k) && typeof map[k] === 'string' ? map[k] : k);
    const dead = new Set(Array.isArray(tombstones) ? tombstones : []);
    const deadSeries = new Set(Array.isArray(seriesTombstones) ? seriesTombstones : []);
    return {
      resolve: via(mapOf(aliases)),
      gone: (id) => dead.has(id),
      resolveSeries: via(mapOf(seriesAliases)),
      seriesGone: (key) => deadSeries.has(key),
    };
  }
  let forwardingP = null;
  /** Read once a page; a catalog older than tombstones or series forwarding has none of them, and a failed read is tried again next time. */
  function forwarding(get = getJSON) {
    if (!forwardingP) {
      const missingOk = (fallback) => (e) => { if (e && e.kind === 'missing') return fallback; throw e; };
      forwardingP = Promise.all([get('index/aliases.json').catch(missingOk({})),
                                 get('index/tombstones.json').catch(missingOk([])),
                                 get('index/series-aliases.json').catch(missingOk({})),
                                 get('index/series-tombstones.json').catch(missingOk([]))])
        .then(([a, t, sa, st]) => forwardingOf(a, t, sa, st))
        .catch((e) => { forwardingP = null; throw e; });
    }
    return forwardingP;
  }

  /** Detail for one episode, its id forwarded (§3.5). Null when the catalog does not serve it. */
  async function episodeDetail(id) {
    const m = await manifest();
    // A shard with no served id is not published; the id may still forward to one that is.
    const look = async (eid) => (await getJSON(`episodes/${shardOf(eid, m.shard.mask)}.json`).catch(e => {
      if (e && e.kind === 'missing') return {};
      throw e;
    }))[eid];
    let rec = await look(id);
    let resolved = id;
    if (!rec) {
      const fwd = (await forwarding().catch(() => forwardingOf())).resolve(id);
      if (fwd !== id) { rec = await look(fwd); resolved = fwd; }
    }
    if (!rec) return null;
    const f = m.fields;
    const o = rowsOf(f.detail, [rec])[0];
    o.id = resolved;
    o.recordings = rowsOf(f.recording, o.recordings || []);
    o.credits = rowsOf(f.credit, o.credits || []).map(c => ({ ...c, art: artOf(c.art) }));
    return o;
  }

  /**
   * The story arc an episode is a part of (contract §3.3, Decision 067): { id, part, parts, next, nextStory },
   * the next part's card (null on the last part) and, on the last part only, the series' next story's
   * first part, offered and never started. Null outside an arc, or for a catalog that predates arcs.
   */
  async function arcOf(id, get = getJSON) {
    const m = await get('manifest.json');
    if (!m.fields || !m.fields.arc || !m.fields.detail.includes('arc')) return null;
    const shard = await get(`episodes/${shardOf(id, m.shard.mask)}.json`).catch(e => {
      if (e.kind === 'missing') return {};
      throw e;
    });
    const rec = shard[id];
    const raw = rec && rowsOf(m.fields.detail, [rec])[0].arc;
    if (!raw) return null;
    const a = rowsOf(m.fields.arc, [raw])[0];
    const want = [a.next, a.nextStory].filter(Boolean);
    const cards = new Map((want.length ? await episodesByIds(want, get) : []).map(c => [c.id, c]));
    return { id: a.id, part: a.part, parts: a.parts, next: cards.get(a.next) || null,
             nextStory: cards.get(a.nextStory) || null };
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
  async function searchEpisodeNumbers(q, get = getJSON) {
    const words = [...new Set(tokens(q).filter(w => w.length >= 2))];
    if (!words.length) return [];
    let hits = null;
    for (const w of words) {
      let terms;
      try {
        terms = await get(`search/terms/${termFile(w)}.json`);
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

  /* ---- People (contract §4, §5 withPerson and searchPeople) ---- */

  /** A person's page: facts from the people row and every served credit, oldest first. Null when
      the catalog serves no credit of theirs, or predates people pages. */
  async function personPage(id) {
    const m = await manifest();
    if (!m.fields.person) return null;
    let rec;
    try {
      rec = (await getJSON(`people/${shardOf(id, m.shard.mask)}.json`))[id];
    } catch (e) {
      if (e.kind === 'missing') return null;
      throw e;
    }
    if (!rec) return null;
    const o = rowsOf(m.fields.person, [rec])[0];
    return { ...o, id, art: artOf(o.art), credits: rowsOf(m.fields.personCredit, o.credits) };
  }

  /** The years from the people row, as every platform writes them; null when neither is known. */
  function lifeYears(birth, death) {
    const b = birth && String(birth).slice(0, 4);
    const d = death && String(death).slice(0, 4);
    if (b && d) return `${b}–${d}`;
    if (b) return `Born ${b}`;
    return d ? `Died ${d}` : null;
  }

  /**
   * A person's credits as the page draws them: one row per episode with every role it credits them
   * in, grouped by series. Oldest first (R1) or newest first, undated last either way; a series sits
   * where its first episode in that order does.
   */
  function personGroups(credits, newestFirst = false) {
    const byId = new Map();
    for (const c of credits) {
      let ep = byId.get(c.id);
      if (!ep) byId.set(c.id, ep = { id: c.id, date: c.date, title: c.title, num: c.num, series: c.series, roles: [] });
      ep.roles.push({ role: c.role, character: c.character });
    }
    const eps = [...byId.values()];
    if (newestFirst) {
      const dated = eps.filter(e => e.date).reverse();
      eps.splice(0, eps.length, ...dated, ...eps.filter(e => !e.date));
    }
    const groups = new Map();
    for (const e of eps) {
      if (!groups.has(e.series)) groups.set(e.series, []);
      groups.get(e.series).push(e);
    }
    return [...groups].map(([series, episodes]) => ({ series, episodes }));
  }

  /** People whose name has every query word as a word prefix, most served episodes first. */
  async function searchPeople(q, limit = 8) {
    const words = [...new Set(tokens(q).filter(w => w.length >= 2))];
    if (!words.length) return { total: 0, rows: [] };
    const m = await manifest();
    if (!m.fields.people) return { total: 0, rows: [] };
    let d;
    try {
      d = await getJSON(`search/people/${termFile(words[0])}.json`);
    } catch (e) {
      if (e.kind === 'missing') return { total: 0, rows: [] };
      throw e;
    }
    const hits = rowsOf(d.fields, d.rows).filter(r => {
      const t = tokens(r.name);
      return words.every(w => t.some(x => x.startsWith(w)));
    }).map(r => ({ ...r, art: artOf(r.art) }));
    return { total: hits.length, rows: hits.slice(0, limit) };
  }

  /* ---- Transcripts (DECISIONS 058, contract §3.1) ---- */

  /** The one label on every platform: what it is, and that no person wrote it. */
  const transcriptLabel = 'Automatic transcript';
  const transcripts = new Map();

  /**
   * archive.org's automatic transcript, fetched from its own URL (the Detail
   * row's `transcript`) when opened, never bundled. archive.org answers it with
   * `access-control-allow-origin: *`, so the browser reads it directly.
   */
  function transcript(url, timeout = 20000) {
    if (transcripts.has(url)) return transcripts.get(url);
    const p = (async () => {
      let resp;
      try {
        resp = await fetch(url, { signal: AbortSignal.timeout(timeout) });
      } catch (e) {
        const off = isOffline();
        throw new DataError(off ? 'offline' : 'error', `${e.message} ${url}`);
      }
      if (resp.status === 404) throw new DataError('missing', url);
      if (!resp.ok) throw new DataError('error', `${resp.status} ${url}`);
      return resp.text();
    })();
    transcripts.set(url, p);
    p.catch(() => transcripts.delete(url));   // a failure is never cached; Try again refetches
    return p;
  }

  /** The text as archive.org serves it (a sentence a line), blank lines and stray spaces dropped. */
  function transcriptLines(text) {
    return (text || '').split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  }

  /* ---- What is said, and when it aired (contract §4: search/said, search/dates) ---- */

  /** The transcript words a query searches: its words of saidMinWord letters or more. */
  function saidWords(q, minWord = 3) {
    return [...new Set(tokens(q).filter(w => w.length >= minWord))];
  }

  /** Doc numbers whose shown transcript has every query word as a word prefix, ascending. */
  async function searchSaidNumbers(q, get = getJSON) {
    const m = await get('manifest.json');
    const words = saidWords(q, (m.search && m.search.saidMinWord) || 3);
    if (!words.length) return [];
    let hits = null;
    for (const w of words) {
      let terms;
      try {
        terms = await get(`search/said/${termFile(w)}.json`);
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

  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
                  'October', 'November', 'December'];

  function monthOf(t) {
    const s = t.replace(/\.$/, '');
    if (s === 'sept') return 9;
    const i = MONTHS.findIndex(m => m.toLowerCase() === s || (s.length === 3 && m.toLowerCase().startsWith(s)));
    return i < 0 ? 0 : i + 1;
  }

  /**
   * The air date a query names, the same rule on every platform: "1954", "August 1954", "Aug 2, 1954",
   * "2 August 1954", "1954-08", "1954-08-02", or "8/2/1954". { prefix, rest } where prefix is YYYY,
   * YYYY-MM, or YYYY-MM-DD and rest is the query's other words; null when no date is named.
   */
  function dateQuery(q) {
    const t = String(q || '').toLowerCase().split(/[\s,]+/).filter(Boolean);
    const isYear = (s) => /^\d{4}$/.test(s || '') && +s >= 1900 && +s <= 2099;
    const isDay = (s) => /^\d{1,2}$/.test(s || '') && +s >= 1 && +s <= 31;
    const pad = (n) => String(n).padStart(2, '0');
    for (let i = 0; i < t.length; i++) {
      let y = null, m = 0, d = 0, used = 1;
      let x;
      if ((x = /^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?$/.exec(t[i]))) {
        y = x[1]; m = +x[2]; d = x[3] ? +x[3] : 0;
        if (x[3] && !isDay(x[3])) continue;
      } else if ((x = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(t[i])) && isDay(x[2])) {
        y = x[3]; m = +x[1]; d = +x[2];
      } else if (monthOf(t[i]) && isDay(t[i + 1]) && isYear(t[i + 2])) {
        m = monthOf(t[i]); d = +t[i + 1]; y = t[i + 2]; used = 3;
      } else if (monthOf(t[i]) && isYear(t[i + 1])) {
        m = monthOf(t[i]); y = t[i + 1]; used = 2;
      } else if (isDay(t[i]) && monthOf(t[i + 1] || '') && isYear(t[i + 2])) {
        d = +t[i]; m = monthOf(t[i + 1]); y = t[i + 2]; used = 3;
      } else if (isYear(t[i])) {
        y = t[i];
      }
      if (!isYear(y) || m < 0 || m > 12 || (d && !m)) continue;
      const prefix = [y, m ? pad(m) : null, d ? pad(d) : null].filter(Boolean).join('-');
      return { prefix, rest: [...t.slice(0, i), ...t.slice(i + used)].join(' ') };
    }
    return null;
  }

  /** A date prefix as a person reads it: "1954", "August 1954", "August 2, 1954". */
  function dateLabel(prefix) {
    const [y, m, d] = prefix.split('-');
    if (!m) return y;
    return d ? `${MONTHS[+m - 1]} ${+d}, ${y}` : `${MONTHS[+m - 1]} ${y}`;
  }

  /**
   * The episodes that aired on the date the query names, oldest first, narrowed by its other words
   * (titles, series, people, as Episodes). { prefix, rows } or null when the query names no date.
   */
  async function searchAired(q, get = getJSON) {
    const dq = dateQuery(q);
    if (!dq) return null;
    let file;
    try {
      file = await get(`search/dates/${dq.prefix.slice(0, 4)}.json`);
    } catch (e) {
      if (e.kind === 'missing') return { prefix: dq.prefix, rows: [] };
      throw e;
    }
    let rows = rowsOf(file.fields, file.rows).filter(r => r.date.startsWith(dq.prefix));
    if (tokens(dq.rest).some(w => w.length >= 2)) {
      const ns = new Set(await searchEpisodeNumbers(dq.rest, get));
      rows = rows.filter(r => ns.has(r.doc));
    }
    return { prefix: dq.prefix, rows };
  }

  /**
   * The line of an automatic transcript where a query word is first said, verbatim, cut to about
   * `max` characters around it with an ellipsis at a cut; null when no line says one. The same rule
   * on every platform (Transcript.snippet).
   */
  function transcriptSnippet(text, words, max = 120) {
    if (!words.length) return null;
    const line = transcriptLines(text).find(l => tokens(l).some(t => words.some(w => t.startsWith(w))));
    if (!line) return null;
    if (line.length <= max) return line;
    const lower = line.toLowerCase();
    let at = line.length;
    for (const w of words) {
      for (let i = lower.indexOf(w); i >= 0; i = lower.indexOf(w, i + 1)) {
        if (i === 0 || !/[\p{L}\p{N}]/u.test(lower[i - 1])) { at = Math.min(at, i); break; }
      }
    }
    if (at === line.length) at = 0;
    let start = Math.max(0, at - 40);
    if (start > 0) {
      const sp = line.indexOf(' ', start);
      start = sp >= 0 && sp < at ? sp + 1 : at;
    }
    let end = Math.min(line.length, start + max);
    if (end < line.length) {
      const sp = line.lastIndexOf(' ', end);
      if (sp > at) end = sp;
    }
    return `${start > 0 ? '…' : ''}${line.slice(start, end).trim()}${end < line.length ? '…' : ''}`;
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

  /** The whole published file, for Surprise's random evening (WEB-DESIGN §4.13); null when none is. */
  async function tonightFile() {
    try {
      return await getJSON('tonight.json');
    } catch (e) {
      if (e.kind === 'missing') return null;
      throw e;
    }
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

  /* ---- Genre stations (contract §8, R10): published back to back on the one clock ---- */

  /** The published stations, [{ genre, name, slots }], or [] when none is published. */
  async function stations() {
    try {
      const d = await getJSON('stations.json');
      return Array.isArray(d.stations) ? d.stations : [];
    } catch (e) {
      if (e.kind === 'missing') return [];
      throw e;
    }
  }

  /**
   * What a station has on at `now` (ms): { index, slot, offset } with `offset` in seconds since the
   * slot started, or null before its first slot or after its last. The slots are back to back and in
   * order, so the search halves; a boundary belongs to the slot that starts.
   */
  function onNow(slots, now) {
    let lo = 0;
    let hi = (slots || []).length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const s = slots[mid];
      if (now < Date.parse(s.utc_start)) hi = mid - 1;
      else if (now >= Date.parse(s.utc_end)) lo = mid + 1;
      else return { index: mid, slot: s, offset: (now - Date.parse(s.utc_start)) / 1000 };
    }
    return null;
  }

  /** The slot on now and every slot starting within `spanMs` of now: what one tune-in may play. */
  function ahead(slots, now, spanMs = 12 * 3600 * 1000) {
    const on = onNow(slots, now);
    if (!on) return [];
    const out = [];
    for (let i = on.index; i < slots.length && Date.parse(slots[i].utc_start) < now + spanMs; i++) out.push(slots[i]);
    return out;
  }

  /**
   * The castable plays (PLAYS-DESIGN §3): catalog/plays/castable-scripts.json,
   * served at data/plays/. Only scripts the rights test calls castable and
   * whose parse is clean are in it; the client adds no filter of its own.
   */
  async function castableScripts() {
    const d = await getJSON('plays/castable-scripts.json', 30000);
    return Array.isArray(d.scripts) ? d.scripts : [];
  }

  /** The rights line, worded by the projection (contract §5.5); never "public domain". */
  async function rightsLine(rights, basis) {
    const m = await manifest();
    if (rights === 'unclaimed') return m.rightsLines.unclaimed;
    return m.rightsLines[basis] || null;
  }

  /* ---- The Worker: optional sign-in and sync (Decisions 057, 063; docs/WORKER.md) ---- */

  const realValue = (v) => typeof v === 'string' && v.length > 0 && !v.startsWith('REPLACE_WITH');
  /** The Worker's base URL from a config, or null while it is a placeholder (not available, never an error). */
  function workerBase(cfg) {
    const w = cfg && cfg.worker;
    if (!realValue(w)) return null;
    try {
      const u = new URL(w);
      const local = ['localhost', '127.0.0.1'].includes(u.hostname);
      return u.protocol === 'https:' || (local && u.protocol === 'http:') ? w.replace(/\/+$/, '') : null;
    } catch { return null; }
  }

  /**
   * Every Worker call goes through `account`. The access token lives only in this
   * closure's memory. The refresh token is kept in IndexedDB encrypted with an
   * AES-GCM key made non-extractable by WebCrypto: script on this page can use the
   * key but never read it, so a copy of the browser's storage taken off the machine
   * (a backup, a synced profile, a disk image) cannot be decrypted. It is not
   * protection from script running on the page itself; nothing a page holds is.
   * An HttpOnly cookie would be, but the Worker answers tokens in JSON to every
   * platform alike (docs/WORKER.md). Without IndexedDB the token stays in memory
   * and the sign-in lasts as long as the page. Never in a URL or localStorage.
   */
  const account = (() => {
    const STATE_KEY = 'ed.account';
    const REFRESH_EARLY_MS = 5 * 60 * 1000;
    const TIMEOUT_MS = 20000;
    const DEVICE = 'web';
    const listeners = new Set();
    let config = typeof CONFIG !== 'undefined' ? CONFIG : {};
    let now = () => Date.now();
    let vault = null;
    let access = null;          // { token, exp }
    let refreshing = null;

    const real = realValue;
    const base = () => workerBase(config);
    /** Which sign-ins this build can offer; a placeholder means not available, never an error. */
    function available() {
      const b = !!base();
      return {
        apple: b && real(config.apple && config.apple.servicesId) && real(config.apple.redirectURI),
        google: b && real(config.google && config.google.clientId),
      };
    }

    function readState() {
      try { return JSON.parse(localStorage.getItem(STATE_KEY)) || null; } catch { return null; }
    }
    function writeState(s) {
      try {
        if (s) localStorage.setItem(STATE_KEY, JSON.stringify(s)); else localStorage.removeItem(STATE_KEY);
      } catch { /* storage unavailable: the sign-in lasts as long as the page */ }
      memState = s;
      listeners.forEach(fn => { try { fn(s); } catch (e) { console.error(e); } });
    }
    let memState;
    function state() {
      if (memState === undefined) memState = readState();
      return memState;
    }
    function update(patch) {
      const s = state();
      if (s) writeState({ ...s, ...patch });
    }

    function memoryVault() {
      let t = null;
      return { async get() { return t; }, async set(v) { t = v; }, async clear() { t = null; } };
    }
    function idbVault() {
      let dbP = null;
      let keyP = null;
      const open = () => dbP || (dbP = new Promise((res, rej) => {
        const r = indexedDB.open('ed-auth', 1);
        r.onupgradeneeded = () => r.result.createObjectStore('kv');
        r.onsuccess = () => res(r.result);
        r.onerror = () => rej(r.error);
      }));
      const tx = async (mode, fn) => {
        const db = await open();
        return new Promise((res, rej) => {
          const t = db.transaction('kv', mode);
          const req = fn(t.objectStore('kv'));
          t.oncomplete = () => res(req && req.result);
          t.onerror = t.onabort = () => rej(t.error);
        });
      };
      const key = () => keyP || (keyP = (async () => {
        const k = await tx('readonly', s => s.get('key'));
        if (k) return k;
        const made = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
        await tx('readwrite', s => s.put(made, 'key'));
        return made;
      })());
      return {
        async get() {
          const rec = await tx('readonly', s => s.get('refresh'));
          if (!rec) return null;
          try {
            const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: rec.iv }, await key(), rec.ct);
            return new TextDecoder().decode(pt);
          } catch { return null; }
        },
        async set(token) {
          const iv = crypto.getRandomValues(new Uint8Array(12));
          const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(), new TextEncoder().encode(token));
          await tx('readwrite', s => s.put({ iv, ct }, 'refresh'));
        },
        async clear() { await tx('readwrite', s => s.delete('refresh')); },
      };
    }
    function theVault() {
      if (!vault) {
        vault = typeof indexedDB !== 'undefined' && typeof crypto !== 'undefined' && crypto.subtle ? idbVault() : memoryVault();
        const v = vault;
        const fallback = memoryVault();
        let broken = false;
        // A browser that refuses IndexedDB (some private windows) keeps the token in memory.
        vault = {
          get: () => broken ? fallback.get() : v.get().catch(() => { broken = true; return fallback.get(); }),
          set: (t) => broken ? fallback.set(t) : v.set(t).catch(() => { broken = true; return fallback.set(t); }),
          clear: () => Promise.all([fallback.clear(), v.clear().catch(() => {})]),
        };
      }
      return vault;
    }

    /** One refresh at a time in this page, and across this browser's tabs where Web Locks exist. */
    function withLock(fn) {
      if (typeof navigator !== 'undefined' && navigator.locks && navigator.locks.request) {
        return navigator.locks.request('ed-auth-refresh', fn);
      }
      return fn();
    }

    function netError(e, path) {
      const off = isOffline();
      return new DataError(off ? 'offline' : 'error', `${e.message} ${path}`);
    }
    async function problemOf(resp, path) {
      let code = '';
      let detail;
      try { const j = await resp.json(); code = j.error || ''; detail = j.detail; } catch { /* not JSON */ }
      const kind = resp.status === 401 ? 'unauthorized' : resp.status === 429 ? 'rate_limited'
        : resp.status === 503 ? 'not_configured' : 'error';
      const err = new DataError(kind, `${resp.status} ${code} ${path}`);
      err.status = resp.status;
      err.code = code;
      err.detail = detail;
      return err;
    }
    async function post(path, body, headers = {}) {
      const b = base();
      if (!b) throw new DataError('not_configured', path);
      try {
        return await fetch(b + path, {
          method: 'POST', headers: { 'content-type': 'application/json', ...headers },
          body: JSON.stringify(body), signal: AbortSignal.timeout(TIMEOUT_MS),
        });
      } catch (e) { throw netError(e, path); }
    }

    async function keepSession(s, extra) {
      access = { token: s.access_token, exp: s.access_expires_at };
      await theVault().set(s.refresh_token);
      return { refresh_expires_at: s.refresh_expires_at, ...extra };
    }

    /** The session ended at the Worker (signed out elsewhere, deleted, replayed): forget it here. */
    async function ended(notice) {
      access = null;
      await theVault().clear();
      writeState(notice ? { ended: notice } : null);
    }

    async function doRefresh() {
      const rt = await theVault().get();
      if (!rt) { await ended('session_ended'); throw new DataError('unauthorized', 'no refresh token'); }
      const resp = await post('/v1/auth/refresh', { refresh_token: rt });
      if (resp.status === 401) {
        await ended('session_ended');
        throw await problemOf(resp, '/v1/auth/refresh');
      }
      if (!resp.ok) throw await problemOf(resp, '/v1/auth/refresh');
      update(await keepSession(await resp.json()));
    }
    function refresh() {
      if (!refreshing) refreshing = withLock(doRefresh).finally(() => { refreshing = null; });
      return refreshing;
    }

    /** The bearer for the next call, refreshed first when under five minutes remain. */
    async function accessToken() {
      if (!signedIn()) throw new DataError('unauthorized', 'signed out');
      if (!access || access.exp - now() < REFRESH_EARLY_MS) await refresh();
      return access.token;
    }

    /**
     * Every signed-in call. A 401 refreshes once and retries; a second 401 is surfaced.
     * `opts.raw` sends bytes as the body (a take's audio) with `opts.headers`;
     * `opts.bytes` answers the body as an ArrayBuffer.
     */
    async function call(method, path, body, opts = {}) {
      const b = base();
      if (!b) throw new DataError('not_configured', path);
      for (let attempt = 0; ; attempt++) {
        const token = await accessToken();
        let resp;
        try {
          resp = await fetch(b + path, {
            method,
            headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}),
                       ...(opts.headers || {}) },
            body: opts.raw !== undefined ? opts.raw : body ? JSON.stringify(body) : undefined,
            signal: AbortSignal.timeout(opts.timeout || TIMEOUT_MS),
          });
        } catch (e) { throw netError(e, path); }
        if (resp.status === 401 && attempt === 0) { access = null; continue; }
        if (!resp.ok) throw await problemOf(resp, path);
        if (opts.bytes) return resp.arrayBuffer();
        return resp.status === 204 ? null : resp.json();
      }
    }

    /**
     * A read that needs no account: no bearer, so nothing is refreshed and a 401 is
     * never retried. `opts.headers` carries an invite's `x-invite`; a 410 is kind
     * 'gone' (a revoked or expired invite); `opts.bytes` answers an ArrayBuffer.
     */
    async function open(path, opts = {}) {
      const b = base();
      if (!b) throw new DataError('not_configured', path);
      let resp;
      try {
        resp = await fetch(b + path, { method: 'GET', headers: opts.headers || {}, signal: AbortSignal.timeout(opts.timeout || TIMEOUT_MS) });
      } catch (e) { throw netError(e, path); }
      if (!resp.ok) {
        const err = await problemOf(resp, path);
        if (resp.status === 410) err.kind = 'gone';
        throw err;
      }
      return opts.bytes ? resp.arrayBuffer() : resp.json();
    }

    function signedIn() { const s = state(); return !!(s && s.user_id); }

    /** A fresh raw nonce for one sign-in; the provider puts it (or its SHA-256) in the identity token. */
    function newNonce() {
      const b = crypto.getRandomValues(new Uint8Array(32));
      return btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    }

    /** Trade a provider's identity token for the Worker's session. The signed-out history merges once next. */
    async function signIn(provider, idToken, nonce) {
      if (!['apple', 'google'].includes(provider)) throw new DataError('error', provider);
      const path = `/v1/auth/${provider}`;
      const resp = await post(path, { id_token: idToken, nonce, device: DEVICE });
      if (!resp.ok) throw await problemOf(resp, path);
      const s = await resp.json();
      access = null;
      const kept = await keepSession(s, {
        user_id: s.user_id, provider: s.provider || provider, signed_in_at: now(),
        merge_pending: true, since: 0, last_sync_at: null, last_error: null,
      });
      writeState(kept);
      return state();
    }

    async function signOut() {
      try { if (signedIn()) await call('POST', '/v1/auth/signout'); } catch { /* signed out here regardless */ }
      await ended(null);
    }

    /** Deletes the account at the Worker; only then are the tokens and account state forgotten here. */
    async function deleteAccount(opts = {}) {
      const body = {};
      if (opts.appleAuthorizationCode) {
        body.apple_authorization_code = opts.appleAuthorizationCode;
        if (opts.appleClientId) body.apple_client_id = opts.appleClientId;
      }
      const r = await call('DELETE', '/v1/account', body);
      await ended(null);
      return r;
    }

    return {
      available, state, signedIn, update, newNonce, signIn, signOut, deleteAccount, device: DEVICE, call, open,
      /** The Worker's URL is real (not a placeholder): signed-in features may be offered. */
      reachable: () => !!base(),
      onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
      info: () => call('GET', '/v1/account'),
      syncRead: (since) => call('GET', `/v1/sync?since=${encodeURIComponent(Math.max(0, Math.floor(since || 0)))}`),
      syncPut: (upload) => call('PUT', '/v1/sync', upload),
      syncMerge: (upload) => call('POST', '/v1/sync/merge', upload),
      /** Tests only: a config, a clock, and a vault in place of IndexedDB. */
      _test: {
        configure(c) { config = c; },
        clock(fn) { now = fn; },
        vault(v) { vault = v; },
        reset() { access = null; refreshing = null; memState = undefined; },
        access: () => access,
      },
    };
  })();

  /* ---- Shared plays (M8, Decisions 057, 059, 066; docs/WORKER.md "Shared plays") ---- */

  /**
   * Every route is signed in and goes through `account.call`, so the token is
   * refreshed first. A refusal carries the Worker's own `code` and `detail`.
   */
  const plays = (() => {
    const P = '/v1/plays';
    const at = (pid) => `${P}/productions/${encodeURIComponent(pid)}`;
    const c = (method, path, body, opts) => account.call(method, path, body, opts);
    return {
      available: () => account.reachable(),
      consent: () => c('GET', `${P}/consent`),
      create: (body) => c('POST', `${P}/productions`, body),
      list: () => c('GET', `${P}/productions`),
      get: (pid) => c('GET', at(pid)),
      invite: (pid) => c('POST', `${at(pid)}/invites`, {}),
      viewInvite: (token) => c('POST', `${P}/invites/view`, { token }),
      joinByInvite: (token, part, displayName) =>
        c('POST', `${P}/invites/claim`, { token, part, ...(displayName ? { display_name: displayName } : {}) }),
      claim: (pid, part) => c('POST', `${at(pid)}/claim`, { part }),
      partAction: (pid, part, action) => c('POST', `${at(pid)}/parts/${encodeURIComponent(part)}/${action}`, {}),
      agree: (pid, version) => c('POST', `${at(pid)}/consent`, { version }),
      upload: (pid, takeId, bytes, meta) => c('PUT', `${at(pid)}/takes/${encodeURIComponent(takeId)}`, null,
        { raw: bytes, headers: { 'content-type': 'audio/wav', 'x-take': JSON.stringify(meta) }, timeout: 180000 }),
      audio: (pid, takeId) => c('GET', `${at(pid)}/takes/${encodeURIComponent(takeId)}/audio`, null,
        { bytes: true, timeout: 120000 }),
      choose: (pid, takeId) => c('POST', `${at(pid)}/chosen`, { take_id: takeId }),
      publish: (pid) => c('POST', `${at(pid)}/publish`, {}),
      removeLine: (pid, lineId, reason) => c('POST', `${at(pid)}/archive/lines/${encodeURIComponent(lineId)}/remove`, { reason }),
      report: (body) => c('POST', `${P}/reports`, body),
      block: (userId) => c('POST', `${P}/blocks`, { user_id: userId }),
      /**
       * No account (owner 2026-10-29). An invite link shows everything signed out: the play, its parts
       * and states, who is in by chosen name, and the chosen takes. Only a read; claiming and recording
       * still need `joinByInvite`. A revoked or expired invite is a DataError of kind 'gone'.
       */
      openInvite: (token) => account.open(`${P}/open/invite`, { headers: { 'x-invite': token } }),
      openInviteAudio: (token, takeId) => account.open(`${P}/open/invite/takes/${encodeURIComponent(takeId)}/audio`,
        { headers: { 'x-invite': token }, bytes: true, timeout: 120000 }),
      /** Finished ear dramas, newest published first: { productions, next_cursor }. */
      finished: ({ limit, cursor } = {}) => {
        const q = new URLSearchParams();
        if (limit) q.set('limit', String(limit));
        if (cursor) q.set('cursor', cursor);
        const qs = q.toString();
        return account.open(`${P}/finished${qs ? `?${qs}` : ''}`);
      },
      finishedOne: (pid) => account.open(`${P}/finished/${encodeURIComponent(pid)}`),
      classes: () => c('GET', `${P}/classes`),
      createClass: (name, under13) => c('POST', `${P}/classes`, { name, under13: !!under13 }),
      joinClass: (code, displayName) =>
        c('POST', `${P}/classes/join`, { code, ...(displayName ? { display_name: displayName } : {}) }),
    };
  })();

  /* ---- Listen Together rooms (M6, Decision 065; docs/WORKER.md "Listen Together rooms") ---- */

  /**
   * No account: a room takes no bearer token. The member key comes back once,
   * from create or join, and goes out only as `x-room-key`. Every answer
   * carries `server_time`, so every call is a clock sample (t0, server_time, t1)
   * kept here for TogetherCore.clockOffset. A refusal's kind is the Worker's
   * own code: no_such_room, room_ended, room_full, host_only, not_a_member,
   * bad_code, rate_limited.
   */
  const rooms = (() => {
    const KEY_HEADER = 'x-room-key';
    const TIMEOUT_MS = 15000;
    const KEEP_SAMPLES = 8;
    let config = typeof CONFIG !== 'undefined' ? CONFIG : {};
    let now = () => Date.now();
    let samples = [];

    async function call(method, path, { key, body } = {}) {
      const b = workerBase(config);
      if (!b) throw new DataError('not_configured', path);
      const headers = {};
      if (key) headers[KEY_HEADER] = key;
      if (body !== undefined) headers['content-type'] = 'application/json';
      const t0 = now();
      let resp;
      try {
        resp = await fetch(b + path, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined,
                                       signal: AbortSignal.timeout(TIMEOUT_MS) });
      } catch (e) {
        const off = isOffline();
        throw new DataError(off ? 'offline' : 'error', `${e.message} ${path}`);
      }
      const t1 = now();
      let data = null;
      try { data = await resp.json(); } catch { /* not JSON */ }
      if (!resp.ok) {
        const err = new DataError((data && data.error) || 'error', `${resp.status} ${path}`);
        err.status = resp.status;
        throw err;
      }
      if (data && typeof data.server_time === 'number') {
        samples.push({ t0, server_time: data.server_time, t1 });
        if (samples.length > KEEP_SAMPLES) samples.shift();
      }
      return data;
    }
    const at = (code) => `/v1/rooms/${encodeURIComponent(code)}`;

    return {
      available: () => !!workerBase(config),
      create: (state) => call('POST', '/v1/rooms', { body: { state } }),
      join: (code) => call('POST', `${at(code)}/join`),
      read: (code, key) => call('GET', at(code), { key }),
      setState: (code, key, state) => call('PUT', `${at(code)}/state`, { key, body: state }),
      leave: (code, key) => call('POST', `${at(code)}/leave`, { key }),
      end: (code, key) => call('DELETE', at(code), { key }),
      /** The clock samples of recent answers, newest last. */
      samples: () => samples.slice(),
      resetClock() { samples = []; },
      _test: { configure(c) { config = c; }, clock(fn) { now = fn; } },
    };
  })();

  return {
    rooms, plays, isOffline, offlineLine,
    DataError, dataBase, getJSON, fnv1a, shardOf, tokens, termFile, rowsOf, byDownloads, artOf, artURL, ART_STEPS, wideAspect, artAspect, artShape, cropRect, cropBlobURL,
    monogram, blockSize, nameStep, windowFill, eventParts, RUN_AXIS, runSpan, gradeOf, pathQuery, shareLink,
    manifest, seriesIndex, listen, thisDay, onThisDay, episodesByIds, listenShelves, seriesPage, episodeDetail, arcOf,
    forwarding, forwardingOf,
    searchSeries, searchEpisodeNumbers, searchDocs, rightsLine,
    personPage, lifeYears, personGroups, searchPeople,
    transcript, transcriptLines, transcriptLabel, transcriptSnippet, saidWords, searchSaidNumbers,
    dateQuery, dateLabel, searchAired,
    localDate, tonight, tonightFile, onAir, stations, onNow, ahead, castableScripts, account,
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
