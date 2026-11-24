/**
 * Kokoro, the downloadable voices, as a scene partner (PLAYS-DESIGN §2.8 engine 'kokoro', §5).
 * Loaded on demand by js/voices.js (Decision 086; WebGPU only, Decision 078); see docs/research/design/R2-kokoro-feasibility.md.
 *
 * A line is rendered in a Web Worker (js/kokoro-worker.js) into a buffer held in memory, played
 * once through Web Audio, and dropped: like a system voice it is a live stand-in, never a take,
 * never kept (§5). No eSpeak: the words arrive already turned into phonemes by the catalog
 * (misaki's Apache lexicon plus a permissive fallback, built once and published per play),
 * so this file needs no phonemizer. A line with no published phonemes is not read by Kokoro;
 * the part's system voice reads it instead.
 *
 * This file keeps nothing: js/plays.test.js scans it for storage.
 */
const KokoroVoice = (() => {
  'use strict';

  /** The 28 English voices (VOICES.md, Kokoro-82M v1.0), in the order of the published voice table. Grade is Kokoro's own. */
  const VOICES = [
    ['af_heart', 'Heart', 'A'], ['af_alloy', 'Alloy', 'C'], ['af_aoede', 'Aoede', 'C+'], ['af_bella', 'Bella', 'A-'],
    ['af_jessica', 'Jessica', 'D'], ['af_kore', 'Kore', 'C+'], ['af_nicole', 'Nicole', 'B-'], ['af_nova', 'Nova', 'C'],
    ['af_river', 'River', 'D'], ['af_sarah', 'Sarah', 'C+'], ['af_sky', 'Sky', 'C-'],
    ['am_adam', 'Adam', 'F+'], ['am_echo', 'Echo', 'D'], ['am_eric', 'Eric', 'D'], ['am_fenrir', 'Fenrir', 'C+'],
    ['am_liam', 'Liam', 'D'], ['am_michael', 'Michael', 'C+'], ['am_onyx', 'Onyx', 'D'], ['am_puck', 'Puck', 'C+'],
    ['am_santa', 'Santa', 'D-'],
    ['bf_alice', 'Alice', 'D'], ['bf_emma', 'Emma', 'B-'], ['bf_isabella', 'Isabella', 'C'], ['bf_lily', 'Lily', 'D'],
    ['bm_daniel', 'Daniel', 'D'], ['bm_fable', 'Fable', 'C'], ['bm_george', 'George', 'C'], ['bm_lewis', 'Lewis', 'D+'],
  ].map(([id, name, grade], index) => ({
    id, name, grade, index,
    lang: id[0] === 'b' ? 'en-GB' : 'en-US',
    // The voice's own reported gender (its id says it), which §2.8 rule 4 may read; never a part's.
    gender: id[1] === 'f' ? 'female' : 'male',
  }));
  const GRADE = { A: 2, 'A-': 2, 'B-': 1 };
  /** Kokoro's own grades, best to worst: the defaults' order inside the engine (Decision 086). */
  const GRADES = ['A', 'A-', 'B-', 'C+', 'C', 'C-', 'D+', 'D', 'D-', 'F+'];
  /** Grades under C- start out of the auto-cast pool (Settings > Voices can tick them back in). */
  const LOW = (g) => GRADES.indexOf(g) > GRADES.indexOf('C-');
  /** Tokens per render: Kokoro rushes past ~400 (VOICES.md) and stops at 510. */
  const MAX_TOKENS = 400;

  /** The voices the cast may use: none unless they are allowed (js/voices.js) AND downloaded. Best grade first. */
  function castable({ enabled, ready }) {
    if (!enabled || !ready) return [];
    return VOICES.map(v => ({ engine: 'kokoro', id: v.id, name: `${v.name} (Kokoro)`, lang: v.lang, tier: GRADE[v.grade] || 0,
                              grade: v.grade, gender: v.gender, isDefault: false, index: v.index, offByDefault: LOW(v.grade) }))
      .sort((a, b) => (GRADES.indexOf(a.grade) - GRADES.indexOf(b.grade)) || (a.index - b.index));
  }

  /**
   * Splits a phoneme string into renders of at most `max` symbols, at the last sentence
   * punctuation, else the last comma, else the last space before the limit. Joined, they are the input.
   */
  function chunks(ps, max = MAX_TOKENS) {
    const out = [];
    let rest = ps || '';
    while (rest.length > max) {
      const head = rest.slice(0, max);
      let cut = Math.max(head.lastIndexOf('. '), head.lastIndexOf('! '), head.lastIndexOf('? '), head.lastIndexOf('; '));
      if (cut < max / 4) cut = head.lastIndexOf(', ');
      if (cut < max / 4) cut = head.lastIndexOf(' ');
      if (cut <= 0) cut = max - 1;
      out.push(rest.slice(0, cut + 1));
      rest = rest.slice(cut + 1);
    }
    if (rest) out.push(rest);
    return out;
  }

  /** Phonemes to Kokoro's token ids (its tokenizer.json vocab), padded with 0 at both ends; unknown symbols dropped. */
  function tokenize(ps, vocab) {
    const ids = [0];
    for (const ch of ps) if (Object.prototype.hasOwnProperty.call(vocab, ch)) ids.push(vocab[ch]);
    ids.push(0);
    return ids;
  }

  /**
   * The words as the phoneme file keys them: printed italic marks dropped, whitespace folded, two hyphens read as
   * a dash and leading punctuation dropped, so a line shown through the opening's clean (Today's scene, Hear in
   * Library > Voices) finds the same row as the script's own words. Unfolded, a Kokoro voice's Hear found no row
   * and said nothing (apple Kokoro.keyOf, 2026-11-23).
   */
  const keyOf = (text) => (text || '').replace(/_/g, '').replace(/\s+/g, ' ').trim()
    .replace(/--/g, '\u2014').replace(/^[.,:;\u2014-]+\s*/, '');

  /* ---- The engine (browser only) ---- */

  let shared = null;

  /**
   * The engine StandInVoice hands a Kokoro part to. `model` is a KokoroModel instance, ready.
   * speak() resolves true when the line was read, false when Kokoro cannot read it (no phonemes,
   * no model), so the caller can read it with the system voice instead.
   */
  function create({ model, workerURL = 'js/kokoro-worker.js', muted = false, AudioCtx = (typeof AudioContext !== 'undefined' ? AudioContext : null) }) {
    let worker = null;
    let loading = null;
    let ctx = null;
    let vocab = null;
    let seq = 0;
    let current = null;
    const pending = new Map();
    const phonemes = new Map();
    const loads = new Map();

    async function boot() {
      if (loading) return loading;
      loading = (async () => {
        const [onnx, table, tok] = await Promise.all([model.bytes('model'), model.bytes('voices'), model.bytes('vocab')]);
        if (!onnx || !table || !tok) throw new Error('model not downloaded');
        vocab = JSON.parse(new TextDecoder().decode(tok)).model.vocab;
        worker = new Worker(workerURL);
        worker.onmessage = (e) => {
          const p = pending.get(e.data.id);
          if (!p) return;
          pending.delete(e.data.id);
          if (e.data.error) p.reject(new Error(e.data.error)); else p.resolve(e.data);
        };
        // WebGPU where present (the only measured web path faster than real time, with the fp32 model).
        const ep = typeof navigator !== 'undefined' && navigator.gpu ? 'webgpu' : 'wasm';
        await call({ type: 'load', model: onnx, voices: table, ep }, [onnx, table]);
      })();
      return loading;
    }
    function call(msg, transfer = []) {
      const id = ++seq;
      return new Promise((resolve, reject) => { pending.set(id, { resolve, reject }); worker.postMessage({ ...msg, id }, transfer); });
    }

    /** A play's published phonemes (the catalog's per-play file), fetched once; keyed by the words. */
    function prepare(url) {
      if (!url) return Promise.resolve();
      if (!loads.has(url)) loads.set(url, load(url));
      return loads.get(url);
    }
    async function load(url) {
      try {
        const r = await fetch(url);
        if (!r.ok) return;
        const f = await r.json();
        const m = new Map();
        for (const row of f.lines || []) m.set(keyOf(row.t), row);
        phonemes.set(url, m);
      } catch { /* no phonemes: the system voice reads */ }
    }
    function lookup(text, lang) {
      const k = keyOf(text);
      for (const m of phonemes.values()) {
        const row = m && m.get(k);
        if (row) return lang === 'en-GB' ? (row.gb || row.us) : row.us;
      }
      return null;
    }

    function play(samples, playbackRate) {
      if (!ctx) ctx = new AudioCtx();
      const buf = ctx.createBuffer(1, samples.length, 24000);
      buf.copyToChannel(samples, 0);
      const src = ctx.createBufferSource();
      src.buffer = buf;
      src.playbackRate.value = playbackRate;
      const gain = ctx.createGain();
      gain.gain.value = muted ? 0 : 1;
      src.connect(gain).connect(ctx.destination);
      return new Promise((resolve) => {
        current = src;
        src.onended = () => { if (current === src) current = null; resolve(true); };
        src.start();
      });
    }

    return {
      prepare,
      /**
       * The web's gate after a download (Decision 078, R2-kokoro-feasibility §6 item 5): two renders of
       * one fixed phrase, nothing played. Passes when both are sound (finite, not silent) and the second,
       * past the first render's warm-up, is faster than real time by the measured margin (RTF under 0.7).
       */
      async selfTest() {
        try { await boot(); } catch (e) { return { ok: false, reason: String(e && e.message || e) }; }
        const tokens = Int32Array.from(tokenize('ðɪs ɪz ə tˈɛst ʌv ðə vˈYsᵻz.', vocab));
        let rtf = Infinity;
        for (let i = 0; i < 2; i++) {
          let out;
          try { out = await call({ type: 'synth', tokens, voice: 0, speed: 1 }); } catch (e) { return { ok: false, reason: String(e && e.message || e) }; }
          const s = out.samples;
          let sum = 0;
          for (let k = 0; k < s.length; k++) sum += s[k] * s[k];
          if (!s.length || Math.sqrt(sum / s.length) < 1e-4) return { ok: false, reason: 'silent' };
          rtf = out.ms / ((s.length / 24000) * 1000);
        }
        return { ok: rtf < 0.7, rtf: Math.round(rtf * 100) / 100, reason: rtf < 0.7 ? null : 'slow' };
      },
      /**
       * Reads `text` in Kokoro voice `voiceId`. Speed and pitch: the model renders at rate/pitch and
       * Web Audio plays it back at `pitch`, so the tempo is `rate` and the pitch moves by `pitch`.
       */
      async speak(text, voiceId, { rate = 1, pitch = 1 } = {}) {
        const v = VOICES.find(x => x.id === voiceId);
        const ps = v && lookup(text, v.lang);
        if (!v || !ps) return false;
        try { await boot(); } catch { return false; }
        const speed = Math.min(2, Math.max(0.5, rate / pitch));
        // Render the next piece while this one plays, so a long speech never waits between pieces.
        const pieces = chunks(ps).map(c => tokenize(c, vocab));
        let next = call({ type: 'synth', tokens: Int32Array.from(pieces[0]), voice: v.index, speed });
        for (let i = 0; i < pieces.length; i++) {
          let out;
          // A refused render (non-finite samples) before anything played: the system voice reads the line.
          try { out = await next; } catch { if (i === 0) return false; break; }
          if (i + 1 < pieces.length) next = call({ type: 'synth', tokens: Int32Array.from(pieces[i + 1]), voice: v.index, speed });
          await play(out.samples, pitch);
        }
        return true;
      },
      cancel() { if (current) { try { current.stop(); } catch { /* already ended */ } current = null; } },
    };
  }

  /** The page's one engine, made once the model exists. */
  function engine(opts) {
    if (!shared && opts && opts.model) shared = create(opts);
    return shared;
  }

  /* ---- The page's one model and engine (js/voices.js calls boot, on demand) ---- */

  let lab = null;
  /**
   * Makes the model and the engine; resolves when it is known whether the model is downloaded.
   * `allowed()` is js/voices.js's gate (WebGPU, not switched off, the self-test passed); `muted` is ?mute=1.
   */
  async function boot({ manifestURL, phonemesBase = 'data/plays/library/phonemes/', muted = false, allowed = () => true } = {}) {
    if (lab) return lab;
    const model = KokoroModel.create(manifestURL ? { manifestURL } : {});
    lab = { model, phonemesBase, allowed };
    await model.check();
    engine({ model, muted });
    return lab;
  }
  const ready = () => !!(lab && lab.model.isReady());
  /** Whether Kokoro voices may be cast now: allowed and downloaded. */
  const available = () => !!(ready() && lab.allowed());
  /** Castable Kokoro voices now (none unless available). */
  const voices = () => castable({ enabled: !!(lab && lab.allowed()), ready: ready() });
  /** Fetches a play's published phonemes, once, when the model is here. An own script has none (PLAYS-DESIGN §13 item 8). */
  function prepare(script) {
    if (ready() && shared && script && script.id && script.kind !== 'own') return shared.prepare(`${lab.phonemesBase}${script.id}.json`);
    return Promise.resolve();
  }
  const model = () => (lab ? lab.model : null);

  return { VOICES, GRADES, MAX_TOKENS, castable, chunks, tokenize, keyOf, create, engine, boot, available, voices, prepare, model };
})();
