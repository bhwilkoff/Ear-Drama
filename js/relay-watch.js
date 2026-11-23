/**
 * Relay across time on this device (PLAYS-DESIGN §12.11): one RelayCore sender per production
 * that has takes to pass through, kept alive while the app is open. No DOM. A production is linked
 * to the Worker either as a seat's (`share.seat = { key, class_id, label }`: no account, the seat
 * key) or as a member's (`share.pid`, signed in). The take stays in this device's production;
 * `share.sent` remembers which ones passed through, so "Sent" reads the same offline.
 *
 * Every dependency is passed in (api, store, timers, online), so js/relay.test.js runs this file
 * against a stub Worker and a memory store, recording and playing nothing.
 */
const RelayWatch = (() => {
  'use strict';
  const C = PlaysCore;
  const R = RelayCore;
  /**
   * How often an open tab asks again: every 30 s while a take waits to pass through, every 5 minutes
   * when the last ask found nothing, and never while the page is hidden (each ask is a Worker request
   * on the free account every app shares; recording, the network returning, and the page coming back
   * all kick at once).
   */
  const BUSY_MS = 30000;
  const QUIET_MS = 5 * 60 * 1000;

  function make({ api, store, me = () => null, timers = globalThis, online, onChange = () => {}, doc = typeof document !== 'undefined' ? document : null }) {
    const senders = new Map();
    const listeners = new Set();
    let idle = null;
    let stopped = false;

    const link = (id) => store.share(id) || {};
    const patch = (id, fields) => store.setShare(id, { ...link(id), ...fields });
    const castOf = (script) => script.lines.map((l) => [l.id, C.linePart(l)]);

    /** The takes of `lines` (script order) that have not passed through: chosen, not flagged, not sent, not refused. */
    function unsent(local, lines, sentIds, refused) {
      const out = [];
      for (const id of lines) {
        const t = C.chosenTake(local, id);
        if (!t || t.bleed || sentIds.has(t.id) || (refused && refused[t.id])) continue;
        out.push(t);
      }
      return out;
    }

    function seatSource(id, script) {
      const l0 = () => link(id).seat;
      const pid = () => link(id).pid;
      return {
        async pending() {
          let remote = new Set();
          try {
            const home = await api.plays.seatHome(l0().key);
            const prod = (home.productions || []).find((p) => p.id === pid());
            if (prod) {
              remote = new Set((prod.takes || []).map((t) => t.id));
              await patch(id, { assignments: prod.assignments || [] });
            }
          } catch (e) {
            if (e && (e.code === 'seat_key_required' || e.status === 401)) return [];
          }
          const lines = R.assignedLines(castOf(script), link(id).assignments || []);
          return unsent(store.production(id), lines, new Set([...(link(id).sent || []), ...remote]), link(id).refused);
        },
        probe: () => api.plays.seatReceiver(l0().key, pid()),
        async send(t) {
          const bytes = await store.readTake(id, t.file);
          try { await api.plays.seatSend(l0().key, pid(), t.id, bytes, PlaysShare.metaOf(t)); } catch (e) { if (!(e && e.code === 'take_exists')) throw e; }
        },
        sent: (t) => patch(id, { sent: [...new Set([...(link(id).sent || []), t.id])] }),
        refused: (t, code) => patch(id, { refused: { ...(link(id).refused || {}), [t.id]: code } }),
      };
    }

    function memberSource(id, script) {
      const pid = () => link(id).pid;
      return {
        async pending() {
          const rec = await api.plays.get(pid());
          if (!PlaysShare.uploadsOpen(rec)) return [];
          return PlaysShare.pending(store.production(id), script, rec, me()).filter((t) => !t.bleed && !(link(id).refused || {})[t.id]);
        },
        probe: () => api.plays.receiver(pid()),
        async send(t) {
          const bytes = await store.readTake(id, t.file);
          try { await api.plays.upload(pid(), t.id, bytes, PlaysShare.metaOf(t)); } catch (e) { if (!(e && e.code === 'take_exists')) throw e; }
        },
        sent: (t) => patch(id, { sent: [...new Set([...(link(id).sent || []), t.id])] }),
        refused: (t, code) => patch(id, { refused: { ...(link(id).refused || {}), [t.id]: code } }),
      };
    }

    /** The sender for a production, made on first need; null when it is not linked to the Worker. */
    async function senderFor(id) {
      if (senders.has(id)) return senders.get(id);
      const lk = link(id);
      const local = store.production(id);
      if (!local || !(lk.seat || lk.pid)) return null;
      const script = await store.script(local);
      if (!script) return null;
      const source = lk.seat ? seatSource(id, script) : memberSource(id, script);
      const s = R.make({ source, timers, online, onChange: (st) => { onChange(id, st); listeners.forEach((f) => f(id, st)); } });
      senders.set(id, s);
      return s;
    }

    async function kick(id) {
      if (stopped) return;
      const ids = id ? [id] : store.productions.filter((p) => link(p.id).seat || link(p.id).pid).map((p) => p.id);
      for (const x of ids) { try { const s = await senderFor(x); if (s) await s.kick(); } catch (e) { console.error(e); } }
    }

    /** Nothing waits on any sender: the last ask of each found no take to send. */
    const quiet = () => [...senders.values()].every((s) => s.state().idle);
    function next() {
      if (stopped) return;
      idle = timers.setTimeout(tick, quiet() ? QUIET_MS : BUSY_MS);
    }
    async function tick() {
      idle = null;
      if (stopped) return;
      if (!(doc && doc.hidden)) await kick();
      next();
    }

    function start() {
      stopped = false;
      if (idle) return;
      idle = true;
      kick().finally(() => { if (idle === true) next(); });
    }
    function stop() {
      stopped = true;
      if (idle && idle !== true) timers.clearTimeout(idle);
      idle = null;
      for (const s of senders.values()) s.stop();
      senders.clear();
    }

    /** One take's state for the screen: 'sent', 'sending', 'waiting' (or 'refused' with its code). */
    function takeState(id, takeId, remoteIds = []) {
      const lk = link(id);
      if (lk.refused && lk.refused[takeId]) return { state: 'refused', code: lk.refused[takeId] };
      const s = senders.get(id);
      const st = s ? s.state() : {};
      return { state: R.stateOf(takeId, { sent: [...(lk.sent || []), ...remoteIds], sending: st.sending }), name: st.name || null };
    }

    /** `fn(localId, state)` on every change of any sender; returns the way to stop listening. */
    const subscribe = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };

    return { kick, start, stop, takeState, senderFor, subscribe, state: (id) => (senders.get(id) ? senders.get(id).state() : null) };
  }

  const FLAG = 'ed.relay';
  let hub = null;
  /**
   * The one sender for this tab. The flag says this device has takes to pass through (set when a seat or
   * a member first records), so a tab that never recorded for a class never opens the store at start.
   */
  function shared(deps) {
    if (!hub) {
      hub = make(deps);
      if (typeof window !== 'undefined') {
        window.addEventListener('online', () => hub.kick());
        document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') hub.kick(); });
      }
    }
    return hub;
  }
  const flagged = () => { try { return localStorage.getItem(FLAG) === '1'; } catch { return false; } };
  const flag = () => { try { localStorage.setItem(FLAG, '1'); } catch { /* this tab only */ } };

  return { make, shared, flagged, flag };
})();
if (typeof module !== 'undefined') module.exports = RelayWatch;
