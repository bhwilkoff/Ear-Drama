/**
 * Listen Together on the web (WEB-DESIGN §4.12, LOOP-PLAN M6, Decision 065):
 * the room session. No DOM here; js/together-ui.js draws it.
 *
 * The rules are the protocol's (js/together-core.js, ported from
 * worker/src/room-protocol.js): the host publishes STATE when it changes,
 * never the playhead; the server is the clock; members read on the protocol's
 * cadence and extrapolate between reads; a guest corrects by rate before it
 * seeks, silently; the host is authoritative and a stalled guest catches up;
 * every guest plays the host's exact copy. When the host leaves, the Worker
 * hands the room to the member present longest, and that member's next read
 * says `role: "host"`: this session then gives them the controls.
 *
 * A guest may pause their own sound (Decision 067): the hold stops corrections
 * and never reaches the room; on resume the next correction seeks them to
 * where the host is now, so they catch up rather than the room waiting.
 *
 * Every network call is API.rooms'. `make()` takes its player, clock, and
 * timers, so js/together.test.js runs this file against a stubbed Worker.
 */
const Together = (() => {
  'use strict';

  const STORE_KEY = 'ed.room';
  const TICK_MS = 500;
  const PUBLISH_DEBOUNCE_MS = 150;
  /** A guest's player is stalled while it is seeking or cannot play ahead (HAVE_FUTURE_DATA). */
  const HAVE_FUTURE_DATA = 3;

  function make(deps) {
    const { api, core, player } = deps;
    const now = deps.now || (() => Date.now());
    // Wrapped: the browser's timer functions throw "Illegal invocation" when called as another object's methods.
    const T = deps.timers || { setTimeout: (f, ms) => setTimeout(f, ms), clearTimeout: (t) => clearTimeout(t),
                               setInterval: (f, ms) => setInterval(f, ms), clearInterval: (t) => clearInterval(t) };
    const storage = deps.storage || null;
    /** The card a guest plays for a room's state: the catalog's facts, the host's copy's URL. */
    const cardFor = deps.cardFor || (async (s) => ({ id: s.episode_id, title: null, url: core.urlOfCopy(s) }));
    const audio = player.audio;
    const listeners = new Set();

    let room = null;          // { code, key, role, members, generation, state }
    let notice = null;        // why the last attempt or the room stopped: a Worker code, 'offline', or 'error'
    let busy = false;
    let blocked = false;      // the browser refused to start the guest's audio without a tap
    let held = false;         // the guest paused their own sound; the room plays on
    let lastChangeAt = 0;
    let pollTimer = null;
    let tickTimer = null;
    let publishTimer = null;
    let ownLoad = false;
    let loadingEpisode = null;

    function emit() { listeners.forEach((fn) => { try { fn(); } catch (e) { console.error(e); } }); }
    function save() {
      if (!storage) return;
      try {
        if (room) storage.setItem(STORE_KEY, JSON.stringify({ code: room.code, key: room.key }));
        else storage.removeItem(STORE_KEY);
      } catch { /* storage unavailable: a reload leaves the room to presence */ }
    }

    const isHost = () => !!room && room.role === 'host';
    const isGuest = () => !!room && room.role === 'guest';
    function serverNow() {
      const off = core.clockOffset(api.samples());
      return now() + (off === null ? 0 : off);
    }

    /* ---- Reading the room ---- */

    function schedulePoll() {
      T.clearTimeout(pollTimer);
      if (!room) return;
      pollTimer = T.setTimeout(poll, core.pollInterval(lastChangeAt, now()));
    }

    async function poll() {
      if (!room) return;
      const r = room;
      try {
        const snap = await api.read(r.code, r.key);
        if (room === r) apply(snap);
      } catch (e) {
        if (room !== r) return;
        if (['room_ended', 'no_such_room', 'not_a_member'].includes(e.kind)) { stop(e.kind === 'not_a_member' ? 'not_a_member' : 'room_ended'); return; }
        // Offline or a refusal to read now: keep the room, and read again on the cadence.
      }
      schedulePoll();
    }

    /** One answer from the Worker: the room message (docs/WORKER.md). */
    function apply(snap) {
      const was = room;
      const changed = !was.generation || snap.generation !== was.generation || snap.members !== was.members;
      if (changed) lastChangeAt = now();
      const episodeChanged = !was.state || was.state.episode_id !== snap.state.episode_id
        || was.state.archive_id !== snap.state.archive_id || was.state.file !== snap.state.file;
      const handoff = was.role === 'guest' && snap.role === 'host';
      room = { ...was, role: snap.role, members: snap.members, generation: snap.generation, state: snap.state };
      if (handoff) becomeHost();
      else if (snap.role === 'guest') {
        if (!player.following) player.setFollowing(true);
        if (episodeChanged) followEpisode();
        tick();
      } else hostCheck();
      emit();
    }

    /* ---- The guest: follow the host's state ---- */

    function onRoomEpisode() {
      const c = player.current;
      return !!c && !!room && c.id === room.state.episode_id && c.url === core.urlOfCopy(room.state);
    }

    async function followEpisode() {
      const s = room.state;
      const url = core.urlOfCopy(s);
      if (!url || onRoomEpisode() || loadingEpisode === url) return;
      loadingEpisode = url;
      let card;
      try { card = await cardFor(s); } catch { card = null; }
      loadingEpisode = null;
      if (!room || !isGuest() || core.urlOfCopy(room.state) !== url) return;
      card = { ...(card || { id: s.episode_id }), id: s.episode_id, url };
      ownLoad = true;
      try {
        player.load(card, { autoplay: false, at: core.expectedPosition(room.state, serverNow()) });
      } finally { ownLoad = false; }
      tick();
    }

    /** Applies the protocol's correction to the player. Nobody is asked to do anything. */
    function tick() {
      if (!isGuest() || !onRoomEpisode() || held) return;
      const s = room.state;
      if (!audio.paused && (audio.seeking || audio.readyState < HAVE_FUTURE_DATA)) return;
      const d = isFinite(audio.duration) ? audio.duration : Infinity;
      const c = core.correction(s, serverNow(), { position: audio.currentTime, playing: !audio.paused });
      // Past the end of this copy there is nothing to follow; the host's next state says what plays.
      if (c.position !== undefined && c.position >= d - 0.25 && c.action !== 'pause') return;
      if (c.action === 'pause') {
        player.follow.pause();
        if (Math.abs(audio.currentTime - c.position) > core.DRIFT.ignoreBelow) player.follow.seek(c.position);
      } else if (c.action === 'seek') {
        player.follow.seek(c.position);
        if (c.play) { player.follow.rate(s.rate); startPlay(); }
      } else if (c.action === 'play') {
        if (blocked) return;
        player.follow.seek(c.position);
        player.follow.rate(c.rate);
        startPlay();
      } else if (c.action === 'rate') {
        player.follow.rate(c.rate);
      }
    }

    function startPlay() {
      if (blocked || !audio.paused) return;
      const p = player.follow.play();
      if (p && p.catch) p.catch(() => {});
    }

    function startTicking() {
      T.clearInterval(tickTimer);
      tickTimer = T.setInterval(tick, TICK_MS);
    }

    /* ---- The host: publish state when it changes ---- */

    function body() {
      const b = { position: Math.max(0, audio.currentTime || 0), playing: !audio.paused,
                  rate: nearest(audio.playbackRate) };
      const c = player.current;
      if (c && (!room.state || c.id !== room.state.episode_id || c.url !== core.urlOfCopy(room.state))) {
        const copy = core.copyOfUrl(c.url);
        if (copy) Object.assign(b, { episode_id: c.id }, copy);
      }
      return b;
    }
    function nearest(r) {
      const n = Number(r) || 1;
      return core.SPEEDS.reduce((best, x) => (Math.abs(x - n) < Math.abs(best - n) ? x : best), 1);
    }

    function schedulePublish() {
      if (!isHost() || !player.current) return;
      T.clearTimeout(publishTimer);
      publishTimer = T.setTimeout(publish, PUBLISH_DEBOUNCE_MS);
    }

    async function publish() {
      if (!room) return;
      const r = room;
      try {
        const snap = await api.setState(r.code, r.key, body());
        if (room === r) apply(snap);
      } catch (e) {
        if (room !== r) return;
        if (['room_ended', 'no_such_room', 'not_a_member'].includes(e.kind)) stop('room_ended');
        else if (e.kind === 'host_only') poll();
      }
    }

    /** The host is authoritative: when its own player has drifted from what the room says (a stall), it says so again. */
    function hostCheck() {
      if (!isHost() || !player.current || audio.seeking) return;
      const c = player.current;
      if (c.id !== room.state.episode_id) { schedulePublish(); return; }
      const off = Math.abs(audio.currentTime - core.expectedPosition(room.state, serverNow()));
      if (off > core.DRIFT.seekAbove || room.state.playing === audio.paused) schedulePublish();
    }

    function becomeHost() {
      T.clearInterval(tickTimer);
      blocked = false;
      if (held) {
        // A guest who held their sound is handed a room that played on: they take it from
        // where the room is, never from where they paused.
        held = false;
        player.follow.seek(core.expectedPosition(room.state, serverNow()));
        if (room.state.playing) startPlay();
      }
      player.setFollowing(false);
      player.follow.rate(room.state.rate);
      schedulePublish();
    }

    ['play', 'pause', 'seeked', 'ratechange'].forEach((t) => audio.addEventListener(t, schedulePublish));

    /** The guest's own pause and resume, from the player's verbs (keys, Media Session, the button). */
    function setHold(on) {
      if (!isGuest()) return;
      if (on) {
        held = true;
        player.follow.pause();
      } else {
        held = false;
        blocked = false;
        tick();
      }
      emit();
    }
    if (player.setGuestHold) player.setGuestHold(setHold);
    player.onChange((kind) => {
      if (!room) return;
      if (kind === 'blocked' && isGuest()) { blocked = true; emit(); return; }
      if (kind === 'load' && isHost()) { schedulePublish(); return; }
      // A guest who picks another episode, or whose sleep timer ends, has left the room (as Radio's
      // listening live ends, §4.9): the room goes on without them.
      if (isGuest() && ((kind === 'load' && !ownLoad) || kind === 'sleep-fired')) leave();
    });

    /* ---- Entering and leaving ---- */

    function enter(snap, key) {
      room = { code: snap.code, key, role: snap.role, members: snap.members, generation: null, state: null };
      notice = null;
      blocked = false;
      held = false;
      apply(snap);
      save();
      if (isGuest()) startTicking();
      schedulePoll();
      emit();
    }

    function stop(why) {
      const wasGuest = isGuest();
      T.clearTimeout(pollTimer); T.clearInterval(tickTimer); T.clearTimeout(publishTimer);
      room = null;
      blocked = false;
      held = false;
      notice = why || null;
      if (wasGuest) player.setFollowing(false);
      save();
      emit();
    }

    async function guarded(fn) {
      if (busy) return;
      busy = true; emit();
      try { await fn(); } catch (e) {
        // A placeholder Worker URL is "not available", drawn from info(), never an error.
        notice = !e || !e.kind ? 'error' : e.kind === 'not_configured' ? null : e.kind;
        if (notice === 'error') console.error('listen together', e);
      } finally { busy = false; emit(); }
    }

    /** Start a room from the episode playing, carrying the host's exact copy. */
    function start() {
      return guarded(async () => {
        const c = player.current;
        const copy = c && core.copyOfUrl(c.url);
        if (!copy || room) return;
        notice = null;
        api.resetClock();
        const snap = await api.create({ episode_id: c.id, ...copy, position: Math.max(0, audio.currentTime || 0),
                                        playing: !audio.paused, rate: nearest(audio.playbackRate) });
        enter(snap, snap.member_key);
      });
    }

    /** Join by a code typed or carried by a link. A code that cannot be one is refused before any call. */
    function join(typed) {
      const code = core.normalizeCode(typed);
      if (!code) { notice = 'bad_code'; emit(); return Promise.resolve(); }
      return guarded(async () => {
        if (room && room.code === code) return;
        if (room) await leaveNow();
        notice = null;
        api.resetClock();
        const snap = await api.join(code);
        enter(snap, snap.member_key);
      });
    }

    async function leaveNow() {
      const r = room;
      if (!r) return;
      stop(null);
      try { await api.leave(r.code, r.key); } catch { /* gone quiet, the Worker drops this member in 2 minutes */ }
    }
    function leave() { return guarded(leaveNow); }

    /** The host ends the room for everyone. */
    function end() {
      return guarded(async () => {
        if (!isHost()) return;
        const r = room;
        await api.end(r.code, r.key);
        stop(null);
      });
    }

    /** The guest's one tap when the browser would not start audio on its own. */
    function tap() {
      if (!isGuest()) return;
      blocked = false;
      emit();
      tick();
    }

    /** A reload keeps the room: the key lives in this tab's session storage only. */
    async function restore() {
      if (!storage || room || !api.available()) return;
      let saved = null;
      try { saved = JSON.parse(storage.getItem(STORE_KEY)); } catch { saved = null; }
      if (!saved || !saved.code || !saved.key) return;
      try {
        const snap = await api.read(saved.code, saved.key);
        enter(snap, saved.key);
      } catch (e) {
        if (['room_ended', 'no_such_room', 'not_a_member'].includes(e.kind)) {
          try { storage.removeItem(STORE_KEY); } catch { /* nothing kept */ }
        }
      }
    }

    function info() {
      return {
        available: api.available(), busy, notice, blocked, held,
        inRoom: !!room, code: room ? room.code : null, role: room ? room.role : null,
        members: room ? room.members : 0, state: room ? room.state : null,
        canStart: !room && !!(player.current && core.copyOfUrl(player.current.url)),
      };
    }

    return {
      start, join, leave, end, tap, restore, info, hold: setHold,
      clearNotice() { notice = null; emit(); },
      onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
      _test: { tick, poll, publish },
    };
  }

  return { make };
})();
