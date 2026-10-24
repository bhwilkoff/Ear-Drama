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

  /* ---- Art (contract §3.3a, Decision 069) ---- */

  const ART_FIELDS = ['url', 'width', 'height', 'credit', 'evidence'];
  /** A published art array as an object, or null. */
  function artOf(a) {
    if (!Array.isArray(a) || !a[0]) return null;
    return rowsOf(ART_FIELDS, [a])[0];
  }
  /** Commons' standard thumbnail steps; any other width is refused upstream. */
  const ART_STEPS = [120, 330, 500];
  /** The one image helper: the served file at the smallest standard width at least `px` wide. */
  function artURL(art, px) {
    if (!art || !art.url) return null;
    const w = ART_STEPS.find(x => x >= px) || ART_STEPS[ART_STEPS.length - 1];
    return `${art.url}?width=${w}`;
  }

  /* ---- The verbs (contract §5) ---- */

  const manifest = () => getJSON('manifest.json');

  let indexP = null;
  /** The gatekeeper: every served series. Loaded only when a view needs it. */
  function seriesIndex() {
    if (!indexP) {
      indexP = getJSON('index/series.json').then(d => {
        const rows = rowsOf(d.fields, d.rows).map(r => ({ ...r, art: artOf(r.art) }));
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
    return { shelves: d.shelves.map(s => ({ ...s, series: rowsOf(d.fields, s.series).map(r => ({ ...r, art: artOf(r.art) })) })) };
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
      if (s && s.rule === 'genreFirsts' && Array.isArray(s.episodes)) {
        return { rule: 'genreFirsts', genre: s.genre, rows: await episodesByIds(s.episodes, get) };
      }
      return null;
    }));
    return out.filter(s => s && s.rows.length);
  }

  async function seriesPage(key) {
    const d = await getJSON(`series/${encodeURIComponent(key)}.json`);
    const episodes = rowsOf(d.fields, d.episodes).map(e => ({ ...e, series: d.key, seriesName: d.name }));
    return { ...d, art: artOf(d.art), episodes };
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
    o.credits = rowsOf(f.credit, o.credits || []).map(c => ({ ...c, art: artOf(c.art) }));
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
        const off = typeof navigator !== 'undefined' && navigator.onLine === false;
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
      const off = typeof navigator !== 'undefined' && navigator.onLine === false;
      return new DataError(off ? 'offline' : 'error', `${e.message} ${path}`);
    }
    async function problemOf(resp, path) {
      let code = '';
      try { code = (await resp.json()).error || ''; } catch { /* not JSON */ }
      const kind = resp.status === 401 ? 'unauthorized' : resp.status === 429 ? 'rate_limited'
        : resp.status === 503 ? 'not_configured' : 'error';
      const err = new DataError(kind, `${resp.status} ${code} ${path}`);
      err.status = resp.status;
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

    /** Every signed-in call. A 401 refreshes once and retries; a second 401 is surfaced. */
    async function call(method, path, body) {
      const b = base();
      if (!b) throw new DataError('not_configured', path);
      for (let attempt = 0; ; attempt++) {
        const token = await accessToken();
        let resp;
        try {
          resp = await fetch(b + path, {
            method,
            headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}) },
            body: body ? JSON.stringify(body) : undefined,
            signal: AbortSignal.timeout(TIMEOUT_MS),
          });
        } catch (e) { throw netError(e, path); }
        if (resp.status === 401 && attempt === 0) { access = null; continue; }
        if (!resp.ok) throw await problemOf(resp, path);
        return resp.status === 204 ? null : resp.json();
      }
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
      available, state, signedIn, update, newNonce, signIn, signOut, deleteAccount, device: DEVICE,
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
        const off = typeof navigator !== 'undefined' && navigator.onLine === false;
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
    rooms,
    DataError, dataBase, getJSON, fnv1a, shardOf, tokens, termFile, rowsOf, artOf, artURL, ART_STEPS,
    manifest, seriesIndex, listen, thisDay, onThisDay, episodesByIds, listenShelves, seriesPage, episodeDetail,
    searchSeries, searchEpisodeNumbers, searchDocs, rightsLine, playbackVolume, LOUDNESS_TARGET,
    transcript, transcriptLines, transcriptLabel,
    localDate, tonight, tonightFile, onAir, castableScripts, account,
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
