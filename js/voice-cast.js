/**
 * The device voices' cast (PLAYS-DESIGN §2.8, Decision 076 S2): which voice reads which part,
 * one assignment for every player on this device (the recorder's cues, the listen-through,
 * the reader's Hear the cast), kept in this browser only and never synced (Q8).
 *
 * A part's casting is { engine, voice, name, rate, pitch }: engine 'system' (the browser's
 * own voices), 'kokoro' (the downloaded voices, S6) or 'none' (Not read); voice is
 * the engine's identifier (a voiceURI here), never a language. Auto-cast reads only the
 * voices (their quality, the person's language, and a gender only when the platform reports
 * one for the VOICE); it never reads a part's name or the script (§2.8 rule 4).
 *
 * Only a person's choices are kept (Decision 086). A part nobody chose reads its Default: auto-cast
 * over the device's voice defaults (Settings > Voices: the order, the voices left out, a speed),
 * worked out at each read, so a download or a reorder there reaches every untouched part at once.
 *
 * No speech API here: js/plays-voice.js is the only file that touches the synthesizer.
 */
const VoiceCast = (() => {
  'use strict';

  const KEY = 'ed.cast';
  const DEFAULTS_KEY = 'ed.voices';
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

  const entryOf = (v, pitch = 1, rate = 1) => ({ engine: v.engine, voice: v.id, name: v.name, rate, pitch });

  /**
   * Auto-cast (§2.8 rule 4). `parts` in cast order (largest first: PlaysCore.castParts), `voices`
   * best first. Speaking parts take distinct voices, the best first; where voices report a
   * gender, each next part takes the best remaining voice of the other one. When voices run
   * out the list starts again at the next pitch. Directions and sound are Not read.
   * Reads nothing of a part but its place in the list.
   */
  function autoCast(parts, voices, rate = 1) {
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
      out[id] = entryOf(v, PITCHES[round % PITCHES.length], rate);
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
    const found = voices.find(v => v.engine === e.engine && v.id === e.voice) || null;
    if (found) return { read: true, entry: e, voice: found, rate: e.rate, pitch: e.pitch, missing: null };
    const fb = (auto && auto[partID] && voices.find(v => v.id === auto[partID].voice)) || voices[0];
    const fe = (auto && auto[partID]) || entryOf(fb);
    return { read: true, entry: e, voice: fb, rate: e.rate, pitch: fe.pitch, missing: e.name || e.voice };
  }

  function defaultStorage() {
    try { return typeof localStorage !== 'undefined' ? localStorage : null; } catch { return null; }
  }

  /* ---- The device's voice defaults (Settings > Voices, Decision 086): this browser only ---- */

  const voiceKey = (v) => `${v.engine}:${v.id}`;
  const EMPTY_DEFAULTS = Object.freeze({ order: [], off: {}, rate: 1 });

  function normalizeDefaults(d) {
    if (!d || typeof d !== 'object') return { order: [], off: {}, rate: 1 };
    const order = Array.isArray(d.order) ? d.order.filter(k => typeof k === 'string').slice(0, 400) : [];
    const off = {};
    if (d.off && typeof d.off === 'object') for (const [k, v] of Object.entries(d.off)) if (typeof v === 'boolean') off[k] = v;
    return { order, off, rate: clamp(d.rate, RATE, 1) };
  }
  function loadDefaults(storage = defaultStorage()) {
    try { return normalizeDefaults(JSON.parse((storage && storage.getItem(DEFAULTS_KEY)) || 'null')); } catch { return normalizeDefaults(null); }
  }
  function saveDefaults(d, storage = defaultStorage()) {
    try { if (storage) storage.setItem(DEFAULTS_KEY, JSON.stringify(normalizeDefaults(d))); } catch { /* private window: forgotten, never wrong */ }
  }

  /** Whether the defaults use a voice: the person's tick, else the voice's own default (Kokoro's lowest grades start out). */
  const usesVoice = (v, d = EMPTY_DEFAULTS) => (Object.prototype.hasOwnProperty.call(d.off, voiceKey(v)) ? !d.off[voiceKey(v)] : !v.offByDefault);

  /**
   * Every voice in the defaults' order: the downloaded (Kokoro) voices before the device's own, inside
   * each engine the person's order, then the rest best first as `voices` gave them. Nothing left out.
   */
  function ordered(voices, d = EMPTY_DEFAULTS) {
    const at = new Map(d.order.map((k, i) => [k, i]));
    const rank = (v) => (at.has(voiceKey(v)) ? at.get(voiceKey(v)) : Infinity);
    const engineRank = (v) => (v.engine === 'kokoro' ? 0 : 1);
    return (voices || []).map((v, i) => ({ v, i }))
      .sort((a, b) => (engineRank(a.v) - engineRank(b.v)) || (rank(a.v) - rank(b.v)) || (a.i - b.i))
      .map(x => x.v);
  }

  /** The auto-cast pool: `ordered`, less the voices the defaults leave out; never empty while a voice exists. */
  function poolOf(voices, d = EMPTY_DEFAULTS) {
    const all = ordered(voices, d);
    const used = all.filter(v => usesVoice(v, d));
    return used.length ? used : all;
  }

  /** The defaults with `voice` moved one place up (-1) or down (+1) among its engine's voices. */
  function move(voices, d, voice, by) {
    const list = ordered(voices, d).filter(v => v.engine === voice.engine);
    const i = list.findIndex(v => voiceKey(v) === voiceKey(voice));
    const j = i + by;
    if (i < 0 || j < 0 || j >= list.length) return d;
    [list[i], list[j]] = [list[j], list[i]];
    const keys = list.map(voiceKey);
    return { ...d, order: [...keys, ...d.order.filter(k => !keys.includes(k))] };
  }

  /* ---- Storage: this browser only, newest KEEP casts ---- */

  function readAll(storage) {
    try { const v = JSON.parse((storage && storage.getItem(KEY)) || 'null'); return v && typeof v === 'object' ? v : {}; } catch { return {}; }
  }
  function writeAll(storage, all) {
    const keys = Object.keys(all);
    if (keys.length > KEEP) keys.sort((a, b) => (all[a].at || 0) - (all[b].at || 0)).slice(0, keys.length - KEEP).forEach(k => delete all[k]);
    try { if (storage) storage.setItem(KEY, JSON.stringify(all)); } catch { /* private window: the cast is forgotten, never wrong */ }
  }
  /** A cast's chosen parts. Rows from before Decision 086 (no `v`) wrote auto-cast in as if chosen: not choices. */
  function load(key, storage = defaultStorage()) {
    const row = readAll(storage)[key];
    return row && row.v === 2 && row.parts && typeof row.parts === 'object' ? row.parts : null;
  }
  function save(key, parts, storage = defaultStorage()) {
    const all = readAll(storage);
    all[key] = { v: 2, parts, at: Date.now() };
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
   * `seed` a key to start from (the play's cast) when this one has never been made;
   * `defaults()` the device's voice defaults (Settings > Voices).
   */
  function caster({ key, parts, voices, seed = null, storage = defaultStorage(), defaults = () => loadDefaults(storage) }) {
    const ids = parts.map(p => (typeof p === 'string' ? p : p.id));
    const list = () => voices() || [];
    const chosen = () => load(key, storage) || (seed && load(seed, storage)) || {};
    /** Every part's Default now: auto-cast over the defaults' pool, at the defaults' speed. */
    function auto() {
      const d = defaults() || EMPTY_DEFAULTS;
      return autoCast(parts, poolOf(list(), d), d.rate || 1);
    }
    const api = {
      key,
      parts: ids,
      voices: list,
      defaults: () => defaults() || EMPTY_DEFAULTS,
      /** How `part` is read now (resolve), and whether it is its Default (nobody chose). */
      resolve(part) {
        const c = normalize(chosen()[part]);
        return { ...resolve(c, part, list(), auto()), isDefault: !c };
      },
      /** The part's casting now: the choice, else its Default. */
      entry(part) { return normalize(chosen()[part]) || auto()[part] || null; },
      /** The person's own choice for `part`, or null when it reads its Default. */
      choice(part) { return normalize(chosen()[part]); },
      /** What the part's Default reads now, chosen or not. */
      defaultEntry(part) { return auto()[part] || null; },
      set(part, change) {
        const c = chosen();
        const before = normalize(c[part]) || auto()[part] || { ...NOT_READ };
        const next = normalize({ ...before, ...change });
        if (!next) return;
        save(key, { ...c, [part]: next }, storage);
      },
      /** Back to the Default: the part's choice is dropped. */
      reset(part) {
        const c = { ...chosen() };
        if (!(part in c)) return;
        delete c[part];
        save(key, c, storage);
      },
      /** Recast all: every part back to its Default. */
      recast() { save(key, {}, storage); },
      stored: () => load(key, storage) || (seed && load(seed, storage)) || null,
    };
    return api;
  }

  return { KEY, DEFAULTS_KEY, PITCHES, RATE, PITCH, NOT_READ, tierOf, genderOf, systemVoices, autoCast, resolve, normalize,
           load, save, forget, productionKey, scriptKey, caster,
           voiceKey, loadDefaults, saveDefaults, normalizeDefaults, usesVoice, ordered, poolOf, move };
})();
