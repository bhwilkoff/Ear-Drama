/**
 * Listen Together's client rules (WEB-DESIGN §4.12, LOOP-PLAN M6): a PORT of
 * worker/src/room-protocol.js's client-side parts, not a re-derivation. The
 * code rules, where the host is now, the clock, drift correction, and the poll
 * cadence are the protocol's own; js/together.test.js golden-checks each one
 * against that file on shared cases, so the two cannot drift apart.
 *
 * Pure: no network, no clock, no DOM. Every function takes its inputs.
 */
const TogetherCore = (() => {
  'use strict';

  const PROTOCOL_VERSION = 1;
  const CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  const CODE_LENGTH = 6;
  const SPEEDS = [0.75, 1, 1.25, 1.5, 2];
  const MAX_POSITION_S = 7 * 86400;
  const DRIFT = Object.freeze({
    ignoreBelow: 0.15,
    seekAbove: 2,
    nudge: 0.03,
    pollFastMs: 2000,
    pollSlowMs: 10000,
    slowAfterStillMs: 60000,
  });

  /** Spaces, - and _ dropped; I and L read as 1, O as 0; anything else outside the alphabet refused. */
  function normalizeCode(typed) {
    if (typeof typed !== 'string') return null;
    let out = '';
    for (const ch of typed.toUpperCase()) {
      if (ch === ' ' || ch === '-' || ch === '_') continue;
      if (ch === 'I' || ch === 'L') { out += '1'; continue; }
      if (ch === 'O') { out += '0'; continue; }
      if (!CODE_ALPHABET.includes(ch)) return null;
      out += ch;
    }
    return out.length === CODE_LENGTH ? out : null;
  }

  const ARCHIVE_ID = /^[A-Za-z0-9._-]{1,100}$/;
  /** The host's copy: an archive.org identifier and a file inside it, never a URL (protocol cleanCopy). */
  function cleanCopy(archiveId, file) {
    if (typeof archiveId !== 'string' || !ARCHIVE_ID.test(archiveId)) return null;
    if (typeof file !== 'string' || file.length < 1 || file.length > 400) return null;
    if (file.startsWith('/') || file.includes('\\') || /[\u0000-\u001f\u007f]/.test(file)) return null;
    if (file.split('/').some((part) => part === '..' || part === '.' || part === '')) return null;
    return { archive_id: archiveId, file };
  }

  const DOWNLOAD = 'https://archive.org/download/';
  /** The pipeline's percent-encoding (Python's quote): everything but letters, digits, and _ . - ~. */
  function enc(s) {
    return encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
  }
  /** The copy a played URL names, or null when it is not an archive.org download. */
  function copyOfUrl(url) {
    if (typeof url !== 'string' || !url.startsWith(DOWNLOAD)) return null;
    const rest = url.slice(DOWNLOAD.length).split(/[?#]/)[0];
    const cut = rest.indexOf('/');
    if (cut < 1) return null;
    try {
      const id = decodeURIComponent(rest.slice(0, cut));
      const file = rest.slice(cut + 1).split('/').map(decodeURIComponent).join('/');
      return cleanCopy(id, file);
    } catch { return null; }
  }
  /** Every guest builds the host's URL itself, so a room can never point a player at another host. */
  function urlOfCopy(copy) {
    const c = copy && cleanCopy(copy.archive_id, copy.file);
    return c ? DOWNLOAD + enc(c.archive_id) + '/' + c.file.split('/').map(enc).join('/') : null;
  }

  /** Where the host's player is at server time `now`, extrapolated from the last state. */
  function expectedPosition(state, now) {
    if (!state.playing) return state.position;
    return Math.min(MAX_POSITION_S, state.position + ((now - state.updated_at) / 1000) * state.rate);
  }

  /** Cristian's algorithm: the sample with the smallest round trip wins, never an average. */
  function clockOffset(samples) {
    let best = null;
    for (const s of samples) {
      const rtt = s.t1 - s.t0;
      if (!(rtt >= 0)) continue;
      if (!best || rtt < best.rtt) best = { rtt, offset: s.server_time - (s.t0 + s.t1) / 2 };
    }
    return best ? best.offset : null;
  }

  /**
   * Drift correction as a value the player applies, silently: play/pause follows at once;
   * under 150 ms nothing (the host's rate); 150 ms to 2 s the host's rate x 0.97 or 1.03;
   * over 2 s a seek. A stalled guest catches up; the room never waits.
   */
  function correction(state, serverNow, player) {
    const target = expectedPosition(state, serverNow);
    if (!state.playing) {
      if (player.playing) return { action: 'pause', position: target };
      return Math.abs(player.position - target) > DRIFT.ignoreBelow ? { action: 'seek', position: target } : { action: 'none' };
    }
    const off = player.position - target;
    const far = Math.abs(off);
    if (far > DRIFT.seekAbove) return { action: 'seek', position: target, play: true };
    if (!player.playing) return { action: 'play', position: target, rate: state.rate };
    if (far < DRIFT.ignoreBelow) return { action: 'rate', rate: state.rate };
    return { action: 'rate', rate: state.rate * (off > 0 ? 1 - DRIFT.nudge : 1 + DRIFT.nudge) };
  }

  /** How long a member waits before its next read: fast while things change, slow when still. */
  function pollInterval(lastChangeAt, now) {
    return now - lastChangeAt > DRIFT.slowAfterStillMs ? DRIFT.pollSlowMs : DRIFT.pollFastMs;
  }

  return {
    PROTOCOL_VERSION, CODE_ALPHABET, CODE_LENGTH, SPEEDS, DRIFT,
    normalizeCode, cleanCopy, copyOfUrl, urlOfCopy, expectedPosition, clockOffset, correction, pollInterval,
  };
})();
