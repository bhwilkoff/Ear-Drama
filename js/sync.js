/**
 * Sync between this browser's Store and the Worker (LOOP-PLAN M5, Decision 063,
 * docs/WORKER.md). Only for someone signed in; nothing here runs otherwise.
 *
 * One run: the first after sign-in sends everything this device kept signed out
 * to /v1/sync/merge, once; every later run PUTs only the rows the Worker does
 * not have. Then it reads GET /v1/sync?since=<the last answer's server_time>
 * and applies the rows last-write-wins (Store.applyRemote). One run at a time.
 *
 * When: on load, when the page becomes visible or hidden, back online, Sync
 * now, and 10 s after the listening changes (at most 2 min while it keeps
 * changing, as it does every 5 s during play). Refreshing the token is the API
 * client's job, before each call.
 */
const Sync = (() => {
  'use strict';

  const QUIET_MS = 10 * 1000;
  const MAX_WAIT_MS = 2 * 60 * 1000;
  const acct = API.account;
  const listeners = new Set();
  let running = null;
  let quiet = null;
  let firstDirty = 0;
  let applying = false;
  let toCard = null;

  function emit(kind) { listeners.forEach(fn => { try { fn(kind); } catch (e) { console.error(e); } }); }

  function quietly(fn) {
    applying = true;
    try { return fn(); } finally { applying = false; }
  }

  async function doRun() {
    try {
      if (acct.state().merge_pending) {
        const up = Store.syncUpload({ all: true, device: acct.device });
        await acct.syncMerge(up);
        Store.markSynced(up);
        acct.update({ merge_pending: false, since: 0 });
      }
      for (let i = 0; i < 4 && Store.hasPending(); i++) {
        const up = Store.syncUpload({ device: acct.device });
        if (!up.history && !up.follows && !up.queue) break;
        await acct.syncPut(up);
        Store.markSynced(up);
      }
      const remote = await acct.syncRead(acct.state().since || 0);
      const changed = quietly(() => Store.applyRemote(remote));
      acct.update({ since: remote.server_time, last_sync_at: Date.now(), last_error: null });
      emit(changed ? 'changed' : 'synced');
      if (changed) hydrate().catch(e => console.error('sync cards', e));
      return true;
    } catch (e) {
      console.error('sync', e);
      if (acct.signedIn()) acct.update({ last_error: { kind: (e && e.kind) || 'error', at: Date.now() } });
      emit('error');
      return false;
    }
  }

  /** One run at a time; a call during a run gets that run. */
  function run() {
    if (!acct.signedIn()) return Promise.resolve(false);
    clearTimeout(quiet); quiet = null; firstDirty = 0;
    if (!running) running = doRun().finally(() => { running = null; });
    return running;
  }

  function soon() {
    if (!acct.signedIn() || applying) return;
    const now = Date.now();
    if (!firstDirty) firstDirty = now;
    clearTimeout(quiet);
    quiet = setTimeout(run, Math.max(0, Math.min(QUIET_MS, firstDirty + MAX_WAIT_MS - now)));
  }

  /**
   * Rows that came from the Worker, or ids forwarding moved, arrive as ids; the catalog fills in
   * what the lists draw. Every stub, in batches of HYDRATE_BATCH, each batch drawn as it lands.
   */
  const HYDRATE_BATCH = 60;
  async function hydrate() {
    const { episodes, series } = Store.stubs();
    if (!episodes.length && !series.length) return;
    const idx = await API.seriesIndex().catch(() => null);
    const seriesCards = {};
    if (idx) series.forEach(k => { const s = idx.byKey.get(k); if (s) seriesCards[k] = s; });
    for (let i = 0; i === 0 || i < episodes.length; i += HYDRATE_BATCH) {
      const cards = { episodes: {}, series: i === 0 ? seriesCards : {} };
      for (const id of episodes.slice(i, i + HYDRATE_BATCH)) {
        const d = await API.episodeDetail(id).catch(() => null);
        if (!d || !d.recordings || !d.recordings.length) continue;
        const s = idx && idx.byKey.get(d.series);
        cards.episodes[id] = toCard ? toCard(d, s ? s.name : d.series) : { id };
      }
      quietly(() => Store.fillCards(cards));
      emit('changed');
    }
  }

  function start({ card } = {}) {
    toCard = card || null;
    Store.onChange((key) => { if (key !== 'ed.rate') soon(); });
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', () => { if (acct.signedIn()) run(); });
    }
    if (typeof window !== 'undefined') window.addEventListener('online', () => { if (acct.signedIn()) run(); });
    if (acct.signedIn()) {
      run();
      if (Store.stubs().episodes.length || Store.stubs().series.length) hydrate().catch(() => {});
    }
  }

  /** Signed out here: the listening stays, and every row counts as unsent for the next account. */
  async function signOut() {
    await acct.signOut();
    Store.forgetSync();
    emit('signed-out');
  }
  async function deleteAccount(opts) {
    const r = await acct.deleteAccount(opts);
    Store.forgetSync();
    emit('signed-out');
    return r;
  }

  return { run, start, signOut, deleteAccount, hydrate, onChange(fn) { listeners.add(fn); },
           get running() { return !!running; } };
})();
