/**
 * The player: one <audio> element, the Media Session, resume, speed, skip,
 * the queue, and the sleep timer. The views draw it; this module owns it.
 *
 * Bounded lean-back (R3, R14, R20; Decision 067):
 *  - A part of a story arc (the published `arc`, contract §3.3) is followed by
 *    the arc's next part. At the arc's last part playback stops and the next
 *    story is offered (`nextStory`), never started. Outside an arc, and after
 *    an arc's last part: what the person queued, then stop. Nothing the person
 *    did not choose starts by itself. A live slot (`arc: false`) follows its
 *    clock, never an arc.
 *  - The sleep timer offers "End of this episode" first, fades the volume
 *    over its last FADE_S seconds, and once it has fired nothing starts until
 *    the person presses play.
 * Commercials are part of the broadcast and are never skipped (R8): skip is a
 * fixed 15 s back / 30 s forward, never a jump past a segment.
 * DECISIONS 062: FADE_S, SPEEDS, SAVE_EVERY_MS, and REWIND_S are the numbers
 * every platform's player uses (Android PlayerNumbers, Apple AudioPlayer).
 * Decision 067: volume is leveled on the device as it plays (LEVEL), never by
 * a per-file measurement.
 */
const Player = (() => {
  'use strict';

  const audio = document.getElementById('audio');
  const BACK_S = 15;
  const FWD_S = 30;
  const FADE_S = 10;
  const SPEEDS = [0.75, 1, 1.25, 1.5, 2];
  const SAVE_EVERY_MS = 5000;
  const REWIND_S = 3;
  /** Decision 067: the leveler every platform sets, a compressor over the whole signal. The makeup
      gain is the Web Audio rule, 0.6 x the compression at 0 dBFS (here 10.8 dB), so Apple and
      Android, which set it by hand, match the browser's own. */
  const LEVEL = Object.freeze({ thresholdDb: -24, ratio: 4, kneeDb: 12, attackS: 0.003, releaseS: 0.25,
                                makeupDb: 0.6 * 24 * (1 - 1 / 4) });
  const LEVEL_KEY = 'ed.level';
  const listeners = new Set();

  let current = null;
  let sleep = null;         // null | { kind: 'end' } | { kind: 'time', endsAt, minutes }
  let fired = false;        // the sleep timer has ended playback; nothing may start on its own
  let lastSave = 0;
  let sleepTimer = null;
  let lastError = null;
  let pausing = false;      // the pause in flight is the person's (or the timer's), not an interruption
  let interrupted = false;  // the browser paused us (a call, another tab's audio); resuming rewinds REWIND_S
  let following = false;    // a Listen Together guest: the host drives, so the person's transport verbs do nothing
  let guestHold = null;     // set by js/together.js: a guest's own pause (true) and resume (false)
  let arc = null;           // the current episode's arc ({ part, parts, next, nextStory }), once read
  let arcWait = null;       // the read in flight, or null once settled
  let arcSource = (id) => (typeof API !== 'undefined' && API.arcOf ? API.arcOf(id) : null);

  function emit(kind) { listeners.forEach(fn => fn(kind || 'state')); }
  function onChange(fn) { listeners.add(fn); }

  /**
   * Load an episode card ({ id, title, series, seriesName, date, url, length }) and, by default, play it.
   * `at` starts it at a given second instead of its resume point (the Radio tab's one clock, R10).
   */
  function load(ep, { autoplay = true, at: startAt = null, arc: inArc = true } = {}) {
    current = Store.card(ep);
    readArc(inArc ? ep.id : null);
    fired = false;
    interrupted = false;
    lastError = null;
    if (!audio.paused) pausing = true;
    // The copy is fetched with CORS only when it may be leveled: a copy fetched without it
    // would play silent through the graph (attachLeveler waits for one fetched with it).
    corsReady = !!graph || leveling();
    plainRetry = false;
    if (corsReady) audio.crossOrigin = 'anonymous';
    else if (audio.removeAttribute) audio.removeAttribute('crossorigin');
    audio.src = ep.url;
    setOutput(1);
    audio.defaultPlaybackRate = nearestSpeed(Store.rate());
    const at = startAt !== null ? startAt : Store.resumeAt(ep.id);
    audio.addEventListener('loadedmetadata', () => {
      if (at) audio.currentTime = at;
      audio.playbackRate = nearestSpeed(Store.rate());
    }, { once: true });
    Store.addHistory(current);
    Store.dequeue(ep.id);
    setMetadata();
    if (autoplay) play();
    emit('load');
  }

  function play() {
    fired = false;
    attachLeveler();
    if (interrupted) {
      interrupted = false;
      audio.currentTime = Math.max(0, audio.currentTime - REWIND_S);
    }
    const p = audio.play();
    // NotAllowedError is the browser's autoplay rule, not a broken recording: a tap starts it.
    if (p && p.catch) {
      p.catch(err => {
        if (err.name === 'NotAllowedError') emit('blocked');
        else if (err.name !== 'AbortError') { lastError = err; emit('error'); }
      });
    }
    return p;
  }
  function pause() {
    if (audio.paused) return;
    pausing = true;
    audio.pause();
  }
  function toggle() { if (!current) return; if (audio.paused) play(); else pause(); }

  function seek(t) {
    if (!current || !isFinite(t)) return;
    const d = isFinite(audio.duration) ? audio.duration : Infinity;
    audio.currentTime = Math.max(0, Math.min(d, t));
    savePosition();
  }
  function skip(delta) { seek(audio.currentTime + delta); }
  function back() { skip(-BACK_S); }
  function forward() { skip(FWD_S); }

  /** The offered speed closest to [r]: a rate kept from an older build still lands on a choice. */
  function nearestSpeed(r) {
    const n = Number(r) || 1;
    return SPEEDS.reduce((best, s) => (Math.abs(s - n) < Math.abs(best - n) ? s : best), 1);
  }

  function setRate(r) {
    const rate = nearestSpeed(r);
    audio.playbackRate = rate;
    audio.defaultPlaybackRate = rate;
    Store.setRate(rate);
    emit('rate');
  }

  function savePosition() {
    if (!current || !isFinite(audio.duration)) return;
    Store.savePosition(current.id, audio.currentTime, audio.duration);
    lastSave = Date.now();
  }

  /** The next episode the queue may start: its head, whatever its series (Decision 067). */
  function nextInQueue() {
    if (!current) return null;
    return Store.queue()[0] || null;
  }

  /** Decision 067: the arc's next part, else (outside an arc, or after its last part) the queue's head. */
  function upNext() {
    if (arc && arc.next) return { kind: 'part', card: arc.next };
    const q = nextInQueue();
    return q ? { kind: 'queue', card: q } : null;
  }

  /** On an arc's last part: the series' next story, offered for the person to start, never started. */
  function nextStory() { return arc && !arc.next ? arc.nextStory || null : null; }

  function readArc(id) {
    arc = null;
    arcWait = null;
    if (!id) return;
    let got;
    try { got = arcSource(id); } catch { got = null; }
    if (!got || typeof got.then !== 'function') { arc = got || null; return; }
    const wait = got.then(a => a, () => null).then(a => {
      if (arcWait !== wait) return;
      arc = a || null;
      arcWait = null;
      emit('arc');
    });
    arcWait = wait;
  }

  function advance() {
    const n = upNext();
    if (n) load(n.card);
    else emit('ended');
  }

  /* ---- Sleep timer (R20) ---- */

  function setSleep(choice) {
    restoreVolume();
    if (choice === 'off' || !choice) {
      sleep = null;
    } else if (choice === 'end') {
      sleep = { kind: 'end' };
    } else {
      const minutes = Number(choice);
      sleep = { kind: 'time', minutes, endsAt: Date.now() + minutes * 60000 };
    }
    clearInterval(sleepTimer);
    if (sleep) sleepTimer = setInterval(sleepTick, 250);
    emit('sleep');
  }

  /** Seconds of listening left before the timer fires, or null when there is no timer or no length yet. */
  function sleepRemaining() {
    if (!sleep) return null;
    if (sleep.kind === 'time') return Math.max(0, (sleep.endsAt - Date.now()) / 1000);
    if (!isFinite(audio.duration)) return null;
    return Math.max(0, (audio.duration - audio.currentTime) / (audio.playbackRate || 1));
  }

  function sleepTick() {
    if (!sleep) return;
    const left = sleepRemaining();
    if (left !== null && left <= FADE_S) setOutput(Math.max(0, Math.min(1, left / FADE_S)));
    if (sleep.kind === 'time' && left <= 0) fireSleep();
    emit('tick');
  }

  function fireSleep() {
    pause();
    savePosition();
    fired = true;
    sleep = null;
    clearInterval(sleepTimer);
    restoreVolume();
    emit('sleep-fired');
  }

  function restoreVolume() { setOutput(1); }

  /* ---- Volume leveling (Decision 067, WEB-DESIGN §5.9) ----
     The element plays through a DynamicsCompressorNode. archive.org sends
     access-control-allow-origin: * (research 04 §5), so the element asks with crossorigin;
     without it Web Audio would hear silence. The graph is built only once the AudioContext
     runs (a tap or key started it), so a play the browser starts on its own is never routed
     into a suspended context. Not on iPhone or iPad, where a page's AudioContext stops when
     the screen locks, nor on a TV engine (tv.js), where it is unmeasured. */

  const AC = typeof AudioContext !== 'undefined' ? AudioContext
    : (typeof webkitAudioContext !== 'undefined' ? webkitAudioContext : null); // eslint-disable-line no-undef
  const appleTouch = typeof navigator !== 'undefined' && (/iPad|iPhone|iPod/.test(navigator.userAgent || '')
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1));
  let ctx = null;
  let graph = null;           // { source, comp, out }
  let fade = 1;               // the sleep timer's fade, 0..1
  let corsReady = false;      // the loaded copy was fetched with CORS, so the graph can hear it
  let plainRetry = false;     // a copy refused with CORS was loaded again without it

  function canLevel() {
    const tv = typeof document !== 'undefined' && document.documentElement
      && document.documentElement.classList.contains('tv');
    return !!AC && !appleTouch && !tv;
  }
  function levelOn() {
    try { return localStorage.getItem(LEVEL_KEY) !== 'off'; } catch { return true; }
  }
  function leveling() { return canLevel() && levelOn(); }

  /** Called from a tap or key: the AudioContext may only start inside one. */
  function wake() {
    if (!leveling()) return;
    try {
      if (!ctx) ctx = new AC();
      if (ctx.state === 'suspended') ctx.resume().then(() => { if (!audio.paused) attachLeveler(); }, () => {});
    } catch { ctx = null; }
  }

  function attachLeveler() {
    if (graph || !corsReady || !leveling() || !ctx || ctx.state !== 'running') return;
    try {
      const source = ctx.createMediaElementSource(audio);
      const comp = ctx.createDynamicsCompressor();
      comp.threshold.value = LEVEL.thresholdDb;
      comp.knee.value = LEVEL.kneeDb;
      comp.ratio.value = LEVEL.ratio;
      comp.attack.value = LEVEL.attackS;
      comp.release.value = LEVEL.releaseS;
      const out = ctx.createGain();
      source.connect(comp).connect(out).connect(ctx.destination);
      graph = { source, comp, out };
      audio.volume = 1;
      setOutput(fade);
    } catch (e) { console.error('leveling', e); }
  }

  /** The person turned leveling off or on. Once the element is routed it stays routed, so off
      bypasses the compressor rather than leaving the graph. */
  function setLeveling(on) {
    try { localStorage.setItem(LEVEL_KEY, on ? 'on' : 'off'); } catch { /* kept for this page only */ }
    if (graph) {
      graph.source.disconnect();
      graph.source.connect(on ? graph.comp : graph.out);
    } else if (on) {
      wake();   // the next episode loads with CORS and plays leveled
    }
    emit('level');
  }

  /** The sleep fade and the mute door, on the graph's output when there is one. */
  function setOutput(f) {
    fade = f;
    if (graph) {
      graph.out.gain.value = audio.muted ? 0 : f;
      audio.volume = 1;
    } else {
      audio.volume = f;
    }
  }

  if (typeof document !== 'undefined' && document.addEventListener) {
    ['pointerdown', 'keydown', 'touchend'].forEach(t => document.addEventListener(t, wake, { capture: true, passive: true }));
  }

  /* ---- Element events ---- */

  audio.addEventListener('timeupdate', () => {
    if (Date.now() - lastSave > SAVE_EVERY_MS) savePosition();
    updatePositionState();
    emit('time');
  });
  audio.addEventListener('pause', () => {
    if (!pausing && !audio.ended) interrupted = true;
    pausing = false;
    savePosition();
    emit('pause');
  });
  audio.addEventListener('play', () => emit('play'));
  audio.addEventListener('durationchange', () => emit('time'));
  audio.addEventListener('error', () => {
    // A storage node that did not answer with CORS refuses the crossorigin fetch: before the
    // element is routed, play that copy unleveled rather than not at all.
    if (current && corsReady && !graph && !plainRetry) {
      plainRetry = true;
      corsReady = false;
      if (audio.removeAttribute) audio.removeAttribute('crossorigin');
      audio.src = current.url;
      play();
      emit('level');
      return;
    }
    lastError = audio.error;
    emit('error');
  });
  audio.addEventListener('ended', () => {
    if (current && isFinite(audio.duration)) Store.savePosition(current.id, audio.duration, audio.duration);
    if (sleep && sleep.kind === 'end') { fireSleep(); return; }
    if (fired) return;
    if (!arcWait) { advance(); return; }
    const id = current && current.id;
    arcWait.then(() => { if (!fired && current && current.id === id && audio.ended) advance(); });
  });
  window.addEventListener('pagehide', savePosition);

  /* ---- Media Session: lock screen, headphones, media keys ---- */

  const ms = typeof navigator !== 'undefined' && 'mediaSession' in navigator ? navigator.mediaSession : null;

  let artwork = [];
  function setMetadata() {
    if (!ms || !current || typeof MediaMetadata === 'undefined') return;
    ms.metadata = new MediaMetadata({
      title: current.title || '', artist: current.seriesName || '', album: current.date || '', artwork,
    });
  }
  /** The lock screen's picture (§5.6), the same art Now Playing draws; null clears it. */
  function setArtwork(list) {
    artwork = Array.isArray(list) ? list : [];
    setMetadata();
  }

  function updatePositionState() {
    if (!ms || !ms.setPositionState || !isFinite(audio.duration) || audio.duration <= 0) return;
    try {
      ms.setPositionState({ duration: audio.duration, playbackRate: audio.playbackRate || 1,
                            position: Math.min(audio.currentTime, audio.duration) });
    } catch { /* an engine without position state */ }
  }

  /* ---- Listen Together (WEB-DESIGN §4.12): a guest's player follows the host ---- */

  /** The person's verbs, refused while following; the room's own corrections go through `follow`.
      A guest's play and pause are their own (Decision 067): they hold their sound and, on
      resume, the room's next correction catches them up (js/together.js). */
  const person = (fn) => (...args) => (following ? undefined : fn(...args));
  const hold = (want) => () => {
    if (!following) return want === 'toggle' ? toggle() : want ? pause() : play();
    if (guestHold) guestHold(want === 'toggle' ? !audio.paused : want);
    return undefined;
  };
  const personPlay = hold(false), personPause = hold(true), personToggle = hold('toggle');
  function setGuestHold(fn) { guestHold = fn; }
  function setFollowing(on) {
    following = !!on;
    if (!following) audio.playbackRate = nearestSpeed(Store.rate());
    emit('following');
  }
  /** Applied by js/together.js only. A drift nudge sets the element's rate and is never kept as the person's speed. */
  const follow = {
    play, pause,
    seek(t) { if (current && isFinite(t)) { audio.currentTime = Math.max(0, t); savePosition(); } },
    rate(r) { if (Math.abs(audio.playbackRate - r) > 1e-9) audio.playbackRate = r; },
  };

  if (ms) {
    const handlers = {
      play: () => personPlay(),
      pause: () => personPause(),
      stop: () => personPause(),
      seekbackward: d => skip(-((d && d.seekOffset) || BACK_S)),
      seekforward: d => skip((d && d.seekOffset) || FWD_S),
      seekto: d => seek(d.seekTime),
      previoustrack: () => seek(0),
      nexttrack: () => { const n = upNext(); if (n) load(n.card); },
    };
    for (const [action, fn] of Object.entries(handlers)) {
      const guarded = ['play', 'pause', 'stop'].includes(action) ? fn : person(fn);
      try { ms.setActionHandler(action, guarded); } catch { /* unsupported action */ }
    }
  }

  function setMuted(m) { audio.muted = !!m; setOutput(fade); }

  return {
    audio, load, setSleep, setMuted, nextInQueue, upNext, nextStory, sleepRemaining, onChange, setArtwork,
    setArcSource(fn) { arcSource = fn; },
    play: personPlay, pause: personPause, toggle: personToggle, seek: person(seek),
    back: person(back), forward: person(forward), setRate: person(setRate),
    setFollowing, follow, setGuestHold, setLeveling, wake,
    get leveling() { return leveling(); },
    get canLevel() { return canLevel(); },
    get leveled() { return !!graph && levelOn(); },
    get following() { return following; },
    get current() { return current; },
    get sleep() { return sleep; },
    get fired() { return fired; },
    get error() { return lastError; },
    BACK_S, FWD_S, FADE_S, SPEEDS, SAVE_EVERY_MS, REWIND_S, LEVEL, nearestSpeed,
  };
})();
