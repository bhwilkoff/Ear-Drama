/**
 * The person's own scripts on this browser (PLAYS-DESIGN §13, WEB-DESIGN §4.21; Decision 088.3): the
 * one module that keeps them. Nothing here leaves the device and nothing asks for an account.
 *
 * IndexedDB `ed-plays` (js/plays-store.js opens it), object store `scripts`:
 *   scripts/<id>/doc.json     the working copy OwnCore corrects, with the title, the text as pasted
 *                             (normalized), and the parts named but not yet given a line
 *   scripts/<id>/script.json  the castable shape, once Done: what the reader and the recorder read
 *   scripts/<id>/row.json     what Record's Your scripts draws without opening either
 *   scripts/draft.json        the text being added, before Next
 * A script's three files are written in one transaction, so a full disk never leaves half of one.
 */
const OwnScripts = (() => {
  'use strict';
  const O = OwnCore;
  const C = PlaysCore;
  const DRAFT = 'scripts/draft.json';
  const folder = (id) => `scripts/${id}/`;
  const parse = (raw) => { try { return raw === null || raw === undefined ? null : JSON.parse(raw); } catch { return null; } };

  /** `plays()` resolves to the play store (its takes lock lines; its productions take a change). */
  function open({ backend, plays = null, now = () => Date.now() }) {
    const writing = new Map();
    const store = {
      backend,

      /** Your scripts, the last one changed first: `{ id, title, parts, lines, open, done, cast, voices, created, updated }`. */
      async list() {
        const keys = (await backend.keys('scripts/')).filter(k => k.endsWith('/row.json'));
        const rows = (await Promise.all(keys.map(k => backend.get(k)))).map(parse).filter(r => r && O.OWN_ID.test(r.id));
        return rows.sort((a, b) => b.updated - a.updated);
      },

      /** A script being corrected, or null: `{ id, title, original, doc, extras, created, updated, done }`. */
      async get(id) { return parse(await backend.get(`${folder(id)}doc.json`)); },

      /** The castable script, once Done; null before, and for an id not here. */
      async script(id) { return parse(await backend.get(`${folder(id)}script.json`)); },

      /** A new script from a title and a text: its parts proposed, no line id given yet. */
      async create({ title, text }) {
        const read = O.parse(text);
        const at = now();
        const rec = { id: `own-${C.uuid().toLowerCase()}`, title: O.trim(O.normalize(title)), original: read.text,
                      doc: O.newDoc(read.lines), extras: [], created: at, updated: at, done: false };
        await store.keep(rec);
        return rec;
      },

      /**
       * Keeps `rec` as it stands. A Done script's castable shape is sealed and its productions follow;
       * while its lines cannot be a script ("no_parts"), the last one that could stays. Resolves to that
       * refusal or null. Writes of one script never overtake each other.
       */
      keep(rec) {
        const snap = { ...rec, doc: O.kept(rec.doc), updated: rec.updated = now() };
        const before = writing.get(rec.id) || Promise.resolve();
        const w = before.catch(() => {}).then(() => write(snap));
        writing.set(rec.id, w);
        return w;
      },

      async remove(id) {
        await (writing.get(id) || Promise.resolve()).catch(() => {});
        writing.delete(id);
        await backend.removePrefix(folder(id));
      },

      /** The lines of `id` with a take in any of its productions: what may not move (§13 item 4). */
      async takes(id) { return plays ? (await plays()).takenLines(id) : []; },
      async productions(id) { return plays ? (await plays()).productionsOf(id) : []; },

      async draft() { return parse(await backend.get(DRAFT)); },
      setDraft(d) { return d && (d.title || d.text) ? backend.put(DRAFT, JSON.stringify(d)) : backend.remove(DRAFT); },

      /** Export my data's `scripts`: each one's lines as they stand, Done or not. */
      async exportRows() {
        const out = [];
        for (const row of await store.list()) {
          const rec = await store.get(row.id);
          if (!rec) continue;
          const script = rec.done ? await store.script(row.id) : null;
          out.push({
            id: rec.id, title: rec.title, source: script ? script.source.name : 'Added by you', created: new Date(rec.created).toISOString(), done: !!rec.done,
            lines: script ? script.lines : rec.doc.lines.map(l => (l.kind === 'speech'
              ? { kind: l.kind, role: l.role, parts: O.pieces(l.text) } : { kind: l.kind, source: l.text })),
          });
        }
        return out;
      },
    };

    async function write(snap) {
      const parts = O.partsOf(snap.doc.lines).map(p => p.lines).sort((a, b) => b - a);
      let script = null, refusal = null;
      if (snap.done) {
        const taken = new Set(await store.takes(snap.id));
        const built = O.toScript(O.done(snap.doc), { id: snap.id, title: snap.title });
        refusal = O.refusalOf(built);
        if (!refusal) {
          script = await O.seal(built);
          script.created = snap.created;
          script.edits = editsOf(await store.script(snap.id), script, taken);
        }
      }
      const row = { id: snap.id, title: snap.title, parts: parts.length, lines: snap.doc.lines.length,
                    open: snap.doc.lines.filter(l => l.kind === 'open').length, done: snap.done, cast: parts,
                    voices: parts.filter(n => n >= C.CASTABLE_LINES).length, created: snap.created, updated: snap.updated };
      await backend.putAll([[`${folder(snap.id)}doc.json`, JSON.stringify(snap)], [`${folder(snap.id)}row.json`, JSON.stringify(row)],
        ...(script ? [[`${folder(snap.id)}script.json`, JSON.stringify(script)]] : [])]);
      if (script && plays) await (await plays()).adopt(script);
      return refusal;
    }
    return store;
  }

  const textOf = (l) => (l.kind === 'speech' ? O.textOf(l.parts) : l.source);
  /** What a line with a take said before its words changed, and until when: `{ lineID: [{ until, text }] }`, oldest first. */
  function editsOf(was, is, taken) {
    const edits = { ...((was && was.edits) || {}) };
    if (!was) return edits;
    const before = new Map(was.lines.map(l => [l.id, textOf(l)]));
    for (const l of is.lines) {
      const old = before.get(l.id);
      if (taken.has(l.id) && old !== undefined && old !== textOf(l)) edits[l.id] = [...(edits[l.id] || []), { until: C.now(), text: old }];
    }
    return edits;
  }
  /** Whether the words of `take`'s line changed, more than punctuation, since it was recorded (§13 item 4). */
  function wordsChanged(script, take) {
    const past = script && script.edits && script.edits[take.lineID];
    const said = past && past.find(e => take.created < e.until);
    const line = said && script.lines.find(l => l.id === take.lineID);
    return !!line && O.wordsChanged(said.text, textOf(line));
  }

  /**
   * The script as plain text, readable as Fountain and by Add a script: a name alone in capitals over
   * its words (an `@` before one with no capital letter to show), directions as paragraphs.
   */
  function asText(script) {
    const out = script.lines.map(l => {
      if (l.kind !== 'speech') return l.source;
      return `${/[A-Z]/.test(l.role) ? '' : '@'}${l.role}\n${O.textOf(l.parts)}`;
    });
    return `${out.join('\n\n')}\n`;
  }
  const fileName = (title) => `${title.replace(/[\\/:*?"<>|]+/g, '').trim() || 'Script'}.txt`;

  /**
   * A file's bytes as text, or why not: `{ text }` or `{ refusal: 'too_long' | 'not_text' }`. Bytes are
   * counted before anything reads them. UTF-8, UTF-16 with its mark, else Windows-1252 (old .txt files).
   */
  function decode(bytes) {
    const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    if (b.length > 2 * O.MAX_BYTES + 2) return { refusal: 'too_long' };
    const starts = (...x) => x.every((v, i) => b[i] === v);
    if (starts(0x25, 0x50, 0x44, 0x46) || starts(0x7b, 0x5c, 0x72, 0x74, 0x66) || starts(0x50, 0x4b, 3, 4)) return { refusal: 'not_text' };
    let text;
    if (starts(0xff, 0xfe) || starts(0xfe, 0xff)) text = new TextDecoder(b[0] === 0xff ? 'utf-16le' : 'utf-16be').decode(b);
    else {
      if (b.includes(0)) return { refusal: 'not_text' };
      try { text = new TextDecoder('utf-8', { fatal: true }).decode(b); } catch {
        let controls = 0;
        for (const u of b) if (u < 32 && u !== 9 && u !== 10 && u !== 12 && u !== 13) controls += 1;
        if (controls > b.length / 500) return { refusal: 'not_text' };
        text = new TextDecoder('windows-1252').decode(b);
      }
    }
    return O.textRefusal(text) === 'too_long' ? { refusal: 'too_long' } : { text };
  }

  /** Each line with no part's two nearest speakers, as OwnCore.nearestParts answers, for every line in two passes. */
  function nearestAll(lines) {
    const above = new Array(lines.length), below = new Array(lines.length);
    const sweep = (from, step, out) => {
      let two = [];
      for (let i = from; i >= 0 && i < lines.length; i += step) {
        out[i] = two;
        const l = lines[i];
        if (l.kind === 'speech') two = [{ role: l.role, i }, ...two.filter(x => x.role !== l.role)].slice(0, 2);
      }
    };
    sweep(0, 1, above);
    sweep(lines.length - 1, -1, below);
    const out = new Map();
    lines.forEach((l, i) => {
      if (l.kind !== 'open') return;
      const near = [...above[i].map(x => ({ ...x, d: i - x.i, up: 0 })), ...below[i].map(x => ({ ...x, d: x.i - i, up: 1 }))]
        .sort((a, b) => a.d - b.d || a.up - b.up);
      out.set(l.k, [...new Set(near.map(x => x.role))].slice(0, 2));
    });
    return out;
  }

  let one = null;
  /** This page's store, over the same database the plays use. */
  function shared() {
    if (!one) {
      const has = typeof indexedDB !== 'undefined';
      one = open({ backend: has ? PlayStore.indexedDBBackend('ed-plays', 'scripts') : PlayStore.memoryBackend(),
                   plays: () => PlaysUI.openStore() });
    }
    return one;
  }

  return { open, shared, wordsChanged, asText, fileName, decode, nearestAll };
})();
