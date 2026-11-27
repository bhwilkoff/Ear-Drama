/**
 * The Sound part without a DOM (B32 §3, WEB-DESIGN §4.16 item 14a; Decision 091 on the mix): the slots a
 * script offers (its cue rows, and any line a person adds a sound to), the edits a board makes to the
 * production's `sound` block, the pack manifest reader with its rights gate, search over the pack, the cast
 * sheet's summaries, and the cue schedule the live listen plays. Nothing here fills a slot: a slot opens
 * empty, and only the person's act puts a sound in it (§3.1 item 4). Tests: js/sound.test.js.
 */
const SoundCore = (() => {
  'use strict';
  const C = PlaysCore;
  const D = C.SOUND_DEFAULTS;

  const PLACEMENTS = ['before', 'under', 'after', 'bed'];
  const PLACEMENT_LABEL = { before: 'Before', under: 'Under', after: 'After', bed: 'Bed' };
  const FADES_MS = [0, 200, 500, 1000, 2000];
  const BED_FADE_IN_MS = 1500;
  const BED_FADE_OUT_MS = 2000;
  const START_STEP_MS = 100;
  /** The rights gate (B32 §5.2): the only licenses a pack row may carry, and hosts never taken from. */
  const LICENSES = Object.freeze({ 'CC0-1.0': 'CC0', 'PDM-1.0': 'Public domain', 'US-pre-1926': 'Public domain' });
  const REFUSED_HOSTS = ['freesound.org', 'sonniss.com', 'bbcrewind.co.uk', 'sound-effects.bbcrewind.co.uk'];
  /** Own sounds (§3.4): a recorded one up to 30 s; a brought file up to 10 minutes and 50 MB. */
  const OWN_RECORD_MAX_S = 30;
  const OWN_FILE_MAX_S = 600;
  const OWN_FILE_MAX_BYTES = 50 * 1024 * 1024;

  const num = new Intl.NumberFormat('en-US');
  const lineIndex = (script) => new Map(script.lines.map((l, i) => [l.id, i]));

  /* ---- Slots ---- */

  const blockOf = (p) => (p.sound && typeof p.sound === 'object' ? p.sound : null);
  const recordSlots = (p) => { const b = blockOf(p); return b && Array.isArray(b.slots) ? b.slots : []; };
  const pieceOrder = (piece) => (piece === null || piece === undefined ? -1 : piece);

  /**
   * Every slot the Sound part shows, in script order: each cue row (with its record slot once touched)
   * and every added slot. `key` is the record id when there is one, else the cue row's place.
   */
  function slotsOf(script, p) {
    const at = lineIndex(script);
    const rec = recordSlots(p);
    const used = new Set();
    const out = [];
    for (const row of C.cueRows(script)) {
      const s = rec.find(x => !x.added && x.line === row.line && (x.piece ?? null) === row.piece);
      if (s) used.add(s.id);
      out.push(view(row.line, row.piece, false, row.text, s));
    }
    for (const s of rec) {
      if (used.has(s.id) || !at.has(s.line)) continue;
      const line = script.lines[at.get(s.line)];
      const text = s.piece !== null && s.piece !== undefined && line.parts && line.parts[s.piece] ? C.pieceText(line.parts[s.piece]) : '';
      out.push(view(s.line, s.piece ?? null, !!s.added, text, s));
    }
    out.sort((a, b) => (at.get(a.line) - at.get(b.line)) || ((a.added ? 1e9 : pieceOrder(a.piece)) - (b.added ? 1e9 : pieceOrder(b.piece))));
    return out;
  }
  function view(line, piece, added, text, s) {
    return {
      key: s ? s.id : `${line}:${piece === null ? '' : piece}`, id: s ? s.id : null, line, piece, added, text,
      silent: !!(s && s.silent), sounds: s && Array.isArray(s.sounds) ? s.sounds : [],
    };
  }

  function emptyBlock() {
    return { v: C.SOUND_VERSION, lanes: { effects: { duckDb: D.effectsDuckDb }, music: { duckDb: D.musicDuckDb } }, slots: [] };
  }
  function withBlock(p) {
    const n = C.clone(p);
    if (!blockOf(n)) n.sound = emptyBlock();
    if (!Array.isArray(n.sound.slots)) n.sound.slots = [];
    return n;
  }
  const changed = (n) => { n.listenedThrough = false; return n; };

  /** The production with the slot in its record; `{ production, id }`. A cue row's slot is written on first touch. */
  function ensure(p, slot) {
    if (slot.id && recordSlots(p).some(s => s.id === slot.id)) return { production: p, id: slot.id };
    const n = withBlock(p);
    const id = C.uuid();
    n.sound.slots.push({ id, line: slot.line, piece: slot.piece ?? null, added: !!slot.added, silent: false, sounds: [] });
    return { production: n, id };
  }

  /** Add a sound here (§3.1 item 3): a slot at the line's end, or the one already there. */
  function addSlot(p, lineID) {
    const there = recordSlots(p).find(s => s.added && s.line === lineID);
    if (there) return { production: p, id: there.id };
    return ensure(p, { line: lineID, piece: null, added: true });
  }

  function editSlot(p, slotID, fn) {
    const n = withBlock(p);
    const s = n.sound.slots.find(x => x.id === slotID);
    if (!s) return p;
    fn(s);
    return changed(n);
  }

  /** Leave silent marks an empty slot done (§3.1 item 4); a slot holding a sound is never silent. */
  function setSilent(p, slotID, on) {
    return editSlot(p, slotID, (s) => { if (!on || !(s.sounds || []).length) s.silent = !!on; });
  }

  /**
   * Where a sound in a cue inside a speech starts by default (§3.3): Before a cue printed ahead of every
   * said word, After one printed behind them all, else Under, at the share of the said words before it.
   */
  function defaultPlacement(script, slot) {
    const line = script.lines.find(l => l.id === slot.line);
    if (!line || line.kind !== 'speech' || slot.piece === null || slot.piece === undefined || slot.added) return { at: 'after', share: 0 };
    const words = (pc) => (C.pieceKind(pc) === 'say' ? (C.pieceText(pc).match(/\S+/g) || []).length : 0);
    const total = line.parts.reduce((n, pc) => n + words(pc), 0);
    const before = line.parts.slice(0, slot.piece).reduce((n, pc) => n + words(pc), 0);
    if (!total || before === 0) return { at: 'before', share: 0 };
    if (before >= total) return { at: 'after', share: 1 };
    return { at: 'under', share: before / total };
  }

  /**
   * Adds a sound to a slot, as the person chose it. `cue` is what the source says of itself ({ kind, loop }),
   * `take` the anchor line's chosen take when there is one (an Under start is its share of the take's length).
   */
  function addSound(p, script, slotID, src, { kind = 'effect', take = null } = {}) {
    const slot = recordSlots(p).find(s => s.id === slotID);
    if (!slot) return { production: p, id: null };
    const id = C.uuid();
    const bed = kind === 'music' || kind === 'ambience';
    const def = defaultPlacement(script, slot);
    const at = bed && def.at !== 'under' ? 'bed' : def.at;
    const startMs = at === 'under' && take ? Math.round((def.share * take.frames * 1000) / take.sampleRate / START_STEP_MS) * START_STEP_MS : 0;
    const sound = { id, src: C.clone(src), at, startMs, gainDb: 0, fadeInMs: 0, fadeOutMs: 0, loop: false, duckDb: null };
    if (at === 'bed') Object.assign(sound, { until: slot.line, fadeInMs: BED_FADE_IN_MS, fadeOutMs: BED_FADE_OUT_MS, loop: true });
    return { production: editSlot(p, slotID, (s) => { s.silent = false; s.sounds = [...(s.sounds || []), sound]; }), id };
  }

  const nearest = (v, list) => list.reduce((b, x) => (Math.abs(x - v) < Math.abs(b - v) ? x : b), list[0]);

  /** One sound's settings changed, each held to what the board offers (§3.2 item 2). */
  function updateSound(p, slotID, soundID, patch) {
    return editSlot(p, slotID, (s) => {
      const x = (s.sounds || []).find(y => y.id === soundID);
      if (!x) return;
      if (patch.at && PLACEMENTS.includes(patch.at) && patch.at !== x.at) {
        const was = x.at;
        x.at = patch.at;
        if (patch.at === 'bed') Object.assign(x, { until: x.until || s.line, loop: true, fadeInMs: BED_FADE_IN_MS, fadeOutMs: BED_FADE_OUT_MS });
        else {
          delete x.until;
          if (was === 'bed') Object.assign(x, { loop: false, fadeInMs: 0, fadeOutMs: 0 });
          if (patch.at !== 'under') x.loop = false;
        }
      }
      if (typeof patch.startMs === 'number') x.startMs = Math.max(D.startMinMs, Math.round(patch.startMs / START_STEP_MS) * START_STEP_MS);
      if (typeof patch.gainDb === 'number') x.gainDb = Math.min(D.gainMaxDb, Math.max(D.gainMinDb, Math.round(patch.gainDb)));
      if (typeof patch.fadeInMs === 'number') x.fadeInMs = nearest(patch.fadeInMs, x.at === 'bed' ? [...FADES_MS, BED_FADE_IN_MS] : FADES_MS);
      if (typeof patch.fadeOutMs === 'number') x.fadeOutMs = nearest(patch.fadeOutMs, FADES_MS);
      if (typeof patch.loop === 'boolean' && (x.at === 'under' || x.at === 'bed')) x.loop = patch.loop;
      if ('duckDb' in patch) x.duckDb = patch.duckDb === null ? null : Math.min(0, Math.max(-60, Math.round(patch.duckDb)));
      if (typeof patch.until === 'string' && x.at === 'bed') x.until = patch.until;
    });
  }

  function removeSound(p, slotID, soundID) {
    return editSlot(p, slotID, (s) => { s.sounds = (s.sounds || []).filter(x => x.id !== soundID); });
  }

  /** Record slots that hold nothing are dropped (an added slot is removed when left empty, §3.1 item 3); `keep` stays. */
  function prune(p, keep = null) {
    const rec = recordSlots(p);
    const gone = rec.filter(s => s.id !== keep && !s.silent && !(s.sounds || []).length);
    if (!gone.length) return p;
    const n = C.clone(p);
    n.sound.slots = rec.filter(s => !gone.includes(s)).map(s => C.clone(s));
    if (!n.sound.slots.length) delete n.sound;
    return n;
  }

  /**
   * A performed cue joins the production (B32 §3.1 item 6, round 3: a take like any line): kept as a take on
   * the slot's line with `cue` naming the slot, never a line's chosen take, and placed in the slot.
   */
  function addPerformed(p, script, slotID, take) {
    const n = C.clone(p);
    n.takes.push({ ...C.clone(take), part: C.SOUND, cue: slotID });
    return addSound(n, script, slotID, { take: take.id }, { kind: 'effect' }).production;
  }

  /* ---- What the cast sheet and the dock say ---- */

  function summary(script, p) {
    const slots = slotsOf(script, p);
    const cues = slots.filter(s => !s.added);
    const sounds = slots.flatMap(s => s.sounds);
    return {
      cues: cues.length,
      chosen: cues.filter(s => s.sounds.length).length,
      silent: cues.filter(s => s.silent).length,
      added: slots.filter(s => s.added && s.sounds.length).length,
      beds: sounds.filter(x => x.at === 'bed').length,
      sounds: sounds.length,
    };
  }

  /** The Sound row's words on the cast sheet (§3.1 item 1). */
  function partLine(script, p, taken) {
    const m = summary(script, p);
    const beds = m.beds ? ` · ${m.beds === 1 ? '1 bed' : `${num.format(m.beds)} beds`}` : '';
    if (!m.cues) return m.sounds ? `${m.sounds === 1 ? '1 sound' : `${num.format(m.sounds)} sounds`}${beds}` : 'Add sounds';
    const cues = m.cues === 1 ? '1 cue' : `${num.format(m.cues)} cues`;
    if (!taken && !m.sounds) return `${cues} · none chosen`;
    return `${num.format(m.chosen)} of ${cues}${beds}`;
  }

  /** Stage directions read by a person (§2 item 3): "6 of 22 recorded · the rest silent". */
  function directionsLine(script, p) {
    const lines = C.linesFor(script, C.DIRECTIONS);
    const kept = lines.filter(l => C.usableTake(p, l.id)).length;
    const of = `${num.format(kept)} of ${num.format(lines.length)} recorded`;
    return kept < lines.length ? `${of} · the rest silent` : of;
  }

  const placementWords = (x) => (x.at === 'bed' ? 'Bed' : PLACEMENT_LABEL[x.at] || '');

  /** "after the line · +0.0 s", the sound's place in words (§3.2 item 2). */
  function placeLine(x, untilLabel = null) {
    const start = `${x.startMs < 0 ? '−' : '+'}${(Math.abs(x.startMs || 0) / 1000).toFixed(1)} s`;
    if (x.at === 'bed') return untilLabel ? `bed to ${untilLabel}` : 'bed';
    return `${{ before: 'before the line', under: 'under the line', after: 'after the line' }[x.at]} · ${start}`;
  }

  const clock = (ms) => { const s = Math.round((ms || 0) / 1000); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };

  /* ---- The pack (B32 §5.2) ---- */

  const host = (u) => { try { return new URL(u).hostname.toLowerCase(); } catch { return ''; } };
  const httpURL = (u) => typeof u === 'string' && /^https?:\/\//i.test(u) && !!host(u);
  const refusedHost = (u) => { const h = host(u); return REFUSED_HOSTS.some(r => h === r || h.endsWith(`.${r}`)); };

  /**
   * Reads `sounds.json`: the categories and every cue that passes the rights gate. A row whose license is not
   * CC0-1.0, PDM-1.0 or US-pre-1926, that lacks an evidence URL or a checked date, comes from a refused host,
   * or lacks its file, length or checksum, is never listed; `refused` names each with why. Throws on a format
   * this client does not read.
   */
  function readManifest(json) {
    if (!json || typeof json !== 'object') throw new Error('manifest: not an object');
    if (json.format !== 1) throw new Error(`manifest: format ${json.format}`);
    if (typeof json.pack !== 'string' || !json.pack) throw new Error('manifest: no pack');
    const categories = (Array.isArray(json.categories) ? json.categories : [])
      .filter(c => c && typeof c.id === 'string' && typeof c.title === 'string')
      .map(c => ({ id: c.id, title: c.title, bytes: Number(c.bytes) || 0 }));
    const cats = new Set(categories.map(c => c.id));
    const cues = [];
    const refused = [];
    const seen = new Set();
    for (const c of Array.isArray(json.cues) ? json.cues : []) {
      const why = refusal(c, cats, seen);
      if (why) { refused.push({ id: c && c.id ? String(c.id) : null, why }); continue; }
      seen.add(c.id);
      cues.push({
        id: c.id, title: c.title, category: c.category, tags: (c.tags || []).map(t => String(t).toLowerCase()),
        kind: ['effect', 'ambience', 'music'].includes(c.kind) ? c.kind : 'effect', ms: c.ms, loop: !!c.loop,
        file: c.file, bytes: Number(c.bytes) || 0, sha256: String(c.sha256).toLowerCase(),
        lufs: typeof c.lufs === 'number' ? c.lufs : null, peak: typeof c.peak === 'number' ? c.peak : null,
        source: { name: c.source.name, page: c.source.page, file: c.source.file || null, maker: c.source.maker || null },
        license: { id: c.license.id, url: c.license.url || null, evidence: c.license.evidence, checked: c.license.checked },
      });
    }
    return { pack: json.pack, built: json.built || null, categories: categories.filter(c => cues.some(x => x.category === c.id)), cues, refused };
  }
  function refusal(c, cats, seen) {
    if (!c || typeof c !== 'object' || typeof c.id !== 'string' || !c.id) return 'no id';
    if (seen.has(c.id)) return 'a second row with this id';
    if (typeof c.title !== 'string' || !c.title.trim()) return 'no title';
    if (!cats.has(c.category)) return 'no such category';
    const lic = c.license || {};
    if (!Object.prototype.hasOwnProperty.call(LICENSES, lic.id)) return `license ${lic.id || 'none'}`;
    if (!httpURL(lic.evidence)) return 'no evidence';
    if (typeof lic.checked !== 'string' || !/^\d{4}-\d{2}-\d{2}/.test(lic.checked)) return 'no checked date';
    const src = c.source || {};
    if (typeof src.name !== 'string' || !src.name || !httpURL(src.page)) return 'no source page';
    if ([src.page, src.file, lic.evidence].some(u => u && refusedHost(u))) return `refused host ${host(src.page)}`;
    if (typeof c.file !== 'string' || !c.file || /^\/|\.\./.test(c.file)) return 'no file';
    if (typeof c.sha256 !== 'string' || !/^[0-9a-f]{64}$/i.test(c.sha256)) return 'no checksum';
    if (!(typeof c.ms === 'number' && c.ms > 0)) return 'no length';
    return null;
  }

  const licenseLabel = (cue) => LICENSES[cue.license.id] || '';
  /** "0:06 · OpenGameArt · CC0", or "0:38 loop · ..." (§3.2 item 5). */
  const cueLine = (cue) => `${clock(cue.ms)}${cue.loop ? ' loop' : ''} · ${cue.source.name} · ${licenseLabel(cue)}`;
  const megabytes = (bytes) => `${(bytes / 1048576).toFixed(1)} MB`;

  const fold = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const wordsOf = (s) => fold(s).match(/[a-z0-9]+/g) || [];

  /** The search field's first words (§3.2 item 3): the first word of the cue that is a tag in the pack, else empty. */
  function seedQuery(text, cues) {
    const tags = new Set(cues.flatMap(c => c.tags));
    for (const w of wordsOf(text)) {
      if (tags.has(w)) return w;
      const one = w.replace(/(?:es|s)$/, '');
      if (one !== w && tags.has(one)) return one;
      if (w.endsWith('s') && tags.has(w.slice(0, -1))) return w.slice(0, -1);
    }
    return '';
  }

  /** Cues whose title or tags hold every word of the query (a word's start), in the pack's order; in one category when given. */
  function search(cues, query, category = null) {
    const q = wordsOf(query);
    return cues.filter(c => (!category || c.category === category) && q.every(w => {
      const have = [...wordsOf(c.title), ...c.tags.flatMap(wordsOf)];
      return have.some(h => h.startsWith(w) || (w.length > 3 && w.endsWith('s') && h.startsWith(w.slice(0, -1))));
    }));
  }
  /** Own sounds by name, the same way. */
  const searchMine = (mine, query) => { const q = wordsOf(query); return mine.filter(m => q.every(w => wordsOf(m.name).some(h => h.startsWith(w)))); };

  /** The sources a block names, by kind; `withoutOwn` is the block a published play may carry (§3.4 item 3). */
  function sources(p) {
    const out = { pack: [], own: [], take: [] };
    for (const s of recordSlots(p)) for (const x of s.sounds || []) {
      if (!x.src) continue;
      if (x.src.pack) out.pack.push(x.src.cue); else if (x.src.own) out.own.push(x.src.own); else if (x.src.take) out.take.push(x.src.take);
    }
    return out;
  }
  function withoutOwn(block) {
    if (!block) return null;
    const n = C.clone(block);
    n.slots = (n.slots || []).map(s => ({ ...s, sounds: (s.sounds || []).filter(x => !(x.src && x.src.own)) }))
      .filter(s => s.silent || s.sounds.length);
    return n;
  }

  /* ---- The live listen (§4.4: close, not sample-exact) ---- */

  /**
   * For a listen plan (PlaysCore.listenPlan), which sounds play at each entry: `before` its words (the line
   * waits for them), `under` and `bed` from its start, `after` it (the next entry waits), and the beds that
   * end with it (`stop`). A slot on a line the plan skips (a silent direction) plays with the next entry.
   */
  function listenCues(script, p, plan) {
    const at = lineIndex(script);
    const out = plan.map(() => ({ before: [], under: [], after: [], stop: [] }));
    if (!plan.length) return out;
    const entryAt = plan.map(e => at.get(e.lineID));
    const entryFor = (lineID) => { const k = at.get(lineID); const i = entryAt.findIndex(x => x >= k); return i; };
    const lastFor = (lineID) => { const k = at.get(lineID); let j = -1; entryAt.forEach((x, i) => { if (x <= k) j = i; }); return j; };
    let readable;
    try { readable = C.readSound(p.sound); } catch { readable = null; }
    if (!readable) return out;
    for (const slot of readable.slots) {
      if (!at.has(slot.line)) continue;
      const i = entryFor(slot.line);
      const exact = i >= 0 && plan[i].lineID === slot.line;
      for (const x of slot.sounds) {
        if (!PLACEMENTS.includes(x.at)) continue;
        if (i < 0) { const j = plan.length - 1; out[j].after.push({ slot, sound: x }); continue; }
        if (!exact && (x.at === 'after' || x.at === 'under')) { out[i].before.push({ slot, sound: x }); continue; }
        out[i][x.at === 'bed' ? 'under' : x.at].push({ slot, sound: x });
        if (x.at === 'bed') {
          const j = Math.max(i, lastFor(x.until || slot.line));
          out[j].stop.push(x.id);
        }
      }
    }
    return out;
  }

  /** The plan entries Hear it in place plays (§3.2 item 2): from the entry before the slot's line to the one after it. */
  function inPlace(script, plan, lineID) {
    const at = lineIndex(script);
    const k = at.get(lineID);
    let i = plan.findIndex(e => at.get(e.lineID) >= k);
    if (i < 0) i = plan.length;
    const exact = i < plan.length && plan[i].lineID === lineID;
    return { from: Math.max(0, i - 1), to: Math.min(plan.length - 1, exact ? i + 1 : i) };
  }

  return {
    PLACEMENTS, PLACEMENT_LABEL, FADES_MS, START_STEP_MS, LICENSES, REFUSED_HOSTS, OWN_RECORD_MAX_S, OWN_FILE_MAX_S, OWN_FILE_MAX_BYTES,
    slotsOf, ensure, addSlot, setSilent, defaultPlacement, addSound, updateSound, removeSound, prune, addPerformed,
    summary, partLine, directionsLine, placementWords, placeLine, clock,
    readManifest, licenseLabel, cueLine, megabytes, seedQuery, search, searchMine, sources, withoutOwn,
    listenCues, inPlace,
  };
})();
if (typeof module !== 'undefined') module.exports = SoundCore;
