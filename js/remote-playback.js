/**
 * Another speaker or screen (owner, 2026-10-28): the browser's own picker for
 * the one <audio> element (WEB-DESIGN §5.10). Safari offers AirPlay
 * (webkitShowPlaybackTargetPicker); Chrome and Edge offer Cast through the
 * Remote Playback API (audio.remote). The receiver fetches the element's own
 * src, the archive.org copy. The button shows only while the browser says a
 * target is there, and never on a TV, which is the speaker.
 *   node js/remote-playback.test.js
 */
const RemoteOutput = (() => {
  const LABELS = { airplay: 'AirPlay', cast: 'Cast' };

  /** Which picker this browser has for [audio]: 'airplay', 'cast', or null. */
  function kindOf(audio, win) {
    if (!audio) return null;
    if (typeof audio.webkitShowPlaybackTargetPicker === 'function' &&
        win && 'WebKitPlaybackTargetAvailabilityEvent' in win) return 'airplay';
    if (audio.remote && typeof audio.remote.watchAvailability === 'function' &&
        typeof audio.remote.prompt === 'function') return 'cast';
    return null;
  }

  /**
   * Calls onChange(kind) while a target is available and onChange(null) while
   * none is. A browser that cannot watch continuously (NotSupportedError, as
   * the spec allows) still has a picker, so the button shows and the picker
   * itself says what it finds.
   */
  function watch(audio, win, onChange) {
    const kind = kindOf(audio, win);
    onChange(null);
    if (!kind) return;
    if (kind === 'airplay') {
      audio.addEventListener('webkitplaybacktargetavailabilitychanged', (e) => {
        onChange(e.availability === 'available' ? kind : null);
      });
      return;
    }
    Promise.resolve()
      .then(() => audio.remote.watchAvailability((available) => onChange(available ? kind : null)))
      .catch((err) => onChange(err && err.name === 'NotSupportedError' ? kind : null));
  }

  /** Opens the browser's own device picker. */
  function prompt(audio, win) {
    const kind = kindOf(audio, win);
    if (kind === 'airplay') { audio.webkitShowPlaybackTargetPicker(); return Promise.resolve(); }
    if (kind === 'cast') return audio.remote.prompt().catch(() => {});
    return Promise.resolve();
  }

  return { LABELS, kindOf, watch, prompt };
})();

if (typeof module !== 'undefined') module.exports = RemoteOutput;
