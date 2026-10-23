/**
 * The device voice: a scene partner, never a performer (PLAYS-DESIGN §5).
 *
 * speechSynthesis speaks through the system's own output, and a page is never
 * handed that sound, so there is nothing here to record, keep, or mix: speak()
 * resolves when the line has been read and returns no audio. Only voices on
 * this device are offered (`localService`, §5 rule 5), so a script line is
 * never sent to a speech server, and never a Personal Voice (C10).
 *
 * This file holds no audio path at all; js/plays.test.js scans it for one.
 */
const StandInVoice = (() => {
  'use strict';

  /** Voices repeat on a device with few of them; pitch tells two parts on one voice apart. */
  const PITCHES = [1.0, 0.86, 1.14, 0.93, 1.07];

  function castableVoices(all, language) {
    const lang = (language || 'en-US').toLowerCase();
    return all.filter(v => v.localService && /^en([-_]|$)/i.test(v.lang))
      .sort((a, b) => {
        const al = a.lang.toLowerCase() === lang, bl = b.lang.toLowerCase() === lang;
        if (al !== bl) return al ? -1 : 1;
        if (a.default !== b.default) return a.default ? -1 : 1;
        return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
      });
  }

  function create({ muted = false, synth = (typeof speechSynthesis !== 'undefined' ? speechSynthesis : null),
                    Utterance = (typeof SpeechSynthesisUtterance !== 'undefined' ? SpeechSynthesisUtterance : null),
                    language = (typeof navigator !== 'undefined' ? navigator.language : 'en-US') } = {}) {
    const assigned = new Map();
    let voices = [];
    const refresh = () => { voices = synth ? castableVoices(synth.getVoices(), language) : []; };
    refresh();
    if (synth && synth.addEventListener) synth.addEventListener('voiceschanged', refresh);

    return {
      available() { refresh(); return !!(synth && Utterance && voices.length); },

      /** Reads one line aloud, live. Resolves true when it was read, false when no local voice can read it. */
      speak(text, part, rate = 1) {
        const words = (text || '').trim();
        refresh();
        if (!words || !synth || !Utterance || !voices.length) return Promise.resolve(false);
        if (!assigned.has(part)) assigned.set(part, assigned.size);
        const index = assigned.get(part);
        const u = new Utterance(words);
        u.voice = voices[index % voices.length];
        u.lang = u.voice.lang;
        u.pitch = PITCHES[Math.floor(index / voices.length) % PITCHES.length];
        u.rate = rate;
        u.volume = muted ? 0 : 1;
        return new Promise((resolve) => {
          let settled = false;
          const done = (read) => { if (!settled) { settled = true; clearTimeout(guard); resolve(read); } };
          // Some engines never fire `end` on a long utterance; a line is never waited on forever.
          const guard = setTimeout(() => { synth.cancel(); done(true); }, 4000 + (words.length * 120) / rate);
          u.onend = () => done(true);
          u.onerror = () => done(false);
          synth.speak(u);
        });
      },

      cancel() { if (synth) synth.cancel(); },
    };
  }

  return { create, castableVoices, PITCHES };
})();
