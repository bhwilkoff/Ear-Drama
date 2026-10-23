/**
 * The person's own listening, kept on this device until accounts (M5):
 * resume positions, history, the queue, and followed series.
 *
 * localStorage, every access guarded: a private window or blocked storage
 * leaves the app working, just forgetful. An episode is stored as the small
 * card the lists draw: { id, title, series, seriesName, date, url, length }.
 */
const Store = (() => {
  'use strict';

  const KEYS = { positions: 'ed.positions', history: 'ed.history', queue: 'ed.queue', follows: 'ed.follows',
                 rate: 'ed.rate' };
  const MAX_HISTORY = 200;
  const MAX_POSITIONS = 500;
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

  /* ---- Resume positions ---- */
  function position(id) { return read(KEYS.positions, {})[id] || null; }
  function savePosition(id, t, d) {
    const all = read(KEYS.positions, {});
    all[id] = { t: Math.floor(t), d: Math.floor(d || 0), at: Date.now() };
    const ids = Object.keys(all);
    if (ids.length > MAX_POSITIONS) {
      ids.sort((a, b) => all[a].at - all[b].at).slice(0, ids.length - MAX_POSITIONS).forEach(k => delete all[k]);
    }
    write(KEYS.positions, all);
  }
  /** Resume only inside the 10 s to 95 % window; outside it, start from the top. */
  function resumeAt(id) {
    const p = position(id);
    if (!p || !p.d) return 0;
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
    write(KEYS.history, h.slice(0, MAX_HISTORY));
  }
  function clearHistory() { write(KEYS.history, []); write(KEYS.positions, {}); }
  /** continueListening (contract §5): started, not finished, most recent first. */
  function inProgress(limit = 10) {
    return history().filter(x => resumeAt(x.id) > 0).slice(0, limit);
  }

  /* ---- Queue ---- */
  function queue() { return read(KEYS.queue, []); }
  function enqueue(ep) {
    const q = queue().filter(x => x.id !== ep.id);
    q.push(card(ep));
    write(KEYS.queue, q);
  }
  function dequeue(id) { write(KEYS.queue, queue().filter(x => x.id !== id)); }
  function moveInQueue(id, delta) {
    const q = queue();
    const i = q.findIndex(x => x.id === id);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= q.length) return;
    [q[i], q[j]] = [q[j], q[i]];
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
    write(KEYS.follows, next);
    return next.some(s => s.key === series.key);
  }

  function rate() { return Number(read(KEYS.rate, 1)) || 1; }
  function setRate(r) { write(KEYS.rate, r); }

  function onChange(fn) { listeners.add(fn); }

  return { position, savePosition, resumeAt, progress, history, addHistory, clearHistory, inProgress,
           queue, enqueue, dequeue, moveInQueue, inQueue, follows, isFollowing, toggleFollow, rate, setRate,
           onChange, card };
})();
