/**
 * Where the Sound part's audio comes from on the web (B32 §3.4, §5.2; WEB-DESIGN §4.16 item 14a):
 *   - the pack, a source that may be absent: its manifest read through API.sounds (null until the owner rules on
 *     its hosting), each category downloaded on the person's press into Cache Storage `ed-sounds-1` (the service
 *     worker keeps that cache), every file checked against its sha256 before use;
 *   - the person's own sounds, on this device only: the plays database (`ed-plays`, its `files` store) under
 *     `sounds/mine/` beside the productions, a 16-bit 48 kHz WAV and a row each. Nothing here uploads, syncs,
 *     shares or publishes them; Export my data reads them (docs/EXPORT.md `ownSounds[]`);
 *   - a performed cue, which is a take, read from the production.
 * It also holds the one player that auditions a sound and plays the live listen's cues. Every device is passed
 * in, so js/sound.test.js runs this file against fakes.
 */
const SoundStore = (() => {
  'use strict';
  const C = PlaysCore;
  const S = SoundCore;
  const CACHE = 'ed-sounds-1';
  const MINE = 'sounds/mine/';
  const NAME_MAX = 60;

  const hex = (buf) => [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
  const bufferOf = (bytes) => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const muted = () => typeof location !== 'undefined' && new URLSearchParams(location.search).get('mute') === '1';

  /** The browser's own devices; the tests pass fakes. */
  function browserDevices() {
    return {
      cache: () => caches.open(CACHE),
      digest: async (bytes) => hex(await crypto.subtle.digest('SHA-256', bytes)),
      /** Any audio the browser decodes, at 48 kHz mono. */
      async decode(bytes) {
        const ctx = new OfflineAudioContext(1, 1, C.TAKE_RATE);
        const buf = await ctx.decodeAudioData(bytes.slice(0));
        const n = buf.length;
        const out = new Float32Array(n);
        for (let ch = 0; ch < buf.numberOfChannels; ch++) {
          const d = buf.getChannelData(ch);
          for (let i = 0; i < n; i++) out[i] += d[i] / buf.numberOfChannels;
        }
        return { samples: out, sampleRate: buf.sampleRate };
      },
      online: () => typeof navigator === 'undefined' || navigator.onLine !== false,
    };
  }

  /**
   * One store over the plays database's `backend` (PlayStore's). `api` is API.sounds; `devices` the cache,
   * digest and decoder.
   */
  function create({ backend, api = (typeof API !== 'undefined' ? API.sounds : null), devices = browserDevices() } = {}) {
    const st = {
      /** The pack: none (not configured), loading, ready, or error (configured, not reached). */
      pack: { status: 'none', manifest: null, url: null },
      cached: new Set(),
      loadingCats: new Map(),
      failedCats: new Set(),
      onChange: null,
    };
    const samples = new Map();
    let mineRows = null;
    const tell = () => { if (st.onChange) st.onChange(st); };

    /* ---- The pack ---- */

    st.loadPack = async () => {
      const url = api ? api.manifestURL() : null;
      if (!url) { st.pack = { status: 'none', manifest: null, url: null }; tell(); return st.pack; }
      if (st.pack.status === 'ready' && st.pack.url === url) return st.pack;
      st.pack = { status: 'loading', manifest: null, url };
      tell();
      try {
        const manifest = S.readManifest(await api.manifest(url));
        for (const r of manifest.refused) console.warn('sound pack: refused', r.id, r.why);
        st.pack = { status: 'ready', manifest, url };
        await st.refreshCached();
      } catch (e) {
        console.error('sound pack', e);
        st.pack = { status: 'error', manifest: null, url };
      }
      tell();
      return st.pack;
    };

    const fileURL = (cue) => new URL(cue.file, st.pack.url).href;
    const cuesOf = (catID) => (st.pack.manifest ? st.pack.manifest.cues.filter(c => c.category === catID) : []);
    st.cue = (id) => (st.pack.manifest ? st.pack.manifest.cues.find(c => c.id === id) || null : null);

    st.refreshCached = async () => {
      try {
        const cache = await devices.cache();
        st.cached = new Set((await cache.keys()).map(r => (typeof r === 'string' ? r : r.url)));
      } catch { st.cached = new Set(); }
    };
    st.isHere = (cue) => st.cached.has(fileURL(cue));
    /** A category: here (every file cached), loading (with the share done), failed, or missing. */
    st.categoryState = (catID) => {
      if (st.loadingCats.has(catID)) return { state: 'loading', done: st.loadingCats.get(catID) };
      const cues = cuesOf(catID);
      if (cues.length && cues.every(st.isHere)) return { state: 'here' };
      return { state: st.failedCats.has(catID) ? 'failed' : 'missing' };
    };

    async function fetchChecked(cue) {
      for (let attempt = 0; attempt < 2; attempt++) {
        const got = await api.file(st.pack.url, cue.file);
        if ((await devices.digest(got.bytes)) === cue.sha256) return got.bytes;
        console.warn('sound pack: checksum failed', cue.id, attempt ? 'again' : 'once');
      }
      throw new Error(`checksum ${cue.id}`);
    }

    /** Downloads a category's files (the person's press, or a render that needs them); true when all are here. */
    st.download = async (catID) => {
      if (st.pack.status !== 'ready' || st.loadingCats.has(catID)) return false;
      const cues = cuesOf(catID).filter(c => !st.isHere(c));
      st.failedCats.delete(catID);
      st.loadingCats.set(catID, 0);
      tell();
      try {
        const cache = await devices.cache();
        let n = 0;
        for (const cue of cues) {
          const bytes = await fetchChecked(cue);
          await cache.put(fileURL(cue), new Response(bytes, { headers: { 'content-type': 'audio/mp4' } }));
          st.cached.add(fileURL(cue));
          st.loadingCats.set(catID, ++n / cues.length);
          tell();
        }
        return true;
      } catch (e) {
        console.error('sound pack download', e);
        st.failedCats.add(catID);
        return false;
      } finally {
        st.loadingCats.delete(catID);
        tell();
      }
    };

    /** A cached pack file's samples at 48 kHz, checked against its sha256 again (a damaged copy is deleted). */
    st.cueSamples = async (cue) => {
      const key = `p:${cue.id}`;
      if (samples.has(key)) return samples.get(key);
      const cache = await devices.cache();
      const resp = await cache.match(fileURL(cue));
      if (!resp) throw new C.MixFailure('missingSounds', [cue.id]);
      const bytes = await resp.arrayBuffer();
      if ((await devices.digest(bytes)) !== cue.sha256) {
        await cache.delete(fileURL(cue));
        st.cached.delete(fileURL(cue));
        throw new Error(`checksum ${cue.id}`);
      }
      const got = (await devices.decode(bytes)).samples;
      samples.set(key, got);
      return got;
    };

    /* ---- Own sounds (§3.4): this device only ---- */

    st.mine = async () => {
      if (!mineRows) {
        const keys = (await backend.keys(MINE)).filter(k => k.endsWith('.json'));
        const rows = await Promise.all(keys.map(async k => { try { return JSON.parse(await backend.get(k)); } catch { return null; } }));
        mineRows = rows.filter(r => r && r.id).sort((a, b) => (b.created || '').localeCompare(a.created || ''));
      }
      return mineRows;
    };
    st.mineNow = () => mineRows || [];
    st.own = (id) => (mineRows || []).find(r => r.id === id) || null;

    /** Keeps a sound the person recorded or brought: `{ name, samples, sampleRate: 48000, from }`; its row. */
    st.saveOwn = async ({ name, samples: data, sampleRate, from = 'recorded' }) => {
      if (sampleRate !== C.TAKE_RATE) throw new Error('own sounds are kept at 48 kHz');
      if (!data.length) throw new Error('nothing to keep');
      const id = C.uuid();
      const wav = C.encodeWav(data, sampleRate, 16);
      const loudness = C.integratedLoudness(data, sampleRate);
      const row = {
        id, name: String(name || '').trim().slice(0, NAME_MAX) || 'My sound', created: new Date().toISOString(), from,
        frames: data.length, sampleRate, bytes: wav.byteLength, peak: C.samplePeak(data), loudness: loudness === null ? null : loudness,
      };
      await backend.putAll([[`${MINE}${id}.wav`, bufferOf(wav)], [`${MINE}${id}.json`, JSON.stringify(row)]]);
      await st.mine();
      mineRows = [row, ...mineRows];
      tell();
      return row;
    };
    st.renameOwn = async (id, name) => {
      const row = st.own(id);
      if (!row) return null;
      const next = { ...row, name: String(name || '').trim().slice(0, NAME_MAX) || row.name };
      await backend.put(`${MINE}${id}.json`, JSON.stringify(next));
      mineRows = mineRows.map(r => (r.id === id ? next : r));
      tell();
      return next;
    };
    st.removeOwn = async (id) => {
      await backend.remove(`${MINE}${id}.wav`);
      await backend.remove(`${MINE}${id}.json`);
      samples.delete(`o:${id}`);
      if (mineRows) mineRows = mineRows.filter(r => r.id !== id);
      tell();
    };
    st.ownSamples = async (id) => {
      const key = `o:${id}`;
      if (samples.has(key)) return samples.get(key);
      const raw = await backend.get(`${MINE}${id}.wav`);
      if (raw === null) throw new C.MixFailure('missingSounds', [id]);
      const got = C.decodeWav(raw).samples;
      samples.set(key, got);
      return got;
    };

    /** Export my data (docs/EXPORT.md): each own sound's row and its audio, so the export is a whole copy. */
    st.exportRows = async () => {
      const out = [];
      for (const r of await st.mine()) {
        const raw = await backend.get(`${MINE}${r.id}.wav`);
        let wav = null;
        if (raw !== null) {
          const b = new Uint8Array(raw);
          let s = '';
          for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
          wav = typeof btoa === 'function' ? btoa(s) : Buffer.from(b).toString('base64');
        }
        out.push({ id: r.id, name: r.name, created: r.created, from: r.from || null,
                   seconds: Math.round((r.frames / r.sampleRate) * 10) / 10, bytes: r.bytes, wav });
      }
      return out;
    };

    /* ---- What a sound is, wherever it comes from ---- */

    /** A sound's title, length (ms) and kind for the board, or `{ missing }` when this device lacks it. */
    st.describe = (src, p) => {
      if (src.pack) {
        const cue = st.cue(src.cue);
        if (!cue) return { title: src.cue, ms: 0, kind: 'effect', missing: st.pack.status === 'ready' ? 'removed' : 'pack' };
        return { title: cue.title, ms: cue.ms, kind: cue.kind, loop: cue.loop, cue, here: st.isHere(cue) };
      }
      if (src.own) {
        const row = st.own(src.own);
        if (!row) return { title: src.name || 'On another device', ms: 0, kind: 'effect', missing: 'own' };
        return { title: row.name, ms: Math.round((row.frames / row.sampleRate) * 1000), kind: 'effect', own: row };
      }
      if (src.take) {
        const t = p ? C.takeById(p, src.take) : null;
        const k = p && t ? p.takes.filter(x => x.cue && x.cue === t.cue).indexOf(t) + 1 : 0;
        if (!t) return { title: 'Your take', ms: 0, kind: 'effect', missing: 'take' };
        return { title: k ? `Your take ${k}` : 'Your take', ms: Math.round((t.frames / t.sampleRate) * 1000), kind: 'effect', take: t };
      }
      return { title: '', ms: 0, kind: 'effect', missing: 'unknown' };
    };

    /**
     * Before a render or a listen: the pack and own rows read, and (online, when `download` is set) the categories
     * a production's cues need downloaded. Returns the mix's resolver and loader and the names of what is missing.
     */
    st.prepare = async (p, { download = true } = {}) => {
      await st.mine();
      const used = S.sources(p);
      if (used.pack.length) {
        await st.loadPack();
        if (st.pack.status === 'ready' && download && devices.online()) {
          const cats = new Set(used.pack.map(id => st.cue(id)).filter(c => c && !st.isHere(c)).map(c => c.category));
          for (const cat of cats) await st.download(cat);
        }
      }
      const resolveSound = (src) => {
        if (src.pack) {
          const cue = st.cue(src.cue);
          if (!cue || !st.isHere(cue)) return null;
          return { frames: C.msFrames(cue.ms, C.TAKE_RATE), kind: cue.kind === 'music' ? 'music' : 'effect', loudness: cue.lufs, peak: cue.peak };
        }
        if (src.own) {
          const row = st.own(src.own);
          return row ? { frames: row.frames, kind: 'effect', loudness: row.loudness, peak: row.peak } : null;
        }
        return null;
      };
      const loadSound = async (x) => (x.src.pack ? st.cueSamples(st.cue(x.src.cue)) : st.ownSamples(x.src.own));
      const missing = [];
      for (const slot of (p.sound && p.sound.slots) || []) {
        if (slot.silent) continue;
        for (const x of slot.sounds || []) {
          if (!x.src || x.src.take) continue;
          if (!resolveSound(x.src)) missing.push({ id: x.id, title: x.src.own ? (x.src.name || null) : st.describe(x.src, p).title, own: !!x.src.own });
        }
      }
      return { resolveSound, loadSound, missing };
    };

    /** The samples a sound in a slot plays, for the live listen and audition; null when this device lacks it. */
    st.samplesOf = async (src, p, store) => {
      try {
        if (src.pack) { const cue = st.cue(src.cue); return cue && st.isHere(cue) ? await st.cueSamples(cue) : null; }
        if (src.own) return st.own(src.own) ? await st.ownSamples(src.own) : null;
        if (src.take) { const t = C.takeById(p, src.take); return t ? C.decodeWav(await store.readTake(p.id, t.file)).samples : null; }
      } catch (e) { console.error('sound', e); }
      return null;
    };

    return st;
  }

  /**
   * The one player for auditions and the live listen's cues (§3.2: audition plays only while nothing records).
   * `play(samples, opts)` resolves `done` at the end and gives `stop()` and `duck(on)`: the duck ramps the gain
   * down over the attack and back over the release, as the mix's envelope does.
   */
  function player() {
    let ctx = null;
    const live = new Set();
    const out = {
      /** Makes the context inside the person's press, so a later start is allowed to sound. */
      warm() { if (!ctx) ctx = new AudioContext(); ctx.resume().catch(() => {}); },
      async play(data, { gainDb = 0, loop = false, fadeInMs = 0, fadeOutMs = 0, lengthMs = null, duckDb = 0, loudness = null, peak = 0, lane = 'effects' } = {}) {
        if (!data || !data.length) return { done: Promise.resolve(), stop() {}, duck() {} };
        if (!ctx) ctx = new AudioContext();
        await ctx.resume();
        const D = C.SOUND_DEFAULTS;
        const level = (muted() ? 0 : 1) * C.gain(loudness, peak || 0, lane === 'music' ? D.musicLufs : D.effectsLufs) * Math.pow(10, gainDb / 20);
        const buffer = ctx.createBuffer(1, data.length, C.TAKE_RATE);
        buffer.getChannelData(0).set(data);
        const src = ctx.createBufferSource();
        src.buffer = buffer;
        src.loop = loop;
        const fade = ctx.createGain();
        const duck = ctx.createGain();
        const t0 = ctx.currentTime;
        const len = lengthMs !== null ? lengthMs / 1000 : (loop ? null : data.length / C.TAKE_RATE);
        fade.gain.setValueAtTime(fadeInMs ? 0 : level, t0);
        if (fadeInMs) fade.gain.linearRampToValueAtTime(level, t0 + fadeInMs / 1000);
        if (len !== null && fadeOutMs) { fade.gain.setValueAtTime(level, t0 + Math.max(0, len - fadeOutMs / 1000)); fade.gain.linearRampToValueAtTime(0, t0 + len); }
        src.connect(fade); fade.connect(duck); duck.connect(ctx.destination);
        let resolve;
        const done = new Promise((r) => { resolve = r; });
        const h = {
          done,
          stop() { try { src.stop(); } catch { /* ended */ } },
          duck(on) {
            if (!(duckDb < 0)) return;
            const now = ctx.currentTime;
            duck.gain.cancelScheduledValues(now);
            duck.gain.setValueAtTime(duck.gain.value, now);
            duck.gain.linearRampToValueAtTime(on ? Math.pow(10, duckDb / 20) : 1, now + (on ? D.attackMs : D.releaseMs) / 1000);
          },
        };
        src.onended = () => { live.delete(h); resolve(); };
        live.add(h);
        src.start(t0, 0, len !== null && !loop ? len : undefined);
        if (len !== null && loop) src.stop(t0 + len);
        return h;
      },
      stopAll() { for (const h of [...live]) h.stop(); },
      get playing() { return live.size > 0; },
    };
    return out;
  }

  /** A file the person brought, decoded at 48 kHz mono (§3.4: stored as the take format). */
  const decodeFile = (bytes) => browserDevices().decode(bytes);

  return { create, player, decodeFile, CACHE, MINE };
})();
if (typeof module !== 'undefined') module.exports = SoundStore;
