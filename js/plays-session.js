/**
 * One performer recording one part (PLAYS-DESIGN §2.3-2.4) in one of the three modes
 * of owner ruling 4 (Run through, Line by line, Step), the web's mirror of apple/Core/Plays/RecordingSession.swift: five seconds of room
 * tone, then for each line the cue before it (an earlier performer's take
 * where one exists, the device voice live where not), then the microphone
 * until the line ends or the performer presses Stop. Only that window is kept.
 *
 * Every device is passed in (store, audio, voice, sleep, announce), so the
 * tests run the shipped session against fakes that play and record nothing.
 */
const RecordingSession = (() => {
  'use strict';
  const C = PlaysCore;

  function create({ production, script, part, store, audio, voice,
                    sleep = (ms) => new Promise(r => setTimeout(r, ms)),
                    announce = async () => {}, onChange = () => {} }) {
    let detector = null;
    let roomToneRMS = 0;
    let finishListening = null;
    let ended = false;
    let runToken = 0;

    const s = {
      phase: { kind: 'idle' },
      production,
      script,
      part,
      lines: C.linesFor(script, part),
      /** The device voice's speed, adjustable (§7). */
      standInRate: 1,
      started: false,
      lastTakeBleed: false,
      /** Run through, Line by line, or Step (owner ruling 4); only what follows a take differs. */
      mode: 'step',
      /** The run on screen (Run through): its first line and the takes it made. */
      run: null,
    };

    const set = (phase) => { s.phase = phase; onChange(s); };
    s.isBusy = () => ['roomTone', 'cue', 'listening'].includes(s.phase.kind);

    /** Changes the store's current record, never a stale copy. */
    function mutate(change) {
      const latest = store.production(s.production.id) || s.production;
      s.production = change(latest);
      store.update(s.production);
    }

    function hear(chunk) {
      if (!finishListening || !detector) return;
      const event = detector.feed(chunk);
      if (event && event.type === 'end') stop();
    }

    function stop() {
      const done = finishListening;
      finishListening = null;
      if (done) done();
    }

    s.begin = async () => {
      if (s.started || ended) return;
      try {
        await audio.start();
      } catch (e) {
        audio.stop();
        set({ kind: 'failed', reason: (e && e.name) || 'Error' });
        return;
      }
      if (ended) { audio.stop(); return; }
      s.started = true;
      audio.beginCapture(() => {});
      for (let second = C.ROOM_TONE_SECONDS; second > 0; second--) {
        set({ kind: 'roomTone', secondsLeft: second });
        await sleep(1000);
        if (ended) return;
      }
      const tone = audio.endCapture();
      roomToneRMS = C.rms(tone.samples);
      if (tone.samples.length) {
        try {
          const file = await store.writeRoomTone(await audio.toTakeRate(tone), s.production);
          mutate(p => ({ ...p, roomTone: [...p.roomTone, file] }));
        } catch (e) {
          console.error('room tone', e);
        }
      }
      if (!ended) set({ kind: 'idle' });
    };

    /** Plays cue lines (a human take where one exists, the device voice live where not); what each was. */
    async function playCues(cues, threshold, live = () => !ended) {
      const heard = {};
      let bleed = false;
      for (const cue of cues) {
        if (!live()) break;
        const t = C.usableTake(s.production, cue.id);
        if (t) {
          set({ kind: 'cue', run: !!s.run, lineID: cue.id, deviceVoice: false });
          await audio.playTake(await store.readTake(s.production.id, t.file));
          heard[cue.id] = t.id;
        } else {
          set({ kind: 'cue', run: !!s.run, lineID: cue.id, deviceVoice: true });
          audio.startMeter(threshold);
          const read = await voice.speak(C.spokenText(cue), C.linePart(cue), s.standInRate);
          const loud = audio.stopMeter();
          if (read) {
            heard[cue.id] = C.STANDIN;
            if (loud >= C.BLEED_LOUD_FRACTION) bleed = true;
          }
        }
      }
      return { heard, bleed };
    }

    /** Opens the microphone on a line until it ends (or Stop), and keeps the line window as a new take. */
    async function listenAndKeep(lineID, heard, bleed) {
      await announce();
      if (ended) return null;
      set({ kind: 'listening', run: !!s.run, lineID });
      detector = new C.LineEndDetector(audio.sampleRate, roomToneRMS);
      await new Promise((resolve) => {
        finishListening = resolve;
        audio.beginCapture(hear);
      });
      const cap = audio.endCapture();
      const [from, to] = C.lineWindow(detector.onset, detector.end, cap.samples.length, cap.sampleRate);
      detector = null;
      if (ended) return null;
      const kept = { samples: cap.samples.subarray(from, to), sampleRate: cap.sampleRate };
      if (!kept.samples.length) return null;
      try {
        const atRate = await audio.toTakeRate(kept);
        const file = await store.writeTake(atRate, s.production, lineID);
        const take = {
          id: C.uuid(), lineID, part, file, created: C.now(), frames: atRate.samples.length,
          sampleRate: atRate.sampleRate, capture: audio.capture, heard,
          peak: C.samplePeak(atRate.samples), bleed,
        };
        const loudness = C.integratedLoudness(atRate.samples, atRate.sampleRate);
        if (loudness !== null) take.loudness = loudness;
        mutate(p => C.addTake(p, take));
        s.lastTakeBleed = bleed;
        return take;
      } catch (e) {
        console.error('take', e);
        set({ kind: 'failed', reason: 'save' });
        return null;
      }
    }

    /** Remembers a take the run made, with the take its line had before, for Discard the run. */
    function noteRun(lineID, take, prior) {
      const entry = s.run.takes.find(e => e.lineID === lineID);
      if (entry) entry.takes.push(take.id);
      else s.run.takes.push({ lineID, prior, takes: [take.id] });
    }

    /**
     * Step and Line by line: plays the cue, then listens for the line and keeps it as a new
     * take (the line's chosen one). Step ends on the take's review, Line by line on the line,
     * ready; Again in a run's review returns to the review.
     */
    s.record = async (lineID, runUp = false) => {
      if (!s.started || s.isBusy() || ended) return;
      const prior = s.production.chosen[lineID] || null;
      const { heard, bleed } = await playCues(C.cueLines(script, lineID, runUp), C.thresholdFor(roomToneRMS));
      if (ended) return;
      const t = await listenAndKeep(lineID, heard, bleed);
      if (ended || s.phase.kind === 'failed') return;
      if (s.run) {
        if (t) noteRun(lineID, t, prior);
        set({ kind: 'runReview' });
      } else if (!t) set({ kind: 'idle' });
      else set({ kind: s.mode === 'step' ? 'review' : 'idle', lineID });
    };

    /**
     * Run through (owner ruling 4): the play runs straight through from the line's cue, other
     * parts in their human takes or the device voice live, and the microphone opens on each of
     * this part's lines as it comes; the line-end detector closes it and the play goes on. The
     * run ends after the part's last line or at Pause, and opens its review.
     */
    s.runThrough = async (fromLineID) => {
      if (!s.started || s.isBusy() || ended || s.run) return;
      const my = ++runToken;
      s.run = { from: fromLineID, takes: [] };
      const live = () => !ended && my === runToken;
      const threshold = C.thresholdFor(roomToneRMS);
      let heard = {}, bleed = false;
      for (const entry of C.runPlan(s.production, script, part, fromLineID)) {
        if (!live()) break;
        const line = script.lines.find(l => l.id === entry.lineID);
        if (entry.source === 'mine') {
          const prior = s.production.chosen[line.id] || null;
          const t = await listenAndKeep(line.id, heard, bleed);
          if (ended || s.phase.kind === 'failed') return;
          if (t) noteRun(line.id, t, prior);
          heard = {}; bleed = false;
        } else {
          const got = await playCues([line], threshold, live);
          heard = got.heard; bleed = got.bleed;
        }
      }
      if (ended) return;
      if (s.run.takes.length) set({ kind: 'runReview' });
      else { s.run = null; set({ kind: 'idle' }); }
    };

    /** Pause ends a run; a line being recorded is kept as far as it went. */
    s.pause = () => {
      if (!s.run || s.phase.kind === 'runReview') return;
      runToken += 1;
      if (s.phase.kind === 'listening') stop();
      else { voice.cancel(); audio.stopPlayback(); }
    };

    /** Keep N takes: the run's takes stay their lines' chosen ones. */
    s.keepRun = () => {
      if (!s.run || s.phase.kind !== 'runReview') return;
      s.run = null;
      set({ kind: 'idle' });
    };

    /** Discard the run: its takes are deleted and each line goes back to the take it had. */
    s.discardRun = async () => {
      if (!s.run || s.phase.kind !== 'runReview') return;
      const run = s.run.takes;
      s.run = null;
      await store.discardRun(s.production.id, run);
      s.production = store.production(s.production.id) || s.production;
      set({ kind: 'idle' });
    };

    /** The takes the run on screen made, in script order, each its line's latest. */
    s.runTakes = () => (s.run ? s.run.takes.map(e => C.takeById(s.production, e.takes[e.takes.length - 1])).filter(Boolean) : []);

    /** After a playback, back to where it started from (a cue phase is never the place to return to). */
    const settle = (back) => { if (!ended) set(back.kind === 'cue' || back.kind === 'listening' ? { kind: 'idle' } : back); };

    /** The cue alone, heard before recording a line (Line by line's Cue). */
    s.playCue = async (lineID) => {
      if (!s.started || s.isBusy()) return;
      const back = s.phase;
      await playCues(C.cueLines(script, lineID), C.thresholdFor(roomToneRMS));
      settle(back);
    };

    /** A take heard after its cue, as it will sit in the play (Step's With cue, the run's review). */
    s.playWithCue = async (t) => {
      if (!s.started || s.isBusy()) return;
      const back = s.phase;
      await playCues(C.cueLines(script, t.lineID), C.thresholdFor(roomToneRMS));
      if (ended) return;
      set({ kind: 'cue', run: !!s.run, lineID: t.lineID, deviceVoice: false });
      await audio.playTake(await store.readTake(s.production.id, t.file));
      settle(back);
    };

    /** The mode control: refused while the microphone is armed or open, and during a run. */
    s.setMode = (mode) => {
      if (!C.MODES.includes(mode) || s.isBusy() || s.run) return false;
      s.mode = mode;
      if (s.phase.kind === 'review') s.phase = { kind: 'idle' };
      onChange(s);
      return true;
    };

    /** The one control's second press: stop listening now. */
    s.stopListening = () => { if (s.phase.kind === 'listening') stop(); };

    /** "Hear it read": the device voice reads the performer's own line once, on request. Never kept. */
    s.hearItRead = async (lineID) => {
      const line = script.lines.find(l => l.id === lineID);
      if (!s.started || s.isBusy() || !line) return;
      set({ kind: 'cue', lineID, deviceVoice: true });
      await voice.speak(C.spokenText(line), C.linePart(line), s.standInRate);
      if (!ended) set({ kind: 'idle' });
    };

    s.playTake = async (t) => {
      if (!s.started || s.isBusy()) return;
      const back = s.phase;
      set({ kind: 'cue', run: !!s.run, lineID: t.lineID, deviceVoice: false });
      await audio.playTake(await store.readTake(s.production.id, t.file));
      settle(back);
    };

    s.choose = (t) => {
      mutate(p => C.choose(p, t.id));
      onChange(s);
    };

    s.end = () => {
      ended = true;
      runToken += 1;
      stop();
      voice.cancel();
      audio.stop();
      s.started = false;
      s.phase = { kind: 'idle' };
    };

    return s;
  }

  return { create };
})();

/**
 * The listen-through of a play not yet fully voiced (PLAYS-DESIGN §2.6; C5, owner
 * 2026-10-23): C.listenPlan in order, each human take from the store, each open
 * speaking line read live by the device voice. It holds a store only to read takes;
 * it writes nothing, and a voice entry is words, so no device voice can reach a
 * take, the mix, an export, or an upload (§5).
 */
const ListenThrough = (() => {
  'use strict';
  const C = PlaysCore;

  function create({ production, script, store, audio, voice, onChange = () => {} }) {
    const plan = C.listenPlan(production, script);
    let run = 0;
    const s = { plan, index: 0, playing: false, rate: 1 };

    s.current = () => plan[s.index] || null;

    s.play = async () => {
      if (s.playing || !plan.length) return;
      const my = ++run;
      s.playing = true;
      if (s.index >= plan.length) s.index = 0;
      onChange(s);
      try {
        await audio.startPlayback();
        while (my === run && s.index < plan.length) {
          const entry = plan[s.index];
          onChange(s);
          if (entry.source === 'take') await audio.playTake(await store.readTake(production.id, entry.take.file));
          else await voice.speak(entry.text, entry.part, s.rate);
          if (my !== run) return;
          s.index += 1;
        }
      } catch (e) {
        console.error('listen-through', e);
      }
      if (my === run) {
        s.playing = false;
        if (s.index >= plan.length) s.index = 0;
        onChange(s);
      }
    };

    s.stop = () => {
      run += 1;
      s.playing = false;
      voice.cancel();
      audio.stopPlayback();
      onChange(s);
    };

    s.end = () => {
      run += 1;
      s.playing = false;
      voice.cancel();
      audio.stop();
    };

    return s;
  }

  return { create };
})();
