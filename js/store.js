/**
 * The person's own listening, kept on this device: resume positions, history,
 * the queue, and followed series. Signed in (M5, js/sync.js), every row also
 * carries a stamp (when it last changed, whether it is a removal, whether the
 * Worker has it yet), and rows from the Worker apply last-write-wins by that
 * stamp (Decision 063). The stamps are kept signed out too, so the one-time
 * merge after sign-in knows when each row changed.
 *
 * localStorage, every access guarded: a private window or blocked storage
 * leaves the app working, just forgetful. An episode is stored as the small
 * card the lists draw: { id, title, series, seriesName, date, url, length }.
 */
const Store = (() => {
  'use strict';

  const KEYS = { positions: 'ed.positions', history: 'ed.history', queue: 'ed.queue', follows: 'ed.follows',
                 rate: 'ed.rate', stamps: 'ed.stamps' };
  const MAX_HISTORY = 200;
  const MAX_POSITIONS = 500;
  const MAX_STAMPS = 1500;
  const MAX_UPLOAD = 500;
  const listeners = new Set();

  function read(key, fallback) {
    try {
      const v = localStorage.getItem(key);
      return v === null ? fallback : JSON.parse(v);
    } catch { return fallback; }
  }
  function write(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* storage unavailable */ }
    listeners.forEach(fn => fn(key));
  }

  function card(ep) {
    return { id: ep.id, title: ep.title || null, series: ep.series || null, seriesName: ep.seriesName || null,
             date: ep.date || null, url: ep.url || null, length: ep.length || null,
             li: ep.li ?? null, ltp: ep.ltp ?? null };
  }

  /* ---- Stamps: { h: {id: {at, del, dirty}}, f: {key: {at, on, dirty}}, q: {at, dirty} } ---- */
  function stamps() {
    const s = read(KEYS.stamps, null);
    return s && typeof s === 'object' ? { h: s.h || {}, f: s.f || {}, q: s.q || null } : { h: {}, f: {}, q: null };
  }
  function prune(map) {
    const ids = Object.keys(map);
    if (ids.length <= MAX_STAMPS) return;
    ids.filter(k => !map[k].dirty).sort((a, b) => map[a].at - map[b].at)
      .slice(0, ids.length - MAX_STAMPS).forEach(k => delete map[k]);
  }
  function saveStamps(s) {
    prune(s.h); prune(s.f);
    try { localStorage.setItem(KEYS.stamps, JSON.stringify(s)); } catch { /* storage unavailable */ }
  }
  function stamp(kind, id, fields) {
    const s = stamps();
    const row = { at: Date.now(), dirty: 1, ...fields };
    if (kind === 'q') s.q = row; else s[kind][id] = row;
    saveStamps(s);
  }

  /* ---- Resume positions ---- */
  function position(id) { return read(KEYS.positions, {})[id] || null; }
  function savePosition(id, t, d) {
    const all = read(KEYS.positions, {});
    all[id] = { t: Math.floor(t), d: Math.floor(d || 0), at: Date.now() };
    const ids = Object.keys(all);
    if (ids.length > MAX_POSITIONS) {
      ids.sort((a, b) => all[a].at - all[b].at).slice(0, ids.length - MAX_POSITIONS).forEach(k => delete all[k]);
    }
    stamp('h', id, { del: 0 });
    write(KEYS.positions, all);
  }
  /** Resume only inside the 10 s to 95 % window; outside it, start from the top. The catalog length, when known, bounds the window too. */
  function resumeAt(id, length) {
    const p = position(id);
    if (!p || !p.d) return 0;
    if (length > 0 && p.t >= length * 0.95) return 0;
    return p.t >= 10 && p.t < p.d * 0.95 ? p.t : 0;
  }
  function progress(id) {
    const p = position(id);
    return p && p.d ? Math.min(1, p.t / p.d) : 0;
  }

  /* ---- History ---- */
  function history() { return read(KEYS.history, []); }
  function addHistory(ep) {
    const h = history().filter(x => x.id !== ep.id);
    h.unshift({ ...card(ep), at: Date.now() });
    stamp('h', ep.id, { del: 0 });
    write(KEYS.history, h.slice(0, MAX_HISTORY));
  }
  /** Every row becomes a removal marker, so a signed-in clearing reaches the other devices. */
  function clearHistory() {
    const s = stamps();
    const at = Date.now();
    const ids = new Set([...history().map(x => x.id), ...Object.keys(read(KEYS.positions, {})),
                         ...Object.keys(s.h).filter(k => !s.h[k].del)]);
    ids.forEach(id => { s.h[id] = { at, del: 1, dirty: 1 }; });
    saveStamps(s);
    write(KEYS.history, []); write(KEYS.positions, {});
  }
  /** continueListening (contract §5): started, not finished, most recent first. */
  function inProgress(limit = 10) {
    return history().filter(x => resumeAt(x.id) > 0).slice(0, limit);
  }

  /* ---- Queue ---- */
  function queue() { return read(KEYS.queue, []); }
  function enqueue(ep) {
    const q = queue().filter(x => x.id !== ep.id);
    q.push(card(ep));
    stamp('q');
    write(KEYS.queue, q);
  }
  function dequeue(id) { stamp('q'); write(KEYS.queue, queue().filter(x => x.id !== id)); }
  function moveInQueue(id, delta) {
    const q = queue();
    const i = q.findIndex(x => x.id === id);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= q.length) return;
    [q[i], q[j]] = [q[j], q[i]];
    stamp('q');
    write(KEYS.queue, q);
  }
  function inQueue(id) { return queue().some(x => x.id === id); }

  /* ---- Followed series ---- */
  function follows() { return read(KEYS.follows, []); }
  function isFollowing(key) { return follows().some(s => s.key === key); }
  function toggleFollow(series) {
    const f = follows();
    const next = f.some(s => s.key === series.key) ? f.filter(s => s.key !== series.key)
      : [{ key: series.key, name: series.name, genre: series.genre || null, first: series.first || null,
           last: series.last || null, episodes: series.episodes || null, networks: series.networks || null }, ...f];
    const on = next.some(s => s.key === series.key);
    stamp('f', series.key, { on: on ? 1 : 0 });
    write(KEYS.follows, next);
    return on;
  }

  function rate() { return Number(read(KEYS.rate, 1)) || 1; }
  function setRate(r) { write(KEYS.rate, r); }

  function onChange(fn) { listeners.add(fn); }

  /* ---- Sync (js/sync.js; the Worker's upload shape, docs/WORKER.md) ---- */

  /**
   * An upload for the Worker. `all` (the one-time merge after sign-in) sends every
   * row this device has, stamping any kept before stamps existed; otherwise only
   * the rows the Worker does not have yet. At most 500 of each, newest first.
   */
  function syncUpload({ all = false, device = 'web' } = {}) {
    const s = stamps();
    const now = Date.now();
    const pos = read(KEYS.positions, {});
    const hist = history();
    if (all) {
      const histAt = new Map(hist.map(x => [x.id, x.at || 0]));
      new Set([...hist.map(x => x.id), ...Object.keys(pos)]).forEach(id => {
        if (s.h[id]) return;
        const at = Math.max((pos[id] && pos[id].at) || 0, histAt.get(id) || 0);
        s.h[id] = { at: Math.min(now, at || now), del: 0, dirty: 1 };
      });
      follows().forEach(f => { if (!s.f[f.key]) s.f[f.key] = { at: now, on: 1, dirty: 1 }; });
      if (!s.q && queue().length) s.q = { at: now, dirty: 1 };
      saveStamps(s);
    }
    const pick = (map) => Object.keys(map).filter(k => all || map[k].dirty)
      .sort((a, b) => map[b].at - map[a].at).slice(0, MAX_UPLOAD);
    const historyRows = pick(s.h).map(id => {
      const st = s.h[id];
      if (st.del) return { episode_id: id, position: 0, finished: false, deleted: true, updated_at: st.at };
      const p = pos[id];
      const t = p ? Math.max(0, p.t || 0) : 0;
      const d = p && p.d ? p.d : null;
      return { episode_id: id, position: t, duration: d, finished: !!(d && t >= d * 0.95), deleted: false,
               updated_at: st.at };
    });
    const followRows = pick(s.f).map(k => ({ series_id: k, following: !!s.f[k].on, updated_at: s.f[k].at }));
    const up = { device };
    if (historyRows.length) up.history = historyRows;
    if (followRows.length) up.follows = followRows;
    if (s.q && (all || s.q.dirty)) up.queue = { items: queue().map(x => x.id).slice(0, MAX_UPLOAD), updated_at: s.q.at };
    return up;
  }

  /** After the Worker took an upload: a row is clean unless it changed again meanwhile. */
  function markSynced(up) {
    const s = stamps();
    (up.history || []).forEach(r => { const st = s.h[r.episode_id]; if (st && st.at === r.updated_at) st.dirty = 0; });
    (up.follows || []).forEach(r => { const st = s.f[r.series_id]; if (st && st.at === r.updated_at) st.dirty = 0; });
    if (up.queue && s.q && s.q.at === up.queue.updated_at) s.q.dirty = 0;
    saveStamps(s);
  }

  function hasPending() {
    const s = stamps();
    return Object.values(s.h).some(x => x.dirty) || Object.values(s.f).some(x => x.dirty) || !!(s.q && s.q.dirty);
  }

  /**
   * Rows from GET /v1/sync, last write wins per row by updated_at: a row applies
   * only when it is newer than this device's, and a tie keeps this device's.
   * `deleted: true` and `following: false` are removal markers. The Worker keeps
   * no cards, so an episode or series new to this device arrives as a stub
   * ({ id } or { key }) for the app to fill (stubs, fillCards). Returns the
   * number of rows that changed here.
   */
  function applyRemote(remote) {
    const s = stamps();
    const pos = read(KEYS.positions, {});
    let hist = history();
    let fol = follows();
    let changed = 0;
    for (const r of (remote && remote.history) || []) {
      const id = r.episode_id;
      const old = hist.find(x => x.id === id);
      const localAt = s.h[id] ? s.h[id].at : Math.max((pos[id] && pos[id].at) || 0, (old && old.at) || 0);
      if (!(r.updated_at > localAt)) continue;
      changed++;
      if (r.deleted) {
        delete pos[id];
        hist = hist.filter(x => x.id !== id);
        s.h[id] = { at: r.updated_at, del: 1, dirty: 0 };
        continue;
      }
      pos[id] = { t: Math.floor(r.position || 0), d: Math.floor(r.duration || 0), at: r.updated_at };
      hist = hist.filter(x => x.id !== id);
      hist.push(old ? { ...old, at: Math.max(old.at || 0, r.updated_at) } : { id, at: r.updated_at });
      s.h[id] = { at: r.updated_at, del: 0, dirty: 0 };
    }
    hist.sort((a, b) => (b.at || 0) - (a.at || 0));
    for (const r of (remote && remote.follows) || []) {
      const key = r.series_id;
      if (!(r.updated_at > (s.f[key] ? s.f[key].at : 0))) continue;
      changed++;
      const has = fol.some(x => x.key === key);
      if (r.following && !has) fol = [{ key, name: null }, ...fol];
      if (!r.following && has) fol = fol.filter(x => x.key !== key);
      s.f[key] = { at: r.updated_at, on: r.following ? 1 : 0, dirty: 0 };
    }
    const rq = remote && remote.queue;
    let q = null;
    if (rq && Array.isArray(rq.items) && rq.updated_at > (s.q ? s.q.at : 0)) {
      changed++;
      const known = new Map([...hist, ...queue()].filter(x => x.url || x.title).map(x => [x.id, x]));
      q = rq.items.map(id => known.has(id) ? card(known.get(id)) : { id });
      s.q = { at: rq.updated_at, dirty: 0 };
    }
    saveStamps(s);
    if (changed) {
      write(KEYS.positions, pos);
      write(KEYS.history, hist.slice(0, MAX_HISTORY));
      write(KEYS.follows, fol);
      if (q) write(KEYS.queue, q);
    }
    return changed;
  }

  /** Episodes and series that arrived from the Worker without a card. */
  function stubs() {
    const isStub = (x) => !x.url && !x.title;
    return {
      episodes: [...new Set([...history(), ...queue()].filter(isStub).map(x => x.id))],
      series: follows().filter(x => !x.name).map(x => x.key),
    };
  }
  /** Fill stubs with cards the app built. Nothing is stamped: no listening changed. */
  function fillCards({ episodes = {}, series = {} } = {}) {
    if (Object.keys(episodes).length) {
      const fill = (x) => episodes[x.id] && !x.url && !x.title ? { ...card(episodes[x.id]), ...(x.at ? { at: x.at } : {}) } : x;
      write(KEYS.history, history().map(fill));
      write(KEYS.queue, queue().map(fill));
    }
    if (Object.keys(series).length) {
      write(KEYS.follows, follows().map(x => series[x.key] && !x.name ? { ...series[x.key], key: x.key } : x));
    }
  }

  /** Signed out or deleted: the listening stays here, and every row counts as unsent again. */
  function forgetSync() {
    const s = stamps();
    Object.values(s.h).forEach(x => { x.dirty = 1; });
    Object.values(s.f).forEach(x => { x.dirty = 1; });
    if (s.q) s.q.dirty = 1;
    saveStamps(s);
  }

  return { position, savePosition, resumeAt, progress, history, addHistory, clearHistory, inProgress,
           queue, enqueue, dequeue, moveInQueue, inQueue, follows, isFollowing, toggleFollow, rate, setRate,
           onChange, card, syncUpload, markSynced, hasPending, applyRemote, stubs, fillCards, forgetSync };
})();
