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
   * Naming a voice the browser names only by its locale (PLAYS-DESIGN §2.8 rule 12). A browser hands a page no
   * audio, so nothing is measured here: a voice with a name a person can choose by ("Samantha", "Microsoft Aria
   * Online (Natural)", "Google UK English Female") keeps it; a voice named only by its locale ("English United
   * States 2", "en-US") is composed from facts in Android's words (android/.../plays/VoiceLabels.kt): "Low, warm
   * · US" from the numbers Android measured once for Google's US voices when the voice's id carries their engine
   * code (Android Chrome's `en-us-x-sfg-local`), else "US voice". Android shows an engine code only until it has
   * measured a voice; the web never measures, so a code would stay for good and reads like a number (owner
   * 2026-11-23). Exact duplicates and voices left indistinguishable are listed once.
   */
  const TRAIT_WORDS = [['tone', ['warm', 'clear', 'bright']], ['range', ['even', 'varied', 'lively']], ['pace', ['quick', 'steady', 'unhurried']]];
  const SPLIT = 165;
  const SEED = {
    'en-us-x-iob-local': { f0: 193.5, range: 1.725, tone: 1752, pace: 4.40 },
    'en-us-x-iog-local': { f0: 230.8, range: 1.409, tone: 2067, pace: 4.22 },
    'en-us-x-iol-local': { f0: 140.4, range: 1.775, tone: 2244, pace: 4.24 },
    'en-us-x-iom-local': { f0: 136.4, range: 1.777, tone: 1931, pace: 4.46 },
    'en-us-x-sfg-local': { f0: 212.4, range: 1.381, tone: 1810, pace: 4.31 },
    'en-us-x-tpc-local': { f0: 157.9, range: 1.619, tone: 1898, pace: 4.66 },
    'en-us-x-tpd-local': { f0: 130.4, range: 1.570, tone: 1825, pace: 4.42 },
    'en-us-x-tpf-local': { f0: 210.5, range: 1.614, tone: 1701, pace: 4.69 },
  };

  const band = (f0) => f0 < 115 ? 'Deep' : f0 < 150 ? 'Low' : f0 < 180 ? 'Middle' : f0 < 220 ? 'High' : 'Very high';
  const tagOf = (lang) => String(lang || '').replace(/_/g, '-');
  const squash = (x) => String(x || '').toLowerCase().replace(/[^a-z]+/g, ' ').trim();
  const NUL = '\u0000';

  function displayName(type, code) {
    try { return new Intl.DisplayNames(['en-US'], { type }).of(code) || ''; } catch (e) { return ''; }
  }
  function partsOfTag(lang) {
    const [lc, ...rest] = tagOf(lang).split('-');
    return { lc, cc: (rest.find(x => /^[a-z]{2}$/i.test(x)) || '').toUpperCase() };
  }

  /** "US", "UK", else the region's English name ("Australia"); the language's name when the tag has no region. */
  function accentOf(lang) {
    const { lc, cc } = partsOfTag(lang);
    if (cc === 'US') return 'US';
    if (cc === 'GB') return 'UK';
    return cc ? (displayName('region', cc) || cc) : (displayName('language', lc) || tagOf(lang));
  }

  /** True when the voice's name says nothing but its locale: "English (United States) 2", "en-US", "United States". */
  function localeNamed(v) {
    const n = squash(v.name).replace(/ \d+$/, '');
    if (!n) return true;
    const { lc, cc } = partsOfTag(v.lang);
    const lang = squash(displayName('language', lc)), region = squash(cc && displayName('region', cc));
    const forms = new Set([squash(tagOf(v.lang)), squash(lc)]);
    if (lang) { forms.add(lang); if (region) forms.add(`${lang} ${region}`); }
    if (region) forms.add(region);
    if (cc === 'GB') { forms.add('english uk'); forms.add('english gb'); }
    if (cc === 'US') forms.add('english us');
    return forms.has(n);
  }

  const engineCode = (v) => { const m = /-x-([a-z0-9]+)/i.exec(`${v.voiceURI || ''} ${v.name || ''}`); return m ? m[1].toLowerCase() : ''; };
  const seedOf = (v) => { const m = /\ben-[a-z]{2}-x-[a-z0-9]+-local\b/i.exec(`${v.voiceURI || ''} ${v.name || ''}`); return m ? SEED[m[0].toLowerCase()] || null : null; };
  const push = (map, k, x) => { (map.get(k) || map.set(k, []).get(k)).push(x); };

  const minGap = (vals) => {
    const s = vals.slice().sort((a, b) => a - b);
    let m = Infinity;
    for (let i = 1; i < s.length; i++) m = Math.min(m, (s[i] - s[i - 1]) / s[i - 1]);
    return m === Infinity ? 0 : m;
  };

  /** Android's `name`: the trait that tells these voices apart best, then the next within each third. */
  function nameApart(items, left, words) {
    if (items.length < 2) return;
    let pick = null, gap = -1;
    for (const tr of left) { const g = minGap(items.map(x => x.t[tr[0]])); if (g > gap) { gap = g; pick = tr; } }
    const tied = items.every(x => ['f0', 'range', 'tone', 'pace'].every(k => x.t[k] === items[0].t[k]));
    if (!pick || tied) { items.forEach(x => push(words, x.id, `(${x.code})`)); return; }
    const sorted = items.slice().sort((a, b) => (a.t[pick[0]] - b.t[pick[0]]) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    const n = sorted.length, buckets = new Map();
    sorted.forEach((x, i) => push(buckets, n === 2 ? i * 2 : Math.floor(i * 3 / n), x));
    for (const [b, members] of buckets) {
      members.forEach(x => push(words, x.id, pick[1][b]));
      nameApart(members, left.filter(t => t !== pick), words);
    }
  }

  /**
   * The labels of the browser's voices (SpeechSynthesisVoice objects): { labels: Map(voiceURI-or-name to label),
   * voices: the ones kept, duplicates left out }. Pure: reads only each voice's name, lang and voiceURI.
   */
  function label(voices) {
    const seen = new Set(), kept = [];
    for (const v of voices) {
      const k = `${v.name}${NUL}${tagOf(v.lang).toLowerCase()}`;
      if (localeNamed(v) || !seen.has(k)) { seen.add(k); kept.push(v); }
    }
    const out = new Map(), idOf = (v) => v.voiceURI || v.name;
    const measured = [];
    for (const v of kept) {
      if (!localeNamed(v)) { out.set(idOf(v), v.name); continue; }
      const t = seedOf(v), code = engineCode(v), acc = accentOf(v.lang);
      if (t) measured.push({ id: idOf(v), acc, t, code: code || idOf(v) });
      else out.set(idOf(v), `${acc} voice`);
    }
    const groups = new Map();
    for (const m of measured) push(groups, `${m.acc}${NUL}${band(m.t.f0)}`, m);
    for (const [k, group] of groups) {
      const [acc, reg] = k.split(NUL), words = new Map();
      nameApart(group, TRAIT_WORDS, words);
      for (const m of group) {
        const w = words.get(m.id) || [];
        out.set(m.id, `${[reg, ...w.filter(x => x[0] !== '(')].join(', ')} · ${acc}${w.filter(x => x[0] === '(').map(x => ' ' + x).join('')}`);
      }
    }
    const taken = new Set();
    const keep = kept.filter(v => { const l = out.get(idOf(v)); if (taken.has(l)) return false; taken.add(l); return true; });
    return { labels: out, voices: keep };
  }

  /** Lower or higher where the voice's own numbers are known (the seed), else null: a fact, never a guess. */
  const registerOf = (v) => { const t = seedOf(v); return t ? (t.f0 < SPLIT ? 'lower' : 'higher') : null; };

  /**
   * The browser's castable voices, best first: local only (§5 rule 5), English, then by tier,
   * the person's own language, the system default, the name. Each as { engine, id, name, lang, tier, gender }.
   */
  function systemVoices(all, language) {
    const lang = tagOf(language || 'en-US').toLowerCase();
    const named = label((all || []).filter(v => v && v.localService && /^en([-_]|$)/i.test(v.lang || '')));
    return named.voices
      .map(v => ({ engine: 'system', id: v.voiceURI || v.name, name: named.labels.get(v.voiceURI || v.name), lang: v.lang, tier: tierOf(v.name),
                   gender: genderOf(v), register: registerOf(v), isDefault: !!v.default, raw: v }))
      .sort((a, b) => {
        if (a.tier !== b.tier) return b.tier - a.tier;
        const al = tagOf(a.lang).toLowerCase() === lang, bl = tagOf(b.lang).toLowerCase() === lang;
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
        const j = pool.findIndex(v => (v.gender || v.register) && (v.gender || v.register) !== last);
        if (j >= 0) k = j;
      }
      const v = pool.splice(k, 1)[0];
      if (v.gender || v.register) last = v.gender || v.register;
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

  return { label, accentOf, localeNamed, KEY, DEFAULTS_KEY, PITCHES, RATE, PITCH, NOT_READ, tierOf, genderOf, systemVoices, autoCast, resolve, normalize,
           load, save, forget, productionKey, scriptKey, caster,
           voiceKey, loadDefaults, saveDefaults, normalizeDefaults, usesVoice, ordered, poolOf, move };
})();
