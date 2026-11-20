/**
 * A read room session on this device (WEB-DESIGN §4.17, PLAYS-DESIGN §12.1): the transport and
 * the room's latest snapshot, no DOM. Every call is `API.read` (AGENTS.md: one shared client).
 *
 * - The socket first (the Durable Object's hibernating WebSocket), its key in a first "hello"
 *   message, never the URL. A socket that will not open, closes, or a `poll_only` room falls
 *   back to polling the same room every second (ReadCore.POLL_MS) with the same messages, and
 *   the socket is tried again later. A school that blocks WebSockets never notices.
 * - Reconnect and reload resume with the member key from this tab's sessionStorage (`ed.read`),
 *   and the next snapshot puts the device back at the cursor.
 * - The clock: every answer and every pong is a sample; `offset()` is ReadCore.clockOffset over
 *   them, kept for T4's cursor-delay measurement. Logged only with `?readdiag=1`.
 * - A snapshot older than the one in hand is dropped (ReadCore.newer), so a slow poll never
 *   moves the cursor back.
 */
const ReadSession = (() => {
  'use strict';
  const KEY = 'ed.read';
  const PING_MS = 10000;
  const OPEN_WAIT_MS = 5000;
  const RETRY_MS = [2000, 5000, 15000, 30000];
  const GONE = new Set(['no_such_room', 'room_ended', 'not_a_member', 'seat_key_required']);

  function make({ api, core, timers = globalThis, now = () => Date.now(), storage = null, diag = false, log = console.log } = {}) {
    const listeners = new Set();
    const st = { code: null, key: null, role: null, wire: null, snap: null, transport: null, slow: false, error: null, ended: null, offset: null };
    let ws = null;
    let wsOpen = false;
    let pollTimer = null;
    let pingTimer = null;
    let retryTimer = null;
    let openTimer = null;
    let retries = 0;
    let run = 0;
    let lastOk = 0;

    const emit = (kind, detail) => listeners.forEach((fn) => { try { fn(kind, detail, st); } catch (e) { console.error(e); } });
    const save = () => {
      if (!storage) return;
      try {
        if (st.code && st.key) storage.setItem(KEY, JSON.stringify({ code: st.code, key: st.key, role: st.role }));
        else storage.removeItem(KEY);
      } catch { /* no storage: the room lasts as long as the page */ }
    };
    const said = (...a) => { if (diag) log('[readdiag]', ...a); };

    function apply(snap) {
      if (!snap || snap.type !== 'snapshot') return false;
      if (!core.newer(st.snap, snap)) return false;
      const was = st.snap;
      st.snap = snap;
      if (diag && (!was || was.cursor !== snap.cursor)) said('lit', snap.cursor, 'gen', snap.cursor_gen, 'at', now(), 'offset', st.offset);
      lastOk = now();
      if (st.slow) { st.slow = false; emit('slow', false); }
      if (st.error) { st.error = null; emit('error', null); }
      if (snap.ended) end('room_ended');
      emit('snapshot', was);
      return true;
    }

    function end(code) {
      if (st.ended) return;
      st.ended = code;
      stopTransport();
      st.key = null;
      save();
      emit('ended', code);
    }

    function stopTransport() {
      run += 1;
      [pollTimer, pingTimer, retryTimer, openTimer].forEach((t) => t && timers.clearTimeout(t));
      pollTimer = pingTimer = retryTimer = openTimer = null;
      if (ws) { try { ws.onclose = null; ws.close(); } catch { /* already closed */ } }
      ws = null;
      wsOpen = false;
    }

    function failed(err) {
      const code = (err && (err.code || err.kind)) || 'error';
      if (GONE.has(code)) { end(code); return; }
      if (code === 'offline' || code === 'error' || code === 'rate_limited') {
        if (st.error !== code) { st.error = code; emit('error', code); }
      }
    }

    /* ---- Polling ---- */
    function poll(mine) {
      if (mine !== run || st.ended) return;
      const t0 = now();
      api.read.poll(st.code, st.key).then((snap) => {
        if (mine !== run) return;
        const took = now() - t0;
        apply(snap);
        const slow = took > core.SLOW_MS;
        if (slow !== st.slow) { st.slow = slow; emit('slow', slow); }
      }).catch((err) => {
        if (mine !== run) return;
        failed(err);
        if (!st.slow && now() - lastOk > core.SLOW_MS) { st.slow = true; emit('slow', true); }
      }).finally(() => {
        if (mine === run && !st.ended && st.transport === 'poll') pollTimer = timers.setTimeout(() => poll(mine), core.POLL_MS);
      });
    }
    function startPolling(mine) {
      if (st.transport !== 'poll') { st.transport = 'poll'; emit('transport', 'poll'); said('transport poll'); }
      if (pollTimer) timers.clearTimeout(pollTimer);
      poll(mine);
    }

    /* ---- The socket ---- */
    function connect() {
      stopTransport();
      const mine = run;
      const sock = st.wire !== 'poll' ? api.read.socket(st.code) : null;
      schedulePing(mine);
      if (!sock) { startPolling(mine); return; }
      ws = sock;
      openTimer = timers.setTimeout(() => { if (mine === run && !wsOpen) fallBack(mine); }, OPEN_WAIT_MS);
      sock.onopen = () => {
        if (mine !== run) return;
        wsOpen = true;
        retries = 0;
        sock.send(JSON.stringify({ type: 'hello', key: st.key }));
        if (pollTimer) { timers.clearTimeout(pollTimer); pollTimer = null; }
        st.transport = 'socket';
        emit('transport', 'socket');
        said('transport socket');
      };
      sock.onmessage = (e) => {
        if (mine !== run) return;
        let msg;
        try { msg = JSON.parse(e.data); } catch { return; }
        if (msg.type === 'snapshot') apply(msg);
        else if (msg.type === 'pong') { api.read.sample(msg.t0, msg.server_time, now()); clock(); }
        else if (msg.type === 'error') {
          if (GONE.has(msg.error)) end(msg.error);
          else emit('refused', { code: msg.error, detail: msg.detail });
        }
      };
      sock.onclose = () => { if (mine === run && !st.ended) fallBack(mine); };
      sock.onerror = () => {};
    }
    function fallBack(mine) {
      if (mine !== run) return;
      if (ws) { try { ws.onclose = null; ws.close(); } catch { /* closed */ } }
      ws = null;
      wsOpen = false;
      startPolling(mine);
      const wait = RETRY_MS[Math.min(retries, RETRY_MS.length - 1)];
      retries += 1;
      retryTimer = timers.setTimeout(() => { if (mine === run && !st.ended) connect(); }, wait);
    }

    /* ---- The clock (T4) ---- */
    function clock() {
      st.offset = core.clockOffset(api.read.samples());
      said('clock offset', st.offset, 'samples', api.read.samples().length);
    }
    function schedulePing(mine) {
      pingTimer = timers.setTimeout(() => {
        if (mine !== run || st.ended) return;
        const t0 = now();
        if (ws && wsOpen) ws.send(JSON.stringify({ type: 'ping', t0 }));
        else api.read.send(st.code, st.key, { type: 'ping', t0 }).then((r) => { apply(r); clock(); }).catch(failed);
        schedulePing(mine);
      }, PING_MS);
    }

    function enter(snap, role) {
      st.code = snap.code;
      st.key = snap.member_key;
      st.role = role;
      st.wire = snap.transport || 'socket';
      st.ended = null;
      st.snap = null;
      apply(snap);
      clock();
      save();
      connect();
      return snap;
    }

    return {
      state: () => st,
      onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
      /** Opens a room as its leader. */
      open: async (body) => enter(await api.read.create(body), 'reader'),
      /** Joins by code: `{ role?, seat?, seat_key?, move? }`. */
      join: async (code, want = {}) => enter(await api.read.join(code, want), want.role || 'reader'),
      /** A snapshot with its member key that came another way (a TV's pairing): this device is now in that room. */
      adopt: (snap, role) => enter(snap, role),
      /** Back into the room this tab was in, with its key; false when there is none or it is over. */
      async resume(code) {
        let kept = null;
        try { kept = storage && JSON.parse(storage.getItem(KEY) || 'null'); } catch { kept = null; }
        if (!kept || !kept.key || (code && kept.code !== code)) return false;
        try {
          const snap = await api.read.poll(kept.code, kept.key);
          st.code = kept.code; st.key = kept.key; st.role = kept.role; st.wire = 'socket'; st.ended = null; st.snap = null;
          apply(snap);
          clock();
          connect();
          return true;
        } catch (err) {
          if (GONE.has(err && err.code)) { try { storage.removeItem(KEY); } catch { /* none */ } }
          return false;
        }
      },
      /**
       * One message to the room. On the socket the answer is the next snapshot (or an "error"
       * message, emitted as 'refused'); over HTTP the snapshot comes back, or the refusal is thrown.
       */
      async send(msg) {
        if (!st.key || st.ended) throw { code: st.ended || 'not_a_member' };
        if (ws && wsOpen) { ws.send(JSON.stringify(msg)); return null; }
        try {
          const r = await api.read.send(st.code, st.key, msg);
          if (r && r.ended) end('room_ended'); else apply(r);
          return r;
        } catch (err) {
          if (err && err.code === 'stale') api.read.poll(st.code, st.key).then(apply).catch(() => {});
          else if (GONE.has(err && err.code)) end(err.code);
          throw err;
        }
      },
      /** Stops following on this device (the room drops a quiet member after 2 minutes). */
      /** Stops the transport on leaving the page; the key stays in this tab, so coming back resumes. */
      pause() { stopTransport(); },
      leave() { stopTransport(); st.key = null; st.code = null; st.snap = null; st.ended = null; save(); emit('left'); },
      offset: () => st.offset,
    };
  }

  return { make, KEY };
})();
if (typeof module !== 'undefined') module.exports = ReadSession;
