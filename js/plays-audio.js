/**
 * One recording session's audio on the web (PLAYS-DESIGN §4.1, WEB-DESIGN
 * §4.10): one AudioContext, the microphone through an AudioWorklet tap
 * (js/plays-worklet.js), the earlier performers' takes played into the
 * headphones, and an OfflineAudioContext to bring a capture to 48 kHz.
 *
 * Nothing here stores anything: a capture is handed to the session as
 * { samples, sampleRate }, and only js/plays-store.js writes it. The device
 * voice never passes through here; it plays on its own (js/plays-voice.js).
 */
const LiveAudio = (() => {
  'use strict';
  const C = PlaysCore;

  function supported() {
    return typeof navigator !== 'undefined' && !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)
      && typeof AudioContext !== 'undefined' && typeof AudioWorkletNode !== 'undefined'
      && typeof OfflineAudioContext !== 'undefined';
  }

  function concat(chunks) {
    const n = chunks.reduce((s, c) => s + c.length, 0);
    const out = new Float32Array(n);
    let o = 0;
    for (const c of chunks) { out.set(c, o); o += c.length; }
    return out;
  }

  function create({ muted = false } = {}) {
    let ctx = null;
    let stream = null;
    let node = null;
    let capturing = null;
    let meter = null;
    let playing = null;
    let capture = 'aec';

    return {
      get sampleRate() { return ctx ? ctx.sampleRate : C.TAKE_RATE; },
      /** "aec" when the browser's echo canceller processed the microphone, "direct" when it did not. */
      get capture() { return capture; },

      /** Asks for the microphone now, at the moment of recording (§2.3). The context is made
       *  before the first await so the press that started recording still counts as a gesture. */
      async start() {
        ctx = new AudioContext({ latencyHint: 'interactive' });
        const resumed = ctx.resume();
        stream = await navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: true, autoGainControl: false, noiseSuppression: false, channelCount: 1 },
        });
        const track = stream.getAudioTracks()[0];
        const settings = track && track.getSettings ? track.getSettings() : {};
        capture = settings.echoCancellation === false ? 'direct' : 'aec';
        await resumed;
        await ctx.audioWorklet.addModule('js/plays-worklet.js');
        node = new AudioWorkletNode(ctx, 'ed-capture', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1] });
        node.port.onmessage = (e) => {
          const chunk = e.data;
          if (capturing) { capturing.chunks.push(chunk); capturing.onChunk(chunk); }
          if (meter) meter.feed(chunk);
        };
        ctx.createMediaStreamSource(stream).connect(node);
        node.connect(ctx.destination);
      },

      beginCapture(onChunk) { capturing = { chunks: [], onChunk }; },
      endCapture() {
        const c = capturing;
        capturing = null;
        return { samples: concat(c ? c.chunks : []), sampleRate: this.sampleRate };
      },

      /** The bleed meter while the device voice reads: a count of loud frames, never the samples. */
      startMeter(threshold) { meter = new C.CueMeter(this.sampleRate, threshold); },
      stopMeter() { const m = meter; meter = null; return m ? m.fraction() : 0; },

      /** Plays an earlier performer's take (WAV bytes) into the headphones and waits for its end. */
      playTake(bytes) {
        const { samples, sampleRate } = C.decodeWav(bytes);
        if (!ctx || !samples.length) return Promise.resolve();
        const buffer = ctx.createBuffer(1, samples.length, sampleRate);
        buffer.getChannelData(0).set(samples);
        const src = ctx.createBufferSource();
        src.buffer = buffer;
        const g = ctx.createGain();
        g.gain.value = muted ? 0 : 1;
        src.connect(g);
        g.connect(ctx.destination);
        return new Promise((resolve) => {
          playing = { src, resolve };
          src.onended = () => { if (playing && playing.src === src) playing = null; resolve(); };
          src.start();
        });
      },

      stopPlayback() {
        if (!playing) return;
        const p = playing;
        playing = null;
        try { p.src.stop(); } catch { /* already stopped */ }
        p.resolve();
      },

      /** A capture at the take rate, 48 kHz (§4.2), resampled in memory. */
      async toTakeRate(cap) {
        if (cap.sampleRate === C.TAKE_RATE || !cap.samples.length) return cap;
        const frames = Math.max(1, Math.round(cap.samples.length * C.TAKE_RATE / cap.sampleRate));
        const off = new OfflineAudioContext(1, frames, C.TAKE_RATE);
        const buffer = off.createBuffer(1, cap.samples.length, cap.sampleRate);
        buffer.getChannelData(0).set(cap.samples);
        const src = off.createBufferSource();
        src.buffer = buffer;
        src.connect(off.destination);
        src.start();
        const out = await off.startRendering();
        return { samples: out.getChannelData(0).slice(), sampleRate: C.TAKE_RATE };
      },

      stop() {
        this.stopPlayback();
        capturing = null;
        meter = null;
        if (stream) stream.getTracks().forEach(t => t.stop());
        stream = null;
        if (node) { node.port.onmessage = null; node.disconnect(); }
        node = null;
        if (ctx && ctx.state !== 'closed') ctx.close().catch(() => {});
        ctx = null;
      },
    };
  }

  /** The browser's mix renderer for PlaysCore.renderMix. */
  const offlineContext = (channels, frames, rate) => new OfflineAudioContext(channels, frames, rate);

  return { supported, create, offlineContext };
})();
