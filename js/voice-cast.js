/**
 * The device voices' cast (PLAYS-DESIGN §2.8, Decision 076 S2): which voice reads which part,
 * one assignment for every player on this device (the recorder's cues, the listen-through,
 * the reader's Hear the cast), kept in this browser only and never synced (Q8).
 *
 * A part's casting is { engine, voice, name, rate, pitch }: engine 'system' (the browser's
 * own voices), 'kokoro' (downloadable voices, S6; none yet) or 'none' (Not read); voice is
 * the engine's identifier (a voiceURI here), never a language. Auto-cast reads only the
 * voices (their quality, the person's language, and a gender only when the platform reports
 * one for the VOICE); it never reads a part's name or the script (§2.8 rule 4).
 *
 * No speech API here: js/plays-voice.js is the only file that touches the synthesizer.
 */
const VoiceCast = (() => {
  'use strict';

  const KEY = 'ed.cast';
  const KEEP = 80;
  /** Voices repeat on a device with few of them; pitch tells two parts on one voice apart. */
  const PITCHES = [1.0, 0.86, 1.14, 0.93, 1.07];
  const RATE = { min: 0.5, max: 2, step: 0.1 };
  const PITCH = { min: 0.5, max: 1.5, step: 0.1 };
  const NOT_READ = Object.freeze({ engine: 'none', voice: null, name: null, rate: 1, pitch: 1 });
  const isSpeaking = (part) => typeof part === 'string' && part.startsWith('role:');

  /** The quality a voice's own name states: Premium 2; Enhanced, Natural or Neural 1; else 0. */
  function tierOf(name) {
    if (/\bpremium\b/i.test(name || '')) return 2;
    if (/\b(enhanced|natural|neural)\b/i.test(name || '')) return 1;
    return 0;
  }

  /** A reported voice gender, or null: the web reports none; 'unspecified' is none. */
  function genderOf(v) {
    const g = v && typeof v.gender === 'string' ? v.gender.toLowerCase() : '';
    return g === 'male' || g === 'female' ? g : null;
  }

  /**
   * The browser's castable voices, best first: local only (§5 rule 5), English, then by tier,
   * the person's own language, the system default, the name. Each as { engine, id, name, lang, tier, gender }.
   */
  function systemVoices(all, language) {
    const lang = (language || 'en-US').toLowerCase();
    return (all || []).filter(v => v && v.localService && /^en([-_]|$)/i.test(v.lang || ''))
      .map(v => ({ engine: 'system', id: v.voiceURI || v.name, name: v.name, lang: v.lang, tier: tierOf(v.name),
                   gender: genderOf(v), isDefault: !!v.default, raw: v }))
      .sort((a, b) => {
        if (a.tier !== b.tier) return b.tier - a.tier;
        const al = a.lang.toLowerCase() === lang, bl = b.lang.toLowerCase() === lang;
        if (al !== bl) return al ? -1 : 1;
        if (a.isDefault !== b.isDefault) return a.isDefault ? -1 : 1;
        return a.name < b.name ? -1 : a.name > b.name ? 1 : (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
      });
  }

  const entryOf = (v, pitch = 1) => ({ engine: v.engine, voice: v.id, name: v.name, rate: 1, pitch });

  /**
   * Auto-cast (§2.8 rule 4). `parts` in cast order (largest first: PlaysCore.castParts), `voices`
   * best first. Speaking parts take distinct voices, the best first; where voices report a
   * gender, each next part takes the best remaining voice of the other one. When voices run
   * out the list starts again at the next pitch. Directions and sound are Not read.
   * Reads nothing of a part but its place in the list.
   */
  function autoCast(parts, voices) {
    const out = {};
    let pool = [];
    let round = -1;
    let last = null;
    for (const part of parts) {
      const id = typeof part === 'string' ? part : part.id;
      if (!isSpeaking(id)) { out[id] = { ...NOT_READ }; continue; }
      if (!voices.length) continue;
      if (!pool.length) { pool = voices.slice(); round += 1; }
      let k = 0;
      if (last) {
        const j = pool.findIndex(v => v.gender && v.gender !== last);
        if (j >= 0) k = j;
      }
      const v = pool.splice(k, 1)[0];
      if (v.gender) last = v.gender;
      out[id] = entryOf(v, PITCHES[round % PITCHES.length]);
    }
    return out;
  }

  const clamp = (x, r, d) => {
    const n = Number(x);
    if (!Number.isFinite(n)) return d;
    return Math.round(Math.min(r.max, Math.max(r.min, n)) * 100) / 100;
  };
  function normalize(e) {
    if (!e || typeof e !== 'object') return null;
    const engine = ['system', 'kokoro', 'none'].includes(e.engine) ? e.engine : null;
    if (!engine) return null;
    if (engine === 'none') return { ...NOT_READ };
    if (typeof e.voice !== 'string' || !e.voice) return null;
    return { engine, voice: e.voice, name: typeof e.name === 'string' ? e.name : e.voice,
             rate: clamp(e.rate, RATE, 1), pitch: clamp(e.pitch, PITCH, 1) };
  }

  /**
   * How a part is read now: { read: false } (Not read, or no voice on this device), or
   * { read: true, voice, rate, pitch, missing } where `missing` names a cast voice this device
   * lacks, and `voice` is then the part's auto-cast voice (§2.8 rule 8).
   */
  function resolve(entry, partID, voices, auto) {
    const e = normalize(entry) || (auto && auto[partID]) || null;
    if (!e || e.engine === 'none') return { read: false, entry: e || { ...NOT_READ }, missing: null, none: !voices.length };
    if (!voices.length) return { read: false, entry: e, missing: null, none: true };
    const found = e.engine === 'system' ? voices.find(v => v.id === e.voice) : null;
    if (found) return { read: true, entry: e, voice: found, rate: e.rate, pitch: e.pitch, missing: null };
    const fb = (auto && auto[partID] && voices.find(v => v.id === auto[partID].voice)) || voices[0];
    const fe = (auto && auto[partID]) || entryOf(fb);
    return { read: true, entry: e, voice: fb, rate: e.rate, pitch: fe.pitch, missing: e.name || e.voice };
  }

  /* ---- Storage: this browser only, newest KEEP casts ---- */

  function defaultStorage() {
    try { return typeof localStorage !== 'undefined' ? localStorage : null; } catch { return null; }
  }
  function readAll(storage) {
    try { const v = JSON.parse((storage && storage.getItem(KEY)) || 'null'); return v && typeof v === 'object' ? v : {}; } catch { return {}; }
  }
  function writeAll(storage, all) {
    const keys = Object.keys(all);
    if (keys.length > KEEP) keys.sort((a, b) => (all[a].at || 0) - (all[b].at || 0)).slice(0, keys.length - KEEP).forEach(k => delete all[k]);
    try { if (storage) storage.setItem(KEY, JSON.stringify(all)); } catch { /* private window: the cast is forgotten, never wrong */ }
  }
  function load(key, storage = defaultStorage()) {
    const row = readAll(storage)[key];
    return row && row.parts && typeof row.parts === 'object' ? row.parts : null;
  }
  function save(key, parts, storage = defaultStorage()) {
    const all = readAll(storage);
    all[key] = { parts, at: Date.now() };
    writeAll(storage, all);
  }
  function forget(key, storage = defaultStorage()) {
    const all = readAll(storage);
    if (all[key]) { delete all[key]; writeAll(storage, all); }
  }

  const productionKey = (id) => `p:${id}`;
  const scriptKey = (id) => `s:${id}`;

  /**
   * The one cast for a production (or a play): every player on this device reads parts
   * through this. `parts` in cast order; `voices()` the device's voices now (best first);
   * `seed` a key to start from (the play's cast) when this one has never been made.
   */
  function caster({ key, parts, voices, seed = null, storage = defaultStorage() }) {
    const ids = parts.map(p => (typeof p === 'string' ? p : p.id));
    const list = () => voices() || [];
    function stored() { return load(key, storage) || (seed && load(seed, storage)) || null; }
    /** Fills any part without a casting by auto-cast, once there is a voice to cast; keeps every choice made. */
    function ensure() {
      const v = list();
      const have = load(key, storage);
      const base = have || (seed && load(seed, storage)) || {};
      if (!v.length) return base;
      const auto = autoCast(parts, v);
      let changed = !have;
      const next = { ...base };
      for (const id of ids) if (!normalize(next[id]) && auto[id]) { next[id] = auto[id]; changed = true; }
      if (changed) save(key, next, storage);
      return next;
    }
    const api = {
      key,
      parts: ids,
      voices: list,
      /** How `part` is read now (resolve). */
      resolve(part) {
        const v = list();
        const cast = ensure();
        return resolve(cast[part], part, v, autoCast(parts, v));
      },
      entry(part) { return normalize(ensure()[part]) || null; },
      set(part, change) {
        const cast = ensure();
        const before = normalize(cast[part]) || { ...NOT_READ };
        const next = normalize({ ...before, ...change });
        if (!next) return;
        save(key, { ...cast, [part]: next }, storage);
      },
      /** Recast all: auto-cast again over the voices on this device now. */
      recast() {
        const v = list();
        if (v.length) save(key, autoCast(parts, v), storage);
      },
      stored,
    };
    return api;
  }

  return { KEY, PITCHES, RATE, PITCH, NOT_READ, tierOf, genderOf, systemVoices, autoCast, resolve, normalize,
           load, save, forget, productionKey, scriptKey, caster };
})();
