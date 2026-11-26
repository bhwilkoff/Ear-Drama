/**
 * The high-fidelity voices on the web: whether this browser may have them, and their download
 * (Decision 086; Decision 078: WebGPU only, the fp32 model in parts, a self-test after download).
 *
 * The Kokoro engine (js/kokoro-model.js, js/kokoro-voice.js and its worker) is loaded on demand:
 * when the person downloads in Settings > Voices, or at page start when the model is already in
 * Cache Storage. Otherwise nothing of it loads. ?kokoro=0 switches the voices off in this browser
 * (a kill switch for testing), kept until ?kokoro=1.
 *
 * Holds no audio and no speech API: a Kokoro line is a live stand-in, never kept (§5).
 */
const Voices = (() => {
  'use strict';

  /** Equal to KokoroModel.CACHE (js/kokoro.test.js checks): asking Cache Storage needs no engine. */
  const CACHE = 'ed-kokoro-v1';
  const OFF = 'ed.kokoro.off';
  const CHECK = 'ed.kokoro.check';
  const MANIFEST = 'data/kokoro/manifest.json';

  function store() { try { return typeof localStorage !== 'undefined' ? localStorage : null; } catch { return null; } }

  /** Whether ?kokoro=0 has switched the voices off in this browser (kept until ?kokoro=1). */
  function killed(search, storage) {
    const q = new URLSearchParams(search || '').get('kokoro');
    try {
      if (q === '0' && storage) storage.setItem(OFF, '1');
      if (q === '1' && storage) storage.removeItem(OFF);
      return q === '0' || !!(storage && storage.getItem(OFF) === '1');
    } catch { return q === '0'; }
  }

  /** The browser's own pieces the engine needs, without asking the GPU for anything yet. */
  function browserEnv() {
    const g = typeof navigator !== 'undefined' ? navigator.gpu : null;
    return {
      gpu: !!g,
      ok: typeof Worker !== 'undefined' && typeof caches !== 'undefined' && typeof crypto !== 'undefined' && !!crypto.subtle
        && (typeof isSecureContext === 'undefined' || isSecureContext),
      /** A WebGPU adapter exists (Chrome lists navigator.gpu even where no adapter can be had). */
      adapter: async () => { try { return !!(g && await g.requestAdapter()); } catch { return false; } },
      online: () => (typeof navigator === 'undefined' || navigator.onLine !== false),
    };
  }
  function addScript(src) {
    return new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = src; s.onload = resolve; s.onerror = () => reject(new Error(`${src} did not load`));
      document.head.append(s);
    });
  }

  function create({ search = (typeof location !== 'undefined' ? location.search : ''), storage = store(), env = browserEnv(),
                    cachesImpl = (typeof caches !== 'undefined' ? caches : null),
                    fetchImpl = (typeof fetch !== 'undefined' ? fetch.bind(globalThis) : null),
                    loadScript = addScript, kokoro = () => (typeof KokoroVoice !== 'undefined' ? KokoroVoice : null),
                    manifestURL = undefined, muted = false,
                    storageEstimate = () => (typeof navigator !== 'undefined' && navigator.storage && navigator.storage.estimate ? navigator.storage.estimate() : null) } = {}) {
    let gpuOK = null;
    let started = null;
    let lab = null;
    let booting = null;
    let phase = null;
    let progress = { done: 0, total: 0 };
    let abort = null;
    let total = null;
    const listeners = new Set();
    const emit = () => listeners.forEach(fn => { try { fn(); } catch (e) { console.error(e); } });
    const off = () => killed(search, storage);
    const checked = () => { try { return JSON.parse((storage && storage.getItem(CHECK)) || 'null'); } catch { return null; } };
    const possible = () => !off() && env.gpu && env.ok;

    async function probe() {
      if (!possible()) { gpuOK = false; return false; }
      if (gpuOK === null) { gpuOK = await env.adapter(); emit(); }
      return gpuOK;
    }

    /** Loads the engine's scripts once and boots the model (whether it is downloaded is then known). */
    function engine() {
      if (!booting) {
        booting = loadScript('js/kokoro-model.js').then(() => loadScript('js/kokoro-voice.js'))
          .then(() => kokoro().boot({ manifestURL, muted, allowed: () => status() === 'ready' }))
          .then((l) => { lab = l; emit(); return l; });
        booting.catch(() => { booting = null; });
      }
      return booting;
    }

    async function selfTest() {
      const k = kokoro();
      const e = k && k.engine();
      const r = e ? await e.selfTest() : { ok: false, reason: 'no engine' };
      try { if (storage) storage.setItem(CHECK, JSON.stringify({ ok: !!r.ok, rtf: r.rtf ?? null, at: Date.now() })); } catch { /* unkept: checked again next time */ }
      if (!r.ok) console.error('kokoro self-test', r);
      return r;
    }

    /**
     * unsupported (no WebGPU, switched off, or the self-test refused it), probing, absent (not downloaded),
     * downloading, checking (the self-test), failed (the download), ready.
     */
    function status() {
      if (!possible() || gpuOK === false) return 'unsupported';
      if (phase) return phase;
      if (lab && lab.model.isReady()) {
        const c = checked();
        return c ? (c.ok ? 'ready' : 'refused') : 'checking';
      }
      return gpuOK === null ? 'probing' : 'absent';
    }

    return {
      status,
      progress: () => ({ ...progress }),
      online: () => env.online(),
      onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
      /**
       * Page start: loads the engine only when a download finished here (its self-test result is kept)
       * and its cache is still there. A stopped download leaves parts but no result: Download resumes it.
       */
      start() { started = started || this.startNow(); return started; },
      /** Settles once page start has looked for a finished download (PLAYS-DESIGN §2.8 rule 13 waits on it). */
      whenStarted: () => started || Promise.resolve(false),
      async startNow() {
        if (!possible() || !cachesImpl || !checked()) return false;
        let have = false;
        try { have = await cachesImpl.has(CACHE); } catch { have = false; }
        if (!have || !(await probe())) return false;
        await engine();
        emit();
        return true;
      },
      probe,
      /** Everything a download fetches, from the manifest alone (no engine), or null. */
      async size() {
        if (total !== null) return total;
        try {
          const r = await fetchImpl(manifestURL || MANIFEST, { cache: 'no-cache' });
          if (!r.ok) return null;
          const m = await r.json();
          total = (m.files || []).reduce((n, f) => n + (Number(f.bytes) || 0), 0) || null;
        } catch { total = null; }
        return total;
      },
      /** The bytes this origin may still store (quota less usage), or null where the browser will not say. */
      async free() {
        try {
          const e = await storageEstimate();
          return e && Number.isFinite(e.quota) && Number.isFinite(e.usage) ? Math.max(0, e.quota - e.usage) : null;
        } catch { return null; }
      },
      /** The person's explicit download: loads the engine, fetches and checks every part, then the self-test. */
      async download() {
        if (!(await probe()) || phase === 'downloading' || phase === 'checking') return;
        phase = 'downloading';
        progress = { done: 0, total: total || 0 };
        abort = typeof AbortController !== 'undefined' ? new AbortController() : null;
        emit();
        try {
          const l = await engine();
          await l.model.download((done, all) => { progress = { done, total: all }; emit(); }, abort && abort.signal);
          phase = 'checking';
          emit();
          await selfTest();
          phase = null;
        } catch (e) {
          phase = e && e.name === 'AbortError' ? null : 'failed';
          if (phase) console.error('kokoro download', e);
        }
        abort = null;
        emit();
      },
      cancel() { if (abort) abort.abort(); },
      /** Runs the self-test again (after a refusal). */
      async recheck() {
        if (!lab || !lab.model.isReady()) return;
        phase = 'checking'; emit();
        await selfTest();
        phase = null; emit();
      },
      async remove() {
        if (lab) await lab.model.remove(); else if (cachesImpl) await cachesImpl.delete(CACHE);
        try { if (storage) storage.removeItem(CHECK); } catch { /* nothing kept */ }
        phase = null;
        emit();
      },
      /** The Kokoro voices the cast may use now (none unless ready). */
      voices() {
        const k = kokoro();
        return status() === 'ready' && k ? k.voices() : [];
      },
      /** Whether "Better voices" is offered: this browser may run them and they are not here yet. */
      offered: () => possible() && gpuOK !== false && ['probing', 'absent', 'failed'].includes(status()),
      loaded: () => !!booting,
    };
  }

  let page = null;
  /** The page's one instance (app.js starts it). */
  const shared = (opts) => { if (!page) page = create(opts); return page; };

  return { CACHE, OFF, CHECK, MANIFEST, killed, create, shared };
})();
