/**
 * The player: one <audio> element, the Media Session, resume, speed, skip,
 * the queue, and the sleep timer. The views draw it; this module owns it.
 *
 * Bounded lean-back (R3, R14, R20):
 *  - At an episode's end the next one plays only when the person queued it
 *    AND it is from the same series. Nothing unrelated ever starts by itself.
 *  - The sleep timer offers "End of this episode" first, fades the volume
 *    over its last FADE_S seconds, and once it has fired nothing starts until
 *    the person presses play.
 * Commercials are part of the broadcast and are never skipped (R8): skip is a
 * fixed 15 s back / 30 s forward, never a jump past a segment.
 * DECISIONS 062: FADE_S, SPEEDS, SAVE_EVERY_MS, and REWIND_S are the numbers
 * every platform's player uses (Android PlayerNumbers, Apple AudioPlayer).
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
  const listeners = new Set();

  let current = null;
  let sleep = null;         // null | { kind: 'end' } | { kind: 'time', endsAt, minutes }
  let fired = false;        // the sleep timer has ended playback; nothing may start on its own
  let baseVolume = 1;       // the episode's loudness level (DECISIONS 061); the device's volume stays the person's
  let lastSave = 0;
  let sleepTimer = null;
  let lastError = null;
  let pausing = false;      // the pause in flight is the person's (or the timer's), not an interruption
  let interrupted = false;  // the browser paused us (a call, another tab's audio); resuming rewinds REWIND_S
  let following = false;    // a Listen Together guest: the host drives, so the person's transport verbs do nothing

  function emit(kind) { listeners.forEach(fn => fn(kind || 'state')); }
  function onChange(fn) { listeners.add(fn); }

  /**
   * Load an episode card ({ id, title, series, seriesName, date, url, length }) and, by default, play it.
   * `at` starts it at a given second instead of its resume point (the Radio tab's one clock, R10).
   */
  function load(ep, { autoplay = true, at: startAt = null } = {}) {
    current = Store.card(ep);
    fired = false;
    interrupted = false;
    lastError = null;
    if (!audio.paused) pausing = true;
    audio.src = ep.url;
    baseVolume = API.playbackVolume(current.li, current.ltp);
    audio.volume = baseVolume;
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

  /** The next episode the queue may start: its head, and only if it is from this series. */
  function nextInQueue() {
    if (!current) return null;
    const head = Store.queue()[0];
    return head && head.series && head.series === current.series ? head : null;
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
    if (left !== null && left <= FADE_S) {
      audio.volume = Math.max(0, Math.min(1, baseVolume * (left / FADE_S)));
    }
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

  function restoreVolume() { audio.volume = baseVolume; }

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
  audio.addEventListener('error', () => { lastError = audio.error; emit('error'); });
  audio.addEventListener('ended', () => {
    if (current && isFinite(audio.duration)) Store.savePosition(current.id, audio.duration, audio.duration);
    if (sleep && sleep.kind === 'end') { fireSleep(); return; }
    if (fired) return;
    const next = nextInQueue();
    if (next) load(next);
    else emit('ended');
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

  /** The person's verbs, refused while following; the room's own corrections go through `follow`. */
  const person = (fn) => (...args) => (following ? undefined : fn(...args));
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
      play: () => play(),
      pause: () => pause(),
      stop: () => pause(),
      seekbackward: d => skip(-((d && d.seekOffset) || BACK_S)),
      seekforward: d => skip((d && d.seekOffset) || FWD_S),
      seekto: d => seek(d.seekTime),
      previoustrack: () => seek(0),
      nexttrack: () => { const n = nextInQueue(); if (n) load(n); },
    };
    for (const [action, fn] of Object.entries(handlers)) {
      try { ms.setActionHandler(action, person(fn)); } catch { /* unsupported action */ }
    }
  }

  function setMuted(m) { audio.muted = !!m; }

  return {
    audio, load, setSleep, setMuted, nextInQueue, sleepRemaining, onChange, setArtwork,
    play: person(play), pause: person(pause), toggle: person(toggle), seek: person(seek),
    back: person(back), forward: person(forward), setRate: person(setRate),
    setFollowing, follow,
    get following() { return following; },
    get current() { return current; },
    get sleep() { return sleep; },
    get fired() { return fired; },
    get error() { return lastError; },
    BACK_S, FWD_S, FADE_S, SPEEDS, SAVE_EVERY_MS, REWIND_S, nearestSpeed,
  };
})();
