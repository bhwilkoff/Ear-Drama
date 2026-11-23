/**
 * Marks in the script reader (PLAYS-DESIGN §2.10, WEB-DESIGN §4.16 item 15; Decision 076 S5), with no
 * DOM, so js/marks.test.js runs this file as shipped. js/marks.js draws what this decides.
 *
 * A mark is anchored to a line, never a page: (script, revision, line id, start, end), offsets into
 * the line's printed words (PlaysCore.lineText, the string every drawn run's data-at counts into),
 * with the marked words (`text`) and up to 32 characters either side (`prefix`, `suffix`), as the W3C
 * Web Annotation model pairs a TextPositionSelector with a TextQuoteSelector. A new revision of the
 * script re-anchors each mark by its words (`place`, golden cases in
 * catalog/tests/golden/marks_anchor.json, which every stack runs); a mark it cannot place is kept,
 * untouched, and listed as not placed.
 */
const MarksCore = (() => {
  'use strict';

  const KINDS = ['highlight', 'underline', 'breath', 'pause', 'beat', 'note'];
  /** Marks over words; the rest stand between two words. */
  const SPAN = new Set(['highlight', 'underline', 'note']);
  /** Marks that never stack: an overlapping or touching one of the same kind merges. */
  const MERGE = new Set(['highlight', 'underline']);
  const HUES = ['yellow', 'green', 'blue', 'pink'];
  const CONTEXT = 32;
  /** Away from its own line, a mark moves only on this many characters of evidence (words plus context), or all it has. */
  const EVIDENCE = 16;
  /** In its own line, a point mark needs this much of its context to match. */
  const POINT_EVIDENCE = 8;
  const LABEL_MAX = 24;
  const KEY = 'ed.marks.';
  const PREFS_KEY = 'ed.marks.prefs';

  const textOf = (line) => PlaysCore.lineText(line);
  /** A word's characters: letters, digits, apostrophes, hyphens, and the printed `_italic_` marks. */
  const isWord = (ch) => !!ch && /[\p{L}\p{N}'’_-]/u.test(ch);
  const isSpace = (ch) => /\s/.test(ch);

  /** A selection grown to whole words and trimmed of space; null when nothing is left. */
  function snapWords(text, start, end) {
    let s = Math.max(0, Math.min(start, end, text.length));
    let e = Math.min(text.length, Math.max(start, end, 0));
    while (s < e && isSpace(text[s])) s++;
    while (e > s && isSpace(text[e - 1])) e--;
    if (s >= e) return null;
    while (s > 0 && isWord(text[s - 1]) && isWord(text[s])) s--;
    while (e < text.length && isWord(text[e]) && isWord(text[e - 1])) e++;
    return { start: s, end: e };
  }

  /** Where a point mark goes for a selection ending at `end`: after its word and any punctuation that follows. */
  function pointAfter(text, end) {
    let p = Math.max(0, Math.min(end, text.length));
    while (p > 0 && isSpace(text[p - 1])) p--;
    while (p < text.length && isWord(text[p])) p++;
    while (p < text.length && !isSpace(text[p]) && !isWord(text[p])) p++;
    return p;
  }

  let seq = 0;
  const newId = (now) => `m${now.toString(36)}${(seq++).toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;

  /** The anchor's quote: the words and their context, read from the line as it is now. */
  function quote(lt, start, end) {
    return { text: lt.slice(start, end), prefix: lt.slice(Math.max(0, start - CONTEXT), start), suffix: lt.slice(end, end + CONTEXT) };
  }

  /** One mark on one line. `extra`: hue (a highlight), label (a beat), note (a note), group. */
  function make(script, lineID, start, end, kind, extra = {}, now = Date.now()) {
    const line = (script.lines || []).find(l => l.id === lineID);
    if (!line || !KINDS.includes(kind)) return null;
    const lt = textOf(line);
    const s = Math.max(0, Math.min(start, lt.length));
    const e = SPAN.has(kind) ? Math.max(s, Math.min(end, lt.length)) : s;
    const m = { id: newId(now), kind, line: lineID, start: s, end: e, ...quote(lt, s, e), revision: script.revision || null, created: now, updated: now };
    if (kind === 'highlight') m.hue = HUES.includes(extra.hue) ? extra.hue : HUES[0];
    if (kind === 'beat') m.label = String(extra.label || '').trim().slice(0, LABEL_MAX);
    if (kind === 'note') m.note = String(extra.note || '');
    if (extra.group && MERGE.has(kind)) m.group = extra.group;
    return m;
  }

  /**
   * The marks a selection makes. `pieces` are the selection per line in reading order, `{ line, start,
   * end }` in raw offsets. A span mark covers each piece grown to whole words (a note: its first line's
   * piece only); highlights and underlines across lines share a group. A point mark goes after the last
   * piece's last word.
   */
  function fromSelection(script, pieces, kind, extra = {}, now = Date.now()) {
    const byId = new Map((script.lines || []).map(l => [l.id, l]));
    const snapped = [];
    for (const p of pieces || []) {
      const line = byId.get(p.line);
      if (!line) continue;
      const lt = textOf(line);
      const w = snapWords(lt, p.start, p.end);
      if (w) snapped.push({ line: p.line, lt, ...w });
    }
    if (!snapped.length) return [];
    if (!SPAN.has(kind)) {
      const last = snapped[snapped.length - 1];
      const at = pointAfter(last.lt, last.end);
      return [make(script, last.line, at, at, kind, extra, now)];
    }
    const use = kind === 'note' ? snapped.slice(0, 1) : snapped;
    const group = use.length > 1 && MERGE.has(kind) ? `g${newId(now)}` : undefined;
    return use.map(p => make(script, p.line, p.start, p.end, kind, { ...extra, group }, now));
  }

  /**
   * Adds a mark by the overlap rules: a highlight or underline that overlaps or touches others of its
   * kind in the line merges with them into one over all their words, taking the new mark's id, hue and
   * group; a note is always its own; a breath, pause or beat replaces any point mark at its place.
   */
  function add(script, marks, mark) {
    if (!mark) return marks.slice();
    let out = marks.slice();
    if (MERGE.has(mark.kind)) {
      let s = mark.start, e = mark.end, grew = true;
      const gone = new Set();
      while (grew) {
        grew = false;
        for (const m of out) {
          if (gone.has(m.id) || m.kind !== mark.kind || m.line !== mark.line) continue;
          if (m.start <= e && s <= m.end) { gone.add(m.id); s = Math.min(s, m.start); e = Math.max(e, m.end); grew = true; }
        }
      }
      out = out.filter(m => !gone.has(m.id));
      if (s !== mark.start || e !== mark.end) {
        const line = (script.lines || []).find(l => l.id === mark.line);
        const lt = line ? textOf(line) : '';
        mark = { ...mark, start: s, end: e, ...quote(lt, s, e) };
      }
    } else if (!SPAN.has(mark.kind)) {
      out = out.filter(m => SPAN.has(m.kind) || m.line !== mark.line || m.start !== mark.start);
    }
    out.push(mark);
    return out;
  }

  /** Removes a mark and the rest of its group: `{ marks, removed }`, so the removal can be undone. */
  function remove(marks, id) {
    const m = marks.find(x => x.id === id);
    if (!m) return { marks: marks.slice(), removed: [] };
    const hit = (x) => x.id === id || (m.group && x.group === m.group);
    return { marks: marks.filter(x => !hit(x)), removed: marks.filter(hit) };
  }

  /** Changes a mark: a hue for its whole group, a beat's label, a note's words. */
  function update(marks, id, patch, now = Date.now()) {
    const m = marks.find(x => x.id === id);
    if (!m) return marks.slice();
    return marks.map(x => {
      if (x.id !== id && !(patch.hue && m.group && x.group === m.group)) return x;
      const y = { ...x, updated: now };
      if (patch.hue && x.kind === 'highlight' && HUES.includes(patch.hue)) y.hue = patch.hue;
      if (x.id === id && patch.label !== undefined && x.kind === 'beat') y.label = String(patch.label).trim().slice(0, LABEL_MAX);
      if (x.id === id && patch.note !== undefined && x.kind === 'note') y.note = String(patch.note);
      return y;
    });
  }

  /* ---- Re-anchoring a revision (PLAYS-DESIGN §2.10 rule 4) ---- */

  function commonTail(a, b) {
    let n = 0;
    while (n < a.length && n < b.length && a[a.length - 1 - n] === b[b.length - 1 - n]) n++;
    return n;
  }
  function commonHead(a, b) {
    let n = 0;
    while (n < a.length && n < b.length && a[n] === b[n]) n++;
    return n;
  }

  /** The best place for a mark in one line's words: `{ at, score }` (context characters matched), or null. */
  function bestIn(lt, mark) {
    const text = mark.text || '';
    const prefix = mark.prefix || '', suffix = mark.suffix || '';
    const at = new Set();
    if (text) {
      for (let k = lt.indexOf(text); k >= 0; k = lt.indexOf(text, k + 1)) at.add(k);
    } else {
      const tail = prefix.slice(-16), head = suffix.slice(0, 16);
      if (tail) for (let k = lt.indexOf(tail); k >= 0; k = lt.indexOf(tail, k + 1)) at.add(k + tail.length);
      if (head) for (let k = lt.indexOf(head); k >= 0; k = lt.indexOf(head, k + 1)) at.add(k);
      if (!tail && !head) at.add(0);
    }
    let best = null;
    for (const k of at) {
      const score = commonTail(prefix, lt.slice(0, k)) + commonHead(suffix, lt.slice(k + text.length));
      const off = Math.abs(k - (mark.start || 0));
      if (!best || score > best.score || (score === best.score && off < best.off)) best = { at: k, score, off };
    }
    return best;
  }

  /** Where a line id sorts among the script's ids (`L0009a` after `L0009`, before `L0010`). */
  function sortIndex(ids, id) {
    let i = 0;
    while (i < ids.length && ids[i] < id) i++;
    return i;
  }

  /**
   * Re-anchors stored marks to `script` as it is now: `{ placed, lost, changed }`. A placed mark carries
   * its (maybe new) line, offsets, quote and this revision; a lost mark is returned exactly as stored.
   * `changed` is true when any placed mark moved or took the new revision.
   */
  function place(script, marks) {
    const lines = script.lines || [];
    const texts = lines.map(textOf);
    const ids = lines.map(l => l.id);
    const index = new Map(ids.map((id, i) => [id, i]));
    const rev = script.revision || null;
    const placed = [], lost = [];
    let changed = false;
    const put = (m, i, at) => {
      const end = at + (m.text || '').length;
      const q = quote(texts[i], at, end);
      const y = { ...m, line: ids[i], start: at, end, ...q, revision: rev };
      if (y.line !== m.line || y.start !== m.start || y.end !== m.end || y.revision !== m.revision || y.prefix !== m.prefix || y.suffix !== m.suffix) changed = true;
      placed.push(y);
    };
    for (const m of marks || []) {
      const text = m.text || '';
      const own = index.get(m.line);
      // 1. The same revision, and the slice still reads the words.
      if (own !== undefined && m.revision === rev && rev !== null && texts[own].slice(m.start, m.end) === text && m.end <= texts[own].length) {
        placed.push(m);
        continue;
      }
      // 2. The same line: the best place its words (or a point mark's context) stand.
      const avail = (m.prefix || '').length + (m.suffix || '').length;
      if (own !== undefined) {
        const b = bestIn(texts[own], m);
        if (b && (text ? true : b.score >= Math.min(POINT_EVIDENCE, avail))) { put(m, own, b.at); continue; }
      }
      // 3. Every other line, nearest first, on evidence.
      const from = own !== undefined ? own : sortIndex(ids, m.line);
      let best = null;
      for (let i = 0; i < lines.length; i++) {
        if (i === own) continue;
        const b = bestIn(texts[i], m);
        if (!b) continue;
        const dist = Math.abs(i - from);
        if (!best || b.score > best.score || (b.score === best.score && (dist < best.dist || (dist === best.dist && b.off < best.off)))) best = { ...b, i, dist };
      }
      if (best && text.length + best.score >= Math.min(EVIDENCE, text.length + avail) && (text || best.score > 0)) { put(m, best.i, best.at); continue; }
      // 4. Not placed: kept as it was.
      lost.push(m);
    }
    return { placed, lost, changed };
  }

  /** The notebook's order: script order (line, then offset), then the kinds' order. */
  function order(script, marks) {
    const index = new Map((script.lines || []).map((l, i) => [l.id, i]));
    return marks.slice().sort((a, b) => (index.get(a.line) ?? 1e9) - (index.get(b.line) ?? 1e9)
      || a.start - b.start || a.end - b.end || KINDS.indexOf(a.kind) - KINDS.indexOf(b.kind));
  }

  /** Marks at an offset in a line, the narrowest first (what a tap on the words opens). */
  function at(marks, lineID, offset) {
    return marks.filter(m => SPAN.has(m.kind) && m.line === lineID && m.start <= offset && offset < m.end)
      .sort((a, b) => (a.end - a.start) - (b.end - b.start) || (a.kind === 'note' ? -1 : b.kind === 'note' ? 1 : 0));
  }

  /* ---- On the device: one key per script, every access guarded ---- */

  function valid(m) {
    return m && typeof m === 'object' && typeof m.id === 'string' && KINDS.includes(m.kind) && typeof m.line === 'string'
      && Number.isInteger(m.start) && Number.isInteger(m.end) && m.start >= 0 && m.end >= m.start && typeof m.text === 'string';
  }

  /** A play's stored marks (`[]` when none, unreadable, or storage is blocked). */
  function load(storage, scriptID) {
    try {
      const raw = storage && storage.getItem(KEY + scriptID);
      const d = raw ? JSON.parse(raw) : null;
      return d && Array.isArray(d.marks) ? d.marks.filter(valid) : [];
    } catch { return []; }
  }

  /** Stores a play's marks; false when the device would not keep them (a private window, a full store). */
  function save(storage, script, marks) {
    try {
      if (!marks.length) storage.removeItem(KEY + script.id);
      else storage.setItem(KEY + script.id, JSON.stringify({ format: 1, script: script.id, title: script.title || null, marks }));
      return true;
    } catch { return false; }
  }

  function prefs(storage) {
    try {
      const p = JSON.parse((storage && storage.getItem(PREFS_KEY)) || 'null') || {};
      return { show: p.show !== false, hue: HUES.includes(p.hue) ? p.hue : HUES[0] };
    } catch { return { show: true, hue: HUES[0] }; }
  }
  function savePrefs(storage, p) {
    try { storage.setItem(PREFS_KEY, JSON.stringify({ show: !!p.show, hue: p.hue })); return true; } catch { return false; }
  }

  /** The scripts with marks on this device, A to Z: { script, title, count } (Library's Marks line, Decision 087). */
  function scripts(storage) {
    const out = [];
    try {
      for (let i = 0; i < storage.length; i++) {
        const k = storage.key(i);
        if (!k || !k.startsWith(KEY) || k === PREFS_KEY) continue;
        let d = null;
        try { d = JSON.parse(storage.getItem(k)); } catch { d = null; }
        const n = d && Array.isArray(d.marks) ? d.marks.filter(valid).length : 0;
        if (n) out.push({ script: d.script || k.slice(KEY.length), title: d.title || null, count: n });
      }
    } catch { return []; }
    return out.sort((a, b) => String(a.title || a.script).localeCompare(String(b.title || b.script), 'en', { sensitivity: 'base' }));
  }

  /** Every play's marks on this device, for the person's own export (docs/EXPORT.md `marks[]`). */
  function exportRows(storage) {
    const rows = [];
    try {
      const keys = [];
      for (let i = 0; i < storage.length; i++) {
        const k = storage.key(i);
        if (k && k.startsWith(KEY) && k !== PREFS_KEY) keys.push(k);
      }
      keys.sort();
      for (const k of keys) {
        let d = null;
        try { d = JSON.parse(storage.getItem(k)); } catch { d = null; }
        if (!d || !Array.isArray(d.marks)) continue;
        for (const m of d.marks.filter(valid)) {
          rows.push({ script: d.script || k.slice(KEY.length), title: d.title || null, revision: m.revision || null, line: m.line,
                      start: m.start, end: m.end, kind: m.kind, text: m.text, hue: m.hue || null, label: m.label ?? null,
                      note: m.note ?? null, created: m.created ? new Date(m.created).toISOString() : null,
                      updated: m.updated ? new Date(m.updated).toISOString() : null });
        }
      }
    } catch { /* storage blocked: nothing to export */ }
    return rows;
  }

  return { KINDS, SPAN, HUES, CONTEXT, EVIDENCE, LABEL_MAX, KEY, PREFS_KEY, scripts, isWord, snapWords, pointAfter, make, fromSelection, add,
           remove, update, bestIn, place, order, at, load, save, prefs, savePrefs, exportRows };
})();
if (typeof module !== 'undefined') module.exports = MarksCore;
