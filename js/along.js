/**
 * The read-along's one controller (PLAYS-DESIGN §2.11; WEB-DESIGN §4.16a), the web's mirror of Apple's AlongModel.
 * Three kinds of entries feed it, each naming its line: a production's listen plan (human takes and the cast's
 * voices), the cast reading the whole script (Hear the cast), and a finished drama's line files. It reads them
 * in order, and reports the line heard (`onLine`) and, where the voice measures it, the word heard (`onWord`,
 * a printed range of the line's words through `ReaderCore.word`). Nothing is guessed: a take, a file, a Kokoro
 * line and a voice that sends no boundaries light the line and mark no word.
 *
 * Pause holds the line (still lit); Play starts that line again from its beginning; Previous and Next move to the
 * nearest line the read-along reads, playing from there, or moving the held line while paused. Speed multiplies
 * each part's own speed: a voice takes it from its next line, a take or a file at once (`playbackRate`, pitch kept).
 *
 * Every device is passed in (voice, media, muted), so tests run the shipped controller against fakes.
 * It holds no audio path and keeps nothing: a voice entry is words, so no device voice can reach a take (§5).
 */
const Along = (() => {
  'use strict';
  const C = PlaysCore;
  const R = ReaderCore;

  /** A production's listen plan: its takes and, for open lines, the cast's voices (directions and sound only when given one). */
  function productionEntries(production, script, voice) {
    return C.listenPlan(production, script, voice.reads ? (part) => !C.isSpeaking(part) && voice.reads(part) : null);
  }

  /** Hear the cast: every line the cast reads, in order (a speech, or a part with a voice, §2.8 rule 7). */
  function tableEntries(script, voice) {
    const out = [];
    for (const line of script.lines) {
      const part = C.linePart(line);
      if (voice.reads(part)) out.push({ lineID: line.id, part, source: 'voice', text: C.spokenText(line) });
    }
    return out;
  }

  /** A finished drama's files in order, each the line it speaks (ReaderCore.dramaPlan). */
  const dramaEntries = (plan) => plan.map(p => ({ lineID: p.lineID, source: 'take', url: p.url }));

  /**
   * `media(entry)` makes an element-like `{ play(): Promise<boolean>, pause(), rate(x), muted }` for a take or a file
   * (injected, so no sound here); `play()` resolves true when it ended, false when it could not be played.
   */
  function create({ script, entries, voice, media, muted = () => false, speed = R.savedSpeed(),
                    onLine = () => {}, onWord = () => {}, onChange = () => {} }) {
    const byLine = new Map(script.lines.map(l => [l.id, l]));
    const s = { entries, index: 0, playing: false, held: false, speed: R.alongSpeed(speed) };
    let run = 0;
    let el = null;

    /** The entry heard, or the one a pause holds; null once stopped. */
    s.current = () => ((s.playing || s.held) ? entries[s.index] || null : null);
    s.line = () => { const e = s.current(); return e ? e.lineID : null; };

    const silence = () => {
      if (el) { const e = el; el = null; try { e.pause(); } catch { /* already ended */ } }
      voice.cancel();
    };

    async function playEntry(entry, my) {
      if (entry.source === 'voice') {
        const sp = R.spoken(byLine.get(entry.lineID));
        return voice.speak(entry.text, entry.part, s.speed, {
          onWord: (location, length) => { if (my === run) onWord(entry.lineID, R.word(sp, location, length)); },
        });
      }
      el = media(entry);
      el.muted = muted();
      el.rate(s.speed);
      return el.play();
    }

    async function go(my) {
      let readOne = false;
      while (my === run && s.index < entries.length) {
        const entry = entries[s.index];
        onWord(entry.lineID, null);
        onLine(entry.lineID, entry);
        onChange(s);
        let read = false;
        try { read = await playEntry(entry, my); } catch { read = false; }
        el = null;
        if (my !== run) return;
        // Nothing read yet and the first line could not be (a browser holds speech until a press): wait for a press.
        if (!read && !readOne) { s.playing = false; s.held = true; onChange(s); return; }
        readOne = readOne || read;
        s.index += 1;
      }
      if (my !== run) return;
      s.playing = false;
      s.held = false;
      s.index = 0;
      onWord(null, null);
      onLine(null, null);
      onChange(s);
    }

    /** Starts at the first entry whose line is at or after `lineIndex` (the reader's place), when given. */
    s.from = (lineIndex) => {
      if (s.playing) return;
      const at = entries.findIndex(e => byLine.has(e.lineID) && script.lines.indexOf(byLine.get(e.lineID)) >= lineIndex);
      s.index = at >= 0 ? at : 0;
    };

    s.play = () => {
      if (s.playing || !entries.length) return;
      silence();
      const my = ++run;
      s.playing = true;
      s.held = false;
      if (s.index >= entries.length) s.index = 0;
      go(my);
    };

    /** Holds the line: still lit, nothing heard. Play starts it again from its beginning. */
    s.pause = () => {
      if (!s.playing) return;
      run += 1;
      s.playing = false;
      s.held = true;
      silence();
      onWord(null, null);
      onChange(s);
    };

    s.toggle = () => { if (s.playing) s.pause(); else s.play(); };

    const move = (by) => {
      const to = s.index + by;
      if (!(s.playing || s.held) || to < 0 || to >= entries.length) return;
      const was = s.playing;
      run += 1;
      silence();
      s.index = to;
      onWord(null, null);
      if (was) { s.playing = false; s.play(); return; }
      s.held = true;
      onLine(entries[to].lineID, entries[to]);
      onChange(s);
    };
    s.next = () => move(1);
    s.prev = () => move(-1);
    s.canPrev = () => (s.playing || s.held) && s.index > 0;
    s.canNext = () => (s.playing || s.held) && s.index < entries.length - 1;

    /** Ends the reading and the light; the bar goes back to the reader's own controls. */
    s.stop = () => {
      run += 1;
      s.playing = false;
      s.held = false;
      s.index = 0;
      silence();
      onWord(null, null);
      onLine(null, null);
      onChange(s);
    };

    /** The reader closed: stop with nothing reported. */
    s.end = () => { run += 1; s.playing = false; s.held = false; silence(); };

    /** Speed (rule 7): remembered, and a take or a file in the air takes it at once. */
    s.setSpeed = (x) => {
      s.speed = R.alongSpeed(x);
      R.saveSpeed(s.speed);
      if (el) el.rate(s.speed);
      onChange(s);
    };

    return s;
  }

  /**
   * The browser's element-like player for a take (WAV bytes) or a drama's file (a URL): an <audio> element at
   * `playbackRate` with `preservesPitch`, so a change of speed keeps the voice's pitch.
   */
  function mediaFor(read) {
    return (entry) => {
      const a = new Audio();
      let url = null;
      const done = () => { if (url) { URL.revokeObjectURL(url); url = null; } };
      return {
        get muted() { return a.muted; },
        set muted(v) { a.muted = v; },
        rate(x) { a.defaultPlaybackRate = x; a.playbackRate = x; a.preservesPitch = true; a.webkitPreservesPitch = true; },
        pause() { a.pause(); done(); a.dispatchEvent(new Event('ended')); },
        play: () => new Promise((resolve) => {
          a.addEventListener('ended', () => { done(); resolve(true); }, { once: true });
          a.addEventListener('error', () => { done(); resolve(false); }, { once: true });
          (async () => {
            if (entry.url) a.src = entry.url;
            else {
              url = URL.createObjectURL(new Blob([await read(entry)], { type: 'audio/wav' }));
              a.src = url;
            }
            a.playbackRate = a.defaultPlaybackRate;
            await a.play();
          })().catch(() => { done(); resolve(false); });
        }),
      };
    };
  }

  return { create, productionEntries, tableEntries, dramaEntries, mediaFor };
})();
