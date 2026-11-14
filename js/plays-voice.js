/**
 * The device voice: a scene partner, never a performer (PLAYS-DESIGN §5).
 *
 * speechSynthesis speaks through the system's own output, and a page is never
 * handed that sound, so there is nothing here to record, keep, or mix: speak()
 * resolves when the line has been read and returns no audio. Only voices on
 * this device are offered (`localService`, §5 rule 5), so a script line is
 * never sent to a speech server, and never a Personal Voice (C10).
 *
 * Which voice reads a part is the production's one cast (VoiceCast, §2.8): every
 * player made with the same cast reads a part in the same voice, at its speed and pitch.
 *
 * This file holds no audio path at all; js/plays.test.js scans it for one.
 */
const StandInVoice = (() => {
  'use strict';

  const PITCHES = VoiceCast.PITCHES;
  const sys = () => (typeof speechSynthesis !== 'undefined' ? speechSynthesis : null);
  const lang = () => (typeof navigator !== 'undefined' ? navigator.language : 'en-US');

  /** The raw voices, castable ones only, in the old order's shape (kept for callers that want the platform objects). */
  function castableVoices(all, language) {
    return VoiceCast.systemVoices(all, language).map(v => v.raw);
  }

  /** This browser's castable voices now, best first (VoiceCast.systemVoices); [] before they load. */
  function voices(synth = sys(), language = lang()) {
    return synth ? VoiceCast.systemVoices(synth.getVoices(), language) : [];
  }
  /** Calls `fn` when the browser's voice list changes (Chrome fills it late); returns the unsubscribe. */
  function onVoices(fn, synth = sys()) {
    if (!synth || !synth.addEventListener) return () => {};
    synth.addEventListener('voiceschanged', fn);
    return () => synth.removeEventListener('voiceschanged', fn);
  }

  /** The words as spoken: printed italic marks never read. */
  const said = (text) => (text || '').replace(/_/g, '').trim();

  function create({ muted = false, synth = sys(),
                    Utterance = (typeof SpeechSynthesisUtterance !== 'undefined' ? SpeechSynthesisUtterance : null),
                    language = lang(), cast = null } = {}) {
    const assigned = new Map();
    let list = [];
    const refresh = () => { list = synth ? VoiceCast.systemVoices(synth.getVoices(), language) : []; };
    refresh();
    if (synth && synth.addEventListener) synth.addEventListener('voiceschanged', refresh);

    /** With no cast (tests of other parts), a part takes the next voice the first time it speaks. */
    function loose(part) {
      if (!assigned.has(part)) assigned.set(part, assigned.size);
      const index = assigned.get(part);
      return { read: true, voice: list[index % list.length], rate: 1, pitch: PITCHES[Math.floor(index / list.length) % PITCHES.length] };
    }

    function utter(words, v, rate, pitch) {
      const u = new Utterance(words);
      u.voice = v.raw || v;
      u.lang = v.lang;
      u.pitch = pitch;
      u.rate = Math.min(10, Math.max(0.1, rate));
      u.volume = muted ? 0 : 1;
      return new Promise((resolve) => {
        let settled = false;
        const done = (read) => { if (!settled) { settled = true; clearTimeout(guard); resolve(read); } };
        // Some engines never fire `end` on a long utterance; a line is never waited on forever.
        const guard = setTimeout(() => { synth.cancel(); done(true); }, 4000 + (words.length * 120) / u.rate);
        u.onend = () => done(true);
        u.onerror = () => done(false);
        synth.speak(u);
      });
    }

    return {
      available() { refresh(); return !!(synth && Utterance && list.length); },

      /** Whether `part` is read at all (Not read for directions and sound by default, §2.8 rule 7). */
      reads(part) {
        refresh();
        if (!synth || !Utterance || !list.length) return false;
        return cast ? cast.resolve(part).read : true;
      },

      /** Reads one line aloud, live, in the part's cast voice. Resolves true when it was read, false when no local voice can read it. */
      speak(text, part, rate = 1) {
        const words = said(text);
        refresh();
        if (!words || !synth || !Utterance || !list.length) return Promise.resolve(false);
        const r = cast ? cast.resolve(part) : loose(part);
        if (!r.read || !r.voice) return Promise.resolve(false);
        return utter(words, r.voice, r.rate * rate, r.pitch);
      },

      /** The picker's preview: `text` (the part's own first line) in a voice not yet chosen. Live, never kept. */
      speakAs(text, voice, { rate = 1, pitch = 1 } = {}) {
        const words = said(text);
        if (!words || !synth || !Utterance || !voice) return Promise.resolve(false);
        synth.cancel();
        return utter(words, voice, rate, pitch);
      },

      cancel() { if (synth) synth.cancel(); },
    };
  }

  return { create, castableVoices, voices, onVoices, PITCHES };
})();
