/**
 * Record in the room on this device (PLAYS-DESIGN §12.10, WEB-DESIGN §4.17 item 9): no DOM. The
 * room's rules are ReadCore's (the protocol's port); the take engine is the studio's
 * RecordingSession (`recordInRoom`, no cue played); the takes live in a local production kept for
 * this room (`room: CODE`), in the same store as every production, so Listen through, Export and
 * Publish work on it as on any other.
 *
 * - A reader's device opens its microphone when the cursor reaches a line it holds (ReadCore
 *   .shouldRecord), keeps the take on the device first, sends `line-done`, and puts the take in
 *   its outbox, sent through the Worker to the room's receiving device; a take nobody is there to
 *   receive (`409 nobody_receiving`), or one caught by a dropped network, waits and is sent again.
 * - The receiving device (`you.receives`) holds the room's pickup while the room records and
 *   imports each take that arrives.
 * - One microphone: the leader's device records the line at the cursor whoever holds it and moves
 *   the cursor on (§12.10 item 6).
 *
 * Every device is passed in (api, store, the engine), so js/read.test.js runs this file against a
 * stub Worker and a stub microphone, recording and playing nothing.
 */
const ReadRecord = (() => {
  'use strict';
  const RETRY_MS = 5000;
  /** Refusals that mean "try again later": the take stays in the outbox. */
  const LATER = new Set(['nobody_receiving', 'one_take_at_a_time', 'offline', 'error', 'rate_limited', 'timeout', 'not_configured', 'not_delivered']);

  function make({ api, store, session, script, cast, core = ReadCore, plays = PlaysCore, engine, timers = globalThis, onChange = () => {}, diag = () => {}, trace = () => {} }) {
    const st = {
      code: null, localId: null, outbox: [], sending: false, recording: null, justDid: null, armed: false,
      oneMic: false, receiving: false, arrived: 0, lastError: null, failed: null,
    };
    let rec = null;
    let retryTimer = null;
    let pickupRun = 0;
    let stopped = false;
    const changed = () => { try { onChange(st); } catch (e) { console.error(e); } };
    const snap = () => session.state().snap;
    const codeOf = (err) => (err && (err.code || err.kind)) || 'error';
    const partOf = (line) => { const l = cast.find((x) => x[0] === line); return l ? l[1] : null; };

    /** The local production for this room, made on the first take or arrival; its outbox is persisted with it. */
    async function production() {
      const s = snap();
      if (st.localId) { const p = store.production(st.localId); if (p) return p; }
      const found = store.productions.find((p) => p.room === s.code);
      if (found) { st.localId = found.id; st.outbox = (found.roomOutbox || []).slice(); return found; }
      const made = await store.create(script);
      const p = { ...made, room: s.code, roomPid: s.production_id || null, roomKind: s.kind, roomOutbox: [] };
      await store.save(p);
      st.localId = p.id;
      return p;
    }

    async function saveOutbox() {
      const p = store.production(st.localId);
      if (p) await store.save({ ...p, roomOutbox: st.outbox.slice() });
    }

    /** The engine is made once per room and started by the reader's Start recording (the permission and room tone). */
    async function engineFor() {
      if (rec) return rec;
      const p = await production();
      rec = engine({ production: p, script, part: partOf(snap().cursor) || cast[0][1], store });
      return rec;
    }

    /** Start recording: the one tap a reader gives before the first take (§12.10 item 1). */
    async function arm() {
      const e = await engineFor();
      await e.begin();
      st.armed = !!e.started;
      st.failed = e.phase && e.phase.kind === 'failed' ? e.phase.reason : null;
      changed();
      if (st.armed) onSnapshot();
    }

    /** Stop: the reader's tap ends the take now (the line-end detector ends it on its silence otherwise). */
    function stop() { if (rec) rec.stopListening(); }

    async function record(line, { credit = false } = {}) {
      const base = snap().cursor_gen;
      st.justDid = line;
      st.recording = line;
      diag(line);
      trace('take', line, 'start gen', base);
      changed();
      const e = await engineFor();
      let take = null;
      try {
        take = await e.recordInRoom(line, partOf(line), 'room');
      } catch (err) {
        console.error('room take', err);
      }
      st.recording = null;
      if (stopped) return;
      if (!take) { st.justDid = null; changed(); return; }
      const now = snap();
      trace('take', line, 'end cursor', now.cursor, 'gen', now.cursor_gen, 'done', (now.done || []).includes(line) ? 1 : 0);
      if (credit) {
        // One microphone: the take is already here. A room with a production writes the director's own row.
        const reads = core.whoReads(core.roomOf(now), cast, (now.members || []).map((m) => ({ ...m, seen_at: 0 })), line, 0);
        if (now.production_id && api.plays && api.plays.upload) {
          const bytes = await store.readTake(st.localId, take.file);
          api.plays.upload(now.production_id, take.id, bytes, { ...metaOf(take), ...(reads && reads.seat ? { seat: reads.seat } : {}) })
            .catch((err) => { st.lastError = codeOf(err); changed(); });
        }
        const next = core.step(cast, line, 1);
        if (next && now.cursor === line) session.send({ type: 'cursor', line: next, base: now.cursor_gen }).catch(() => {});
      } else {
        st.outbox.push(take.id);
        await saveOutbox();
        // Sent even when the leader has moved the cursor away: the take exists, so the line is done and its microphone
        // does not open again when the cursor comes back (T7c; the Worker leaves the cursor where the leader put it).
        trace('line-done', line, 'base', now.cursor_gen, 'sent', now.cursor === line ? '' : `cursor ${now.cursor}`);
        session.send({ type: 'line-done', line, base: now.cursor_gen }).catch((err) => trace('line-done', line, 'refused', codeOf(err)));
        flush();
      }
      changed();
    }

    const metaOf = (t) => {
      const m = { lineID: t.lineID, part: t.part, file: t.file, created: t.created, frames: t.frames, sampleRate: t.sampleRate,
                  capture: 'room', heard: {}, peak: t.peak || 0 };
      if (typeof t.loudness === 'number' && isFinite(t.loudness)) m.loudness = t.loudness;
      return m;
    };

    /** Sends the outbox one take at a time; a "later" refusal stops and waits RETRY_MS, any other drops it (the take stays here). */
    async function flush() {
      if (st.sending || stopped || !st.outbox.length) return;
      const s = snap();
      const key = session.state().key;
      if (!s || !key || s.ended) return;
      st.sending = true;
      try {
        while (st.outbox.length && !stopped) {
          const id = st.outbox[0];
          const p = store.production(st.localId);
          const t = p && p.takes.find((x) => x.id === id);
          if (!t) { st.outbox.shift(); continue; }
          try {
            const bytes = await store.readTake(st.localId, t.file);
            await api.read.sendTake(s.code, key, t.id, bytes, metaOf(t));
            st.outbox.shift();
            st.lastError = null;
          } catch (err) {
            const c = codeOf(err);
            if (LATER.has(c) || (err && err.status >= 500)) { st.lastError = c; break; }
            st.outbox.shift();
            st.lastError = c;
          }
          await saveOutbox();
          changed();
        }
      } finally {
        st.sending = false;
      }
      if (st.outbox.length && !stopped) {
        if (retryTimer) timers.clearTimeout(retryTimer);
        retryTimer = timers.setTimeout(() => { retryTimer = null; flush(); }, RETRY_MS);
      }
      changed();
    }

    /** The receiving device's pickup loop while the room records; each arrival joins the room production. */
    function holdPickup() {
      if (st.receiving) return;
      st.receiving = true;
      const mine = ++pickupRun;
      changed();
      (async () => {
        let wait = 0;
        while (mine === pickupRun && !stopped) {
          const s = snap();
          const key = session.state().key;
          if (!s || !key || s.ended) break;
          try {
            const got = await api.read.inbox(s.code, key);
            wait = 0;
            if (got && mine === pickupRun) await accept(got.take, got.bytes);
          } catch (err) {
            if (['receivers_only', 'not_a_member', 'room_ended', 'no_such_room'].includes(codeOf(err)) || err.status === 503) break;
            wait = Math.min(30000, wait ? wait * 2 : 2000);
            await new Promise((r) => timers.setTimeout(r, wait));
          }
        }
        if (mine === pickupRun) { st.receiving = false; changed(); }
      })();
    }
    function dropPickup() { pickupRun += 1; st.receiving = false; }

    /** A take that arrived: written once under its own id, the line's chosen take (the newest wins, as on the Worker). */
    async function accept(t, bytes) {
      const p = await production();
      if (p.takes.some((x) => x.id === t.id)) return;
      const file = `r-${t.id}.wav`;
      await store.importTake(p.id, file, bytes);
      const take = { id: t.id, lineID: t.lineID, part: t.part, file, created: plays.now(), frames: t.frames, sampleRate: t.sampleRate,
                     capture: 'room', heard: {}, peak: 0, bleed: false, seat: t.seat || null, member: t.member || null };
      await store.save(plays.addTake(store.production(p.id), take));
      st.arrived += 1;
      changed();
    }

    /** Every snapshot: settle `justDid`, open the microphone when it is this device's line, hold or drop the pickup, send the outbox. */
    function onSnapshot() {
      const s = snap();
      if (!s || stopped) return;
      const had = st.justDid;
      st.justDid = core.settleJustDid(s, st.justDid);
      if (had && !st.justDid) trace('justDid', had, 'cleared cursor', s.cursor, 'gen', s.cursor_gen, 'recording', st.recording || '-');
      if (s.ended) { dropPickup(); return; }
      const recording = s.mode === 'record';
      if (recording && s.you && s.you.receives) holdPickup(); else if (st.receiving) dropPickup();
      if (st.armed && !st.recording) {
        if (st.oneMic && s.you && s.you.leads && recording) {
          const part = partOf(s.cursor);
          if (part && plays.isSpeaking(part) && !(s.done || []).includes(s.cursor) && st.justDid !== s.cursor) record(s.cursor, { credit: true });
        } else if (core.shouldRecord(s, cast, st.justDid)) {
          record(s.cursor);
        }
      }
      if (st.outbox.length) flush();
    }

    /**
     * Loads this room's production (and its outbox) when one exists already: a reload keeps waiting
     * takes. Then acts on the snapshot in hand, since a long poll brings the next only on a change.
     */
    async function resume() {
      const s = snap();
      const found = s && store.productions.find((p) => p.room === s.code);
      if (found) { st.localId = found.id; st.outbox = (found.roomOutbox || []).slice(); }
      changed();
      onSnapshot();
    }

    const off = session.onChange((kind) => { if (kind === 'snapshot' || kind === 'transport') onSnapshot(); });

    return {
      state: () => st,
      arm, stop, flush, resume, onSnapshot,
      production: () => (st.localId ? store.production(st.localId) : null),
      ensureProduction: production,
      /** One microphone on or off (the leader's Record every line here). */
      setOneMic(on) { st.oneMic = !!on; changed(); onSnapshot(); },
      /** Lines with a take on this device. */
      arrivedLines() { const p = st.localId && store.production(st.localId); return new Set(p ? Object.keys(p.chosen) : []); },
      detach() {
        stopped = true;
        off();
        dropPickup();
        if (retryTimer) timers.clearTimeout(retryTimer);
        if (rec) rec.end();
      },
    };
  }

  return { make, RETRY_MS };
})();
if (typeof module !== 'undefined') module.exports = ReadRecord;
