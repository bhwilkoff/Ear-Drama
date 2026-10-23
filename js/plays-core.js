/**
 * Plays phase 1, pass the phone (docs/PLAYS-DESIGN.md, binding): the script,
 * the production record, the relay, the mix timeline, and the audio math, as
 * plain functions of plain data. The web's mirror of apple/Core/Plays
 * (PlayScript, Production, Relay, MixTimeline, PlayAudioMath): no DOM, no
 * audio device, no storage, so js/plays.test.js runs this file as shipped.
 *
 * A production record has the shape of Apple's production.json, field for
 * field; `created` is seconds since 2001-01-01, Foundation's default date.
 * Nothing here rewrites, summarizes, or fills in a word of a script (§8 rule 2).
 */
const PlaysCore = (() => {
  'use strict';

  const DIRECTIONS = 'directions';
  const SOUND = 'sound';
  /** What a take's `heard` records for a cue the device voice read live. */
  const STANDIN = 'standin';
  const TAKE_RATE = 48000;
  const ROOM_TONE_SECONDS = 5;
  const DEFAULT_GAP = 0.4;
  const TARGET_LUFS = -16;
  const PEAK_CEILING = -1;
  /** UNVERIFIED: the share of 20 ms frames above the speech floor, while the
   *  device voice reads, that flags bleed. To measure on devices (08a). */
  const BLEED_LOUD_FRACTION = 0.3;
  const REFERENCE_DATE_S = 978307200;

  const clone = (o) => JSON.parse(JSON.stringify(o));
  const now = () => Date.now() / 1000 - REFERENCE_DATE_S;
  const uuid = () => crypto.randomUUID().toUpperCase();

  /* ---- Parts ---- */

  const role = (name) => `role:${name}`;
  const roleName = (part) => (part.startsWith('role:') ? part.slice(5) : null);
  const isSpeaking = (part) => roleName(part) !== null;
  function partTitle(part) {
    const name = roleName(part);
    if (name !== null) return name;
    return part === DIRECTIONS ? 'Stage directions' : 'Sound effects';
  }

  /** The part a line belongs to: its role, or one of the two parts "like any other" (§2.2). */
  function linePart(line) {
    if (line.kind === 'speech') return role(line.role || '');
    if (line.kind === 'direction') return DIRECTIONS;
    return SOUND;
  }

  /** A printed piece of a speech: { say } | { direction } | { mic } | { sound }. */
  function pieceKind(piece) {
    const k = Object.keys(piece)[0];
    return k === 'say' || k === 'mic' || k === 'sound' ? k : 'direction';
  }
  const pieceText = (piece) => piece[Object.keys(piece)[0]] || '';

  /** The words a performer (or the device voice) says: a speech's said parts, or a printed block. */
  function spokenText(line) {
    if (line.kind === 'speech') {
      return (line.parts || []).filter(p => pieceKind(p) === 'say').map(pieceText).join(' ');
    }
    return line.source || '';
  }

  /** "Carlton, Henry Fisk" as Gutenberg files it reads "Henry Fisk Carlton". */
  function displayName(filed) {
    const i = filed.indexOf(',');
    if (i < 0) return filed;
    const last = filed.slice(0, i).trim();
    const first = filed.slice(i + 1).trim();
    if (!first || /^\d/.test(first)) return filed;
    return `${first} ${last}`;
  }
  const authorLine = (script) =>
    (script.authors || []).map(a => a.name).filter(Boolean).map(displayName).join(', ');

  const linesFor = (script, part) => script.lines.filter(l => linePart(l) === part);
  const speechLineIDs = (script) => script.lines.filter(l => l.kind === 'speech').map(l => l.id);

  /** Speaking parts largest first (by lines, then first appearance), then sound, then directions. */
  function castParts(script) {
    const counts = new Map();
    const first = new Map();
    script.lines.forEach((line, i) => {
      const p = linePart(line);
      counts.set(p, (counts.get(p) || 0) + 1);
      if (!first.has(p)) first.set(p, i);
    });
    const speaking = [...counts.keys()].filter(isSpeaking)
      .sort((a, b) => (counts.get(b) - counts.get(a)) || (first.get(a) - first.get(b)));
    const others = [SOUND, DIRECTIONS].filter(p => counts.has(p));
    return [...speaking, ...others].map(id => ({ id, lineCount: counts.get(id), title: partTitle(id) }));
  }

  /* ---- The production record ---- */

  function newProduction(script, { id = uuid(), created = now() } = {}) {
    const parts = {};
    for (const p of castParts(script)) parts[p.id] = { status: 'open' };
    return {
      id, scriptID: script.id, scriptRevision: script.revision, title: script.title, created,
      parts, takes: [], chosen: {}, roomTone: [], listenedThrough: false,
    };
  }

  const stateOf = (p, part) => p.parts[part] || { status: 'open' };
  const takeById = (p, id) => p.takes.find(t => t.id === id) || null;
  const chosenTake = (p, lineID) => (p.chosen[lineID] ? takeById(p, p.chosen[lineID]) : null);
  const takesFor = (p, lineID) => p.takes.filter(t => t.lineID === lineID);
  /** The chosen take when it counts: a take the bleed check flagged is kept on disk but never
   *  counts or reaches the mix (§5 rule 2, §8 rule 3). */
  const usableTake = (p, lineID) => { const t = chosenTake(p, lineID); return t && !t.bleed ? t : null; };

  /** A new take becomes the line's chosen one; the older takes stay (§8 rule 5). */
  function addTake(p, take) {
    const next = clone(p);
    next.takes.push(clone(take));
    next.chosen[take.lineID] = take.id;
    next.listenedThrough = false;
    return next;
  }

  function choose(p, takeID) {
    const take = takeById(p, takeID);
    if (!take) return p;
    const next = clone(p);
    if (next.chosen[take.lineID] !== takeID) next.listenedThrough = false;
    next.chosen[take.lineID] = takeID;
    return next;
  }

  function unusedTakes(p) {
    const keep = new Set(Object.values(p.chosen));
    return p.takes.filter(t => !keep.has(t.id));
  }

  /** Every take that is not a line's chosen one is removed; returns them so the store deletes their files. */
  function discardUnused(p) {
    const gone = unusedTakes(p);
    const ids = new Set(gone.map(t => t.id));
    const next = clone(p);
    next.takes = next.takes.filter(t => !ids.has(t.id));
    return { production: next, gone };
  }

  function fingerprint(p) {
    return Object.keys(p.chosen).sort().map(k => `${k}=${p.chosen[k]}`).join(',');
  }
  const isFinished = (p) => !!p.listenedThrough && p.mixedFrom === fingerprint(p);

  /** JSON with sorted keys, as Apple's encoder writes production.json. */
  function stableStringify(value) {
    if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
    if (value && typeof value === 'object') {
      return `{${Object.keys(value).sort().filter(k => value[k] !== undefined)
        .map(k => `${JSON.stringify(k)}:${stableStringify(value[k])}`).join(',')}}`;
    }
    return JSON.stringify(value);
  }

  /* ---- The relay (§2.3-2.5) ----
     Pending owner (C7): strictly one part at a time, in a fixed order, largest part
     first. Only the next part can be taken, and only while no other part records.
     Sound and directions come last and may be left silent; a speaking part may not (C6). */

  class Refusal extends Error {
    constructor(kind, detail) { super(kind); this.kind = kind; this.detail = detail; }
  }

  const order = (script) => castParts(script).map(p => p.id);
  const current = (p, script) => order(script).find(id => stateOf(p, id).status === 'recording') || null;
  function next(p, script) {
    if (current(p, script)) return null;
    return order(script).find(id => stateOf(p, id).status === 'open') || null;
  }

  function withState(p, part, state) {
    const n = clone(p);
    n.parts[part] = state;
    return n;
  }

  function take(p, script, part, performer) {
    const cur = current(p, script);
    if (cur) throw new Refusal('anotherPartIsRecording', cur);
    const nx = next(p, script);
    if (nx !== part) throw new Refusal('notNext', nx);
    const name = (performer || '').trim();
    return withState(p, part, name ? { status: 'recording', performer: name } : { status: 'recording' });
  }

  /** Lines of the part with no chosen take, or whose chosen take the bleed check flagged. */
  const missingLines = (p, script, part) => linesFor(script, part).map(l => l.id).filter(id => !usableTake(p, id));

  /** "Done with this part": a speaking part is done only when every one of its lines has a take (§5 rule 4). */
  function finish(p, script, part) {
    if (stateOf(p, part).status !== 'recording') throw new Refusal('notNext', current(p, script));
    if (isSpeaking(part)) {
      const missing = missingLines(p, script, part);
      if (missing.length) throw new Refusal('linesMissing', missing);
    }
    return withState(p, part, { ...stateOf(p, part), status: 'done' });
  }

  function leaveSilent(p, script, part) {
    if (isSpeaking(part)) throw new Refusal('speakingPartCannotBeSilent');
    const st = stateOf(p, part).status;
    if (!(st === 'recording' || next(p, script) === part)) throw new Refusal('notNext', next(p, script));
    return withState(p, part, { ...stateOf(p, part), status: 'silent' });
  }

  function reopen(p, script, part) {
    const cur = current(p, script);
    if (cur) throw new Refusal('anotherPartIsRecording', cur);
    if (!['done', 'silent'].includes(stateOf(p, part).status)) throw new Refusal('notNext', next(p, script));
    return withState(p, part, { ...stateOf(p, part), status: 'recording' });
  }

  /** Speaking lines with no unflagged human take. */
  const missingSpeech = (p, script) => speechLineIDs(script).filter(id => !usableTake(p, id));
  /** Lines of any kind whose chosen take the bleed check flagged. */
  const needsRetake = (p, script) => script.lines.map(l => l.id).filter(id => chosenTake(p, id)?.bleed === true);
  /** Only when every speaking line has an unflagged take and no chosen take is flagged can the play be mixed. */
  const isComplete = (p, script) => missingSpeech(p, script).length === 0 && needsRetake(p, script).length === 0;

  /** The cue before a line: the previous speech when another part speaks it, or the two before it for a run-up. */
  function cueLines(script, lineID, runUp = false) {
    const index = script.lines.findIndex(l => l.id === lineID);
    if (index < 0) return [];
    const me = linePart(script.lines[index]);
    const before = script.lines.slice(0, index).filter(l => l.kind === 'speech');
    if (runUp) return before.slice(-2);
    const last = before[before.length - 1];
    return last && linePart(last) !== me ? [last] : [];
  }

  function refusalText(r) {
    switch (r.kind) {
      case 'anotherPartIsRecording': return `${partTitle(r.detail)} is still recording.`;
      case 'notNext': return r.detail ? `${partTitle(r.detail)} is next.` : 'No part is open.';
      case 'linesMissing': return r.detail.length === 1 ? '1 line still needs a take.' : `${r.detail.length} lines still need a take.`;
      case 'speakingPartCannotBeSilent': return 'A speaking part needs a voice.';
      default: return String(r.message || r);
    }
  }

  /* ---- The mix as plain data (§4.2) ----
     Lines in script order, each a chosen human take with its in and out points, a gap,
     and a stored gain. Placement is relative, so a longer re-take ripples. A partial
     play has no timeline (§5 rule 3), and only a take can be placed. */

  class MixFailure extends Error {
    constructor(kind, detail) { super(kind); this.kind = kind; this.detail = detail; }
  }

  /** The gain to -16 LUFS, held so the sample peak stays at or below -1 dBFS, within +-24 dB. */
  function gain(loudness, peak) {
    if (loudness === null || loudness === undefined || !isFinite(loudness)) return 1;
    let db = TARGET_LUFS - loudness;
    if (peak > 0) db = Math.min(db, PEAK_CEILING - 20 * Math.log10(peak));
    db = Math.min(Math.max(db, -24), 24);
    return Math.pow(10, db / 20);
  }

  function buildTimeline(script, p, { sampleRate = TAKE_RATE, gap = DEFAULT_GAP } = {}) {
    const missing = missingSpeech(p, script);
    if (missing.length) throw new MixFailure('incomplete', missing);
    const flagged = needsRetake(p, script);
    if (flagged.length) throw new MixFailure('bleed', flagged);
    const placements = [];
    let cursor = 0;
    const gapFrames = Math.floor(gap * sampleRate);
    for (const line of script.lines) {
      const t = chosenTake(p, line.id);
      if (!t) continue;
      if (t.sampleRate !== sampleRate) throw new MixFailure('sampleRate', t.id);
      const start = placements.length ? cursor + gapFrames : 0;
      placements.push({ lineID: line.id, takeID: t.id, file: t.file, start, inFrame: 0, outFrame: t.frames,
                        frames: t.frames, gain: gain(t.loudness, t.peak), bleed: !!t.bleed });
      cursor = start + t.frames;
    }
    return { sampleRate, placements, totalFrames: cursor };
  }

  /**
   * Renders a timeline into a 16-bit mono WAV Blob, in chunks of `chunkSeconds`
   * so a long play never holds its whole mix in memory. `makeContext(channels,
   * frames, rate)` is an OfflineAudioContext in the browser; `loadTake(placement)`
   * returns the take's samples. It reads only takes the timeline names, and a
   * timeline holds only human takes, so a device voice cannot reach the mix. A take
   * the bleed check flagged is refused, never mixed (§8 rule 3).
   */
  async function renderMix(timeline, loadTake, makeContext, { chunkSeconds = 30 } = {}) {
    const flagged = timeline.placements.find(x => x.bleed);
    if (flagged) throw new MixFailure('bleed', [flagged.lineID]);
    const rate = timeline.sampleRate;
    const chunk = Math.max(1, Math.round(chunkSeconds * rate));
    const parts = [wavHeader(timeline.totalFrames, rate, 16)];
    const loaded = new Map();
    for (let c0 = 0; c0 < timeline.totalFrames; c0 += chunk) {
      const c1 = Math.min(timeline.totalFrames, c0 + chunk);
      const ctx = makeContext(1, c1 - c0, rate);
      for (const p of timeline.placements) {
        if (p.start + p.frames <= c0 || p.start >= c1) continue;
        if (!loaded.has(p.takeID)) loaded.set(p.takeID, await loadTake(p));
        const samples = loaded.get(p.takeID);
        const win = samples.subarray(Math.min(p.inFrame, samples.length), Math.min(p.outFrame, samples.length));
        if (!win.length) continue;
        const buffer = ctx.createBuffer(1, win.length, rate);
        buffer.getChannelData(0).set(win);
        const src = ctx.createBufferSource();
        src.buffer = buffer;
        const g = ctx.createGain();
        g.gain.value = p.gain;
        src.connect(g);
        g.connect(ctx.destination);
        src.start(Math.max(0, p.start - c0) / rate, Math.max(0, c0 - p.start) / rate);
      }
      const rendered = await ctx.startRendering();
      parts.push(pcmBytes(rendered.getChannelData(0), 16));
      for (const p of timeline.placements) {
        if (p.start + p.frames <= c1) loaded.delete(p.takeID);
      }
    }
    return new Blob(parts, { type: 'audio/wav' });
  }

  /* ---- Loudness (ITU-R BS.1770, mono) ---- */

  function biquad(x, b, a) {
    const y = new Float64Array(x.length);
    let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (let i = 0; i < x.length; i++) {
      const out = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2;
      x2 = x1; x1 = x[i]; y2 = y1; y1 = out;
      y[i] = out;
    }
    return y;
  }

  /** K-weighting with the libebur128 filter design, valid at any sample rate. */
  function kWeighted(x, fs) {
    let k = Math.tan(Math.PI * 1681.974450955533 / fs);
    const vh = Math.pow(10, 3.999843853973347 / 20), vb = Math.pow(vh, 0.4996667741545416);
    let q = 0.7071752369554196;
    let a0 = 1 + k / q + k * k;
    const s1b = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0];
    const s1a = [2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0];
    k = Math.tan(Math.PI * 38.13547087602444 / fs);
    q = 0.5003270373238773;
    a0 = 1 + k / q + k * k;
    const s2a = [2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0];
    return biquad(biquad(Float64Array.from(x), s1b, s1a), [1, -2, 1], s2a);
  }

  /** Integrated loudness: 400 ms blocks every 100 ms, the -70 LUFS and -10 LU gates. Null when silent. */
  function integratedLoudness(samples, sampleRate) {
    const w = kWeighted(samples, sampleRate);
    const block = Math.floor(sampleRate * 0.4), hop = Math.floor(sampleRate * 0.1);
    if (w.length < block || block <= 0) return null;
    const powers = [];
    for (let start = 0; start + block <= w.length; start += hop) {
      let sum = 0;
      for (let i = start; i < start + block; i++) sum += w[i] * w[i];
      powers.push(sum / block);
    }
    const loud = (z) => -0.691 + 10 * Math.log10(z);
    const absolute = powers.filter(z => z > 0 && loud(z) > -70);
    if (!absolute.length) return null;
    const relative = loud(absolute.reduce((a, b) => a + b, 0) / absolute.length) - 10;
    const gated = absolute.filter(z => loud(z) > relative);
    if (!gated.length) return null;
    return loud(gated.reduce((a, b) => a + b, 0) / gated.length);
  }

  function samplePeak(samples) {
    let m = 0;
    for (let i = 0; i < samples.length; i++) { const v = Math.abs(samples[i]); if (v > m) m = v; }
    return m;
  }

  function rms(samples) {
    if (!samples.length) return 0;
    let s = 0;
    for (let i = 0; i < samples.length; i++) s += samples[i] * samples[i];
    return Math.sqrt(s / samples.length);
  }

  /* ---- The end of a line (§2.4): an energy detector on 20 ms frames, its floor from the room tone ---- */

  const MIN_THRESHOLD = 0.003;   // about -50 dBFS RMS
  const thresholdFor = (roomToneRMS) => Math.max(MIN_THRESHOLD, roomToneRMS * 4);

  class LineEndDetector {
    constructor(sampleRate, roomToneRMS, trailingSilence = 1.0) {
      this.sampleRate = sampleRate;
      this.threshold = thresholdFor(roomToneRMS);
      this.trailingSilence = trailingSilence;
      this.frameLength = Math.floor(sampleRate * 0.02);
      this.onset = null;
      this.end = null;
      this.position = 0;
      this.loudRun = 0;
      this.lastLoud = 0;
      this.pending = [];
    }

    /** Feeds microphone samples; returns { type: 'onset' | 'end', frame } when one happens. */
    feed(samples) {
      for (let i = 0; i < samples.length; i++) this.pending.push(samples[i]);
      let event = null;
      let at = 0;
      while (this.pending.length - at >= this.frameLength && this.end === null) {
        const frame = this.pending.slice(at, at + this.frameLength);
        at += this.frameLength;
        if (rms(frame) >= this.threshold) {
          this.loudRun += 1;
          this.lastLoud = this.position + this.frameLength;
          if (this.onset === null && this.loudRun >= 3) {
            this.onset = this.position - 2 * this.frameLength;
            event = { type: 'onset', frame: this.onset };
          }
        } else {
          this.loudRun = 0;
        }
        this.position += this.frameLength;
        if (this.onset !== null && this.position - this.lastLoud >= this.trailingSilence * this.sampleRate) {
          this.end = this.lastLoud;
          event = { type: 'end', frame: this.lastLoud };
        }
      }
      this.pending = this.pending.slice(at);
      return event;
    }
  }

  /** The kept window, [from, to): onset less 250 ms to the end plus 250 ms (§4.2); no onset keeps it all. */
  function lineWindow(onset, end, total, sampleRate) {
    if (onset === null || onset === undefined) return [0, total];
    const handle = Math.floor(sampleRate * 0.25);
    const lower = Math.max(0, onset - handle);
    const upper = Math.min(total, (end === null || end === undefined ? total : end) + handle);
    return [lower, Math.max(lower, upper)];
  }

  /** The web's bleed check (PLAYS-DESIGN §4.1, "level only"): how much of the time the
   *  device voice read, the microphone heard more than the room. Holds counts, never samples. */
  class CueMeter {
    constructor(sampleRate, threshold) {
      this.frameLength = Math.max(1, Math.floor(sampleRate * 0.02));
      this.threshold = threshold;
      this.frames = 0;
      this.loud = 0;
      this.sum = 0;
      this.n = 0;
    }
    feed(samples) {
      for (let i = 0; i < samples.length; i++) {
        this.sum += samples[i] * samples[i];
        if (++this.n === this.frameLength) {
          this.frames += 1;
          if (Math.sqrt(this.sum / this.n) >= this.threshold) this.loud += 1;
          this.sum = 0;
          this.n = 0;
        }
      }
    }
    fraction() { return this.frames ? this.loud / this.frames : 0; }
  }

  /* ---- WAV (PCM, mono) ---- */

  function wavHeader(frames, rate, bits) {
    const bytes = bits / 8;
    const h = new DataView(new ArrayBuffer(44));
    const tag = (o, s) => { for (let i = 0; i < 4; i++) h.setUint8(o + i, s.charCodeAt(i)); };
    tag(0, 'RIFF'); h.setUint32(4, 36 + frames * bytes, true); tag(8, 'WAVE');
    tag(12, 'fmt '); h.setUint32(16, 16, true); h.setUint16(20, 1, true); h.setUint16(22, 1, true);
    h.setUint32(24, rate, true); h.setUint32(28, rate * bytes, true); h.setUint16(32, bytes, true);
    h.setUint16(34, bits, true);
    tag(36, 'data'); h.setUint32(40, frames * bytes, true);
    return new Uint8Array(h.buffer);
  }

  function pcmBytes(samples, bits) {
    const bytes = bits / 8;
    const out = new Uint8Array(samples.length * bytes);
    const max = bits === 24 ? 8388607 : 32767;
    for (let i = 0; i < samples.length; i++) {
      const v = Math.round(Math.max(-1, Math.min(1, samples[i])) * max);
      const o = i * bytes;
      out[o] = v & 0xff;
      out[o + 1] = (v >> 8) & 0xff;
      if (bytes === 3) out[o + 2] = (v >> 16) & 0xff;
    }
    return out;
  }

  /** Mono PCM samples as a WAV file's bytes (24-bit for takes, §4.2). */
  function encodeWav(samples, rate, bits = 24) {
    const head = wavHeader(samples.length, rate, bits);
    const body = pcmBytes(samples, bits);
    const out = new Uint8Array(head.length + body.length);
    out.set(head, 0);
    out.set(body, head.length);
    return out;
  }

  /** A PCM WAV's samples (channel 0) at its own rate. */
  function decodeWav(buffer) {
    const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const tag = (o) => String.fromCharCode(bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]);
    if (tag(0) !== 'RIFF' || tag(8) !== 'WAVE') throw new Error('not a WAV file');
    let o = 12, rate = 0, bits = 16, channels = 1;
    while (o + 8 <= bytes.length) {
      const id = tag(o), size = v.getUint32(o + 4, true);
      if (id === 'fmt ') {
        channels = v.getUint16(o + 10, true);
        rate = v.getUint32(o + 12, true);
        bits = v.getUint16(o + 22, true);
      } else if (id === 'data') {
        const width = bits / 8;
        const frames = Math.floor(Math.min(size, bytes.length - o - 8) / (width * channels));
        const samples = new Float32Array(frames);
        for (let i = 0; i < frames; i++) {
          const p = o + 8 + i * width * channels;
          let s;
          if (width === 3) {
            s = bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16);
            if (s & 0x800000) s |= ~0xffffff;
            s /= 8388608;
          } else {
            s = v.getInt16(p, true) / 32768;
          }
          samples[i] = s;
        }
        return { samples, sampleRate: rate };
      }
      o += 8 + size + (size % 2);
    }
    throw new Error('WAV file has no data');
  }

  return {
    DIRECTIONS, SOUND, STANDIN, TAKE_RATE, ROOM_TONE_SECONDS, DEFAULT_GAP, TARGET_LUFS, PEAK_CEILING,
    BLEED_LOUD_FRACTION, now, uuid, clone,
    role, roleName, isSpeaking, partTitle, linePart, pieceKind, pieceText, spokenText, displayName, authorLine,
    linesFor, speechLineIDs, castParts,
    newProduction, stateOf, takeById, chosenTake, usableTake, takesFor, addTake, choose, unusedTakes, discardUnused,
    fingerprint, isFinished, stableStringify,
    Refusal, order, current, next, take, finish, leaveSilent, reopen, missingLines, missingSpeech, needsRetake, isComplete,
    cueLines, refusalText,
    MixFailure, gain, buildTimeline, renderMix,
    integratedLoudness, samplePeak, rms, thresholdFor, LineEndDetector, lineWindow, CueMeter,
    wavHeader, pcmBytes, encodeWav, decodeWav,
  };
})();
