/**
 * One performer recording one part, line by line (PLAYS-DESIGN §2.3-2.4), the
 * web's mirror of apple/Core/Plays/RecordingSession.swift: five seconds of room
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

    /** Plays the cue, then listens for the line and keeps it as a new take (the line's chosen one). */
    s.record = async (lineID, runUp = false) => {
      if (!s.started || s.isBusy() || ended) return;
      const heard = {};
      let bleed = false;
      const threshold = C.thresholdFor(roomToneRMS);
      for (const cue of C.cueLines(script, lineID, runUp)) {
        const t = C.chosenTake(s.production, cue.id);
        if (t) {
          set({ kind: 'cue', lineID: cue.id, deviceVoice: false });
          await audio.playTake(await store.readTake(s.production.id, t.file));
          heard[cue.id] = t.id;
        } else {
          set({ kind: 'cue', lineID: cue.id, deviceVoice: true });
          audio.startMeter(threshold);
          const read = await voice.speak(C.spokenText(cue), C.linePart(cue), s.standInRate);
          const loud = audio.stopMeter();
          if (read) {
            heard[cue.id] = C.STANDIN;
            if (loud >= C.BLEED_LOUD_FRACTION) bleed = true;
          }
        }
        if (ended) return;
      }
      await announce();
      if (ended) return;
      set({ kind: 'listening', lineID });
      detector = new C.LineEndDetector(audio.sampleRate, roomToneRMS);
      await new Promise((resolve) => {
        finishListening = resolve;
        audio.beginCapture(hear);
      });
      const cap = audio.endCapture();
      const [from, to] = C.lineWindow(detector.onset, detector.end, cap.samples.length, cap.sampleRate);
      detector = null;
      if (ended) return;
      const kept = { samples: cap.samples.subarray(from, to), sampleRate: cap.sampleRate };
      if (!kept.samples.length) { set({ kind: 'idle' }); return; }
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
        set({ kind: 'review', lineID });
      } catch (e) {
        console.error('take', e);
        set({ kind: 'failed', reason: 'save' });
      }
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
      set({ kind: 'cue', lineID: t.lineID, deviceVoice: false });
      await audio.playTake(await store.readTake(s.production.id, t.file));
      if (!ended) set({ kind: 'review', lineID: t.lineID });
    };

    s.choose = (t) => {
      mutate(p => C.choose(p, t.id));
      onChange(s);
    };

    s.end = () => {
      ended = true;
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
