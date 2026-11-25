/**
 * Casting an episode by ear (PLAYS-DESIGN §13 item 10, WEB-DESIGN §4.22; Decision 088.3), as plain
 * functions over OwnCore: which line is lit, what has been heard, what a tap does, what a key means.
 * No DOM, no audio, no storage, so js/ear.test.js runs this file as shipped.
 *
 * NOTHING HERE PROPOSES A SPEAKER. A line is somebody's only by a tap, or by coming after one while
 * the episode played (OwnCore.castOf). It is told where the audio is, and never hears it.
 */
const EarCore = (() => {
  'use strict';
  const O = OwnCore;

  /** A first listen starts slow (R4 §2.4 rule 2); Back goes this far. */
  const SPEED = 0.75;
  const BACK_S = 5;
  /** The shortest a line plays for on Hear it: a cue's share can be a tenth of a second. */
  const LEAST_MS = 700;

  /** What tells this transcript from another: its words and its times. */
  function signature(cues) {
    return PlaysCore.fnv1a64(cues.map(c => `${c.at[0]}-${c.at[1]} ${c.text}`).join('\n')).toString(16);
  }

  /** null when these cues can be cast, or why not ('no_lines', 'too_many_lines'). */
  function refusalOf(doc) {
    if (!doc.lines.length) return 'no_lines';
    return doc.lines.length > O.MAX_LINES ? 'too_many_lines' : null;
  }

  /** The parts in the order they were named, which is their number and their hue: `names`, then any the lines hold. */
  function partsOf(doc, names) {
    const cast = O.castOf(doc);
    const n = new Map(names.map(x => [x, 0]));
    for (const l of doc.lines) { const who = cast.get(l.k); if (typeof who === 'string') n.set(who, (n.get(who) || 0) + 1); }
    return [...n].map(([name, lines]) => ({ name, lines }));
  }

  /**
   * A part's hue by the one rule every surface shares (PlayScript.partHue, EarCore.hue on Apple): the first seven parts
   * with a line, largest first, ties by who was named first; the rest, and a part with no line yet, have none.
   */
  function hueOf(name, parts) {
    const ranked = parts.map((p, i) => ({ p, i })).filter(x => x.p.lines > 0)
      .sort((a, b) => b.p.lines - a.p.lines || a.i - b.i);
    const at = ranked.findIndex(x => x.p.name === name);
    return at >= 0 && at < PlaysCore.PART_HUES.length ? PlaysCore.PART_HUES[at] : 'none';
  }

  /**
   * The lines as they are drawn: `{ k, text, kind, who, named }`. `who` is a name, OwnCore.OUT, or null; `named`
   * says the speaker (or Left out) is not the line above's, so it is printed.
   */
  function rows(doc) {
    const cast = O.castOf(doc);
    let before = null;
    return doc.lines.map(l => {
      const who = l.kind === 'open' || l.kind === 'speech' ? cast.get(l.k) : null;
      const row = { k: l.k, text: l.text, kind: l.kind, who, named: who !== null && who !== before };
      before = who;
      return row;
    });
  }

  /**
   * One sitting. `S.doc` is OwnCore's; every change makes a new one. `lit` is the line being said (0 before
   * the first). `tick` is told the audio's place as it plays; `jumped` that the place was moved by hand, so
   * the lines between are not heard.
   */
  function session({ doc, names = [], takes = [] }) {
    const S = { doc, names: [...names], takes: new Set(takes), lit: 0 };
    const renames = [];   // the order of the names before each rename, for its Undo
    let from = 0;   // the last line the audio reached without a jump
    const env = () => ({ takes: [...S.takes] });
    const take = (r) => { if (!r.refusal) S.doc = r.doc; return r.refusal; };

    /** Where the audio is now. While `playing`, the line and those since the last tick are heard. Answers what changed. */
    S.tick = (ms, playing) => {
      const k = O.lineAt(S.doc, ms);
      const moved = k !== S.lit;
      S.lit = k;
      if (!playing || !k) return { moved, heard: false };
      const next = O.hear(S.doc, k, from);
      from = k;
      if (next === S.doc) return { moved, heard: false };
      // A carried part never reaches a line that was recorded as something else.
      if (S.takes.size) {
        const was = O.castOf(S.doc), now = O.castOf(next);
        if (S.doc.lines.some(l => l.id && S.takes.has(l.id) && was.get(l.k) !== now.get(l.k))) { from = 0; return { moved, heard: false }; }
      }
      S.doc = next;
      return { moved, heard: true };
    };
    S.jumped = () => { from = 0; };

    /** The lit line, and those after it as they are heard, are `name`'s. A refusal, or null. */
    S.give = (name) => (S.lit ? take(O.tap(S.doc, S.lit, { role: name }, env())) : 'no_such_line');
    S.leaveOut = () => (S.lit ? take(O.tap(S.doc, S.lit, { out: true }, env())) : 'no_such_line');
    /** Names a voice. With a line lit it is theirs, as a tap is: `{ name, refusal }`. */
    S.add = (raw) => {
      const name = O.partName(O.normalize(raw));
      const why = O.partNameRefusal(name);
      if (why) return { name, refusal: why };
      const known = S.parts().some(p => p.name === name);
      const refusal = S.lit ? S.give(name) : null;
      if (!refusal && !known) S.names.push(name);
      return { name, refusal };
    };
    S.undo = () => {
      const why = take(O.apply(S.doc, { op: 'undo' }));
      while (!why && renames.length && renames[renames.length - 1].depth > S.doc.undo.length) S.names = renames.pop().names;
      return why;
    };
    /** A part's name on every line of theirs, and in its place in the order; a name another part has joins the two. One step. */
    S.rename = (from, raw) => {
      const name = O.partName(O.normalize(raw));
      const all = S.parts();
      const held = all.find(p => p.name === from);
      const why = O.partNameRefusal(name) || (held ? null : 'no_such_part');
      if (why) return { name, refusal: why };
      if (name === from) return { name, refusal: null };
      const before = S.names;
      if (held.lines) {
        const refusal = take(O.apply(S.doc, { op: 'rename', part: from, to: name }, env()));
        if (refusal) return { name, refusal };
        renames.push({ depth: S.doc.undo.length, names: before });
      }
      const order = all.map(p => p.name);
      S.names = order.includes(name) ? order.filter(n => n !== from) : order.map(n => (n === from ? name : n));
      return { name, refusal: null };
    };
    /** One line alone, from its sheet: a part, Direction or Sound. The line after it keeps the cast it had. */
    S.assign = (k, to) => take(O.apply(S.doc, { op: 'assign', line: k, to }, env()));
    S.leaveOutLine = (k) => take(O.leaveOutHeard(S.doc, k, env()));
    S.apply = (op) => take(O.apply(S.doc, op, env()));

    S.line = (k) => S.doc.lines.find(l => l.k === k) || null;
    S.parts = () => partsOf(S.doc, S.names);
    S.who = (k) => O.castOf(S.doc).get(k);
    S.count = () => O.castCount(S.doc);
    S.canUndo = () => S.doc.undo.length > 0;
    /** The next of a part's lines to play, after the one played last: how a person checks whether two voices are one. */
    const last = new Map();
    S.sample = (name) => {
      const cast = O.castOf(S.doc);
      const mine = S.doc.lines.filter(l => l.at && cast.get(l.k) === name);
      if (!mine.length) return null;
      const i = mine.findIndex(l => l.k === last.get(name));
      const l = mine[(i + 1) % mine.length];
      last.set(name, l.k);
      return l;
    };
    return S;
  }

  /** How long a line is played for on its own, in milliseconds. */
  const spanOf = (l) => [l.at[0], Math.max(l.at[1], l.at[0] + LEAST_MS)];

  /** What a key does here, or null: `{ act: 'part', n }`, 'toggle', 'back', 'undo'. Keys held with another are the browser's, but Undo's own. */
  function keyOf(e) {
    const k = e.key;
    if ((e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && k.toLowerCase() === 'z') return { act: 'undo' };
    if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return null;
    if (k >= '1' && k <= '9' && k.length === 1) return { act: 'part', n: Number(k) - 1 };
    if (k === ' ') return { act: 'toggle' };
    if (k === 'ArrowLeft') return { act: 'back' };
    if (k === 'u' || k === 'U') return { act: 'undo' };
    return null;
  }

  /** Where casting is taken up again, in milliseconds: the place it was left, never past the last line. */
  function placeOf(ear, doc) {
    const last = doc.lines.reduce((m, l) => (l.at ? Math.max(m, l.at[1]) : m), 0);
    const p = ear && Number.isFinite(ear.place) ? ear.place : 0;
    return p > 0 && p < last ? p : 0;
  }

  return { SPEED, BACK_S, LEAST_MS, signature, refusalOf, partsOf, hueOf, rows, session, spanOf, keyOf, placeOf };
})();
