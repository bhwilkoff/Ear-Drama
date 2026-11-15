/**
 * The script reader's arithmetic (WEB-DESIGN §4.16, Decision 076): the reader's settings, which
 * line a page shows first, where a page turn lands, and what a swipe or a tap means. No DOM, so
 * js/reader.test.js runs this file as shipped. js/reader.js measures the page and calls these.
 *
 * A page is never stored: the reading position is a line id, and a page is wherever that line
 * falls in the current layout (size, spacing, window). Changing any of them re-lays the script
 * out and turns to the page holding the line that was at the top.
 */
const ReaderCore = (() => {
  'use strict';

  /** Text size steps, as a share of the reading body size; the third is the default. */
  const SIZES = [0.875, 0.9375, 1, 1.125, 1.25, 1.5, 1.75];
  const DEFAULT_SIZE = 2;
  /** Line spacing: the reader's three choices, as a line height. */
  const SPACING = { tight: 1.35, normal: 1.55, loose: 1.8 };
  const LAYOUTS = ['pages', 'scroll'];
  /** Two facing pages once the reading area is this wide (CSS pixels). */
  const SPREAD_MIN = 860;
  /** A page this many em wide sets the speaker's name in a gutter beside the words; narrower, over them. */
  const GUTTER_MIN_EM = 30;

  /** Settings as stored (or not): anything unknown falls back to the default. Pages by default (owner, Decision 076). */
  function normalizePrefs(raw) {
    const p = raw && typeof raw === 'object' ? raw : {};
    const size = Number.isInteger(p.size) && p.size >= 0 && p.size < SIZES.length ? p.size : DEFAULT_SIZE;
    return {
      layout: LAYOUTS.includes(p.layout) ? p.layout : 'pages',
      size,
      spacing: Object.prototype.hasOwnProperty.call(SPACING, p.spacing) ? p.spacing : 'normal',
    };
  }

  /** How many pages one screen shows: two from SPREAD_MIN, else one. */
  const perSpread = (width) => (width >= SPREAD_MIN ? 2 : 1);

  /** A column's page, from its left edge's offset into the flow and one page's width plus the gap. */
  const pageAt = (offset, unit) => Math.max(0, Math.round(offset / unit));

  /** Pages in a flow `width` wide (the flow's scroll width), each `unit` apart with `gap` between. */
  const pageCount = (width, unit, gap) => Math.max(1, Math.round((width + gap) / unit));

  /**
   * The reading position on a page: the first line still showing on it, which is the line carried
   * over from the page before when there is one (so a restore never skips words). `starts[i]` and
   * `ends[i]` are the pages where line i begins and ends, in reading order. -1 when none.
   */
  function lineAtPage(starts, ends, page) {
    for (let i = 0; i < ends.length; i++) {
      if (ends[i] >= page && starts[i] <= page) return i;
      if (starts[i] > page) return i;
    }
    return ends.length ? ends.length - 1 : -1;
  }

  /** The first page of the screen that shows `page`: spreads begin on even pages. */
  const spreadStart = (page, per) => Math.floor(page / per) * per;

  /** Where a turn lands: one screen on or back, never past the first or the last. */
  function turn(page, delta, per, count) {
    const last = spreadStart(Math.max(0, count - 1), per);
    return Math.min(last, Math.max(0, spreadStart(page, per) + delta * per));
  }

  /** A finished drag: -1 back, 1 on, 0 stay. Past a fifth of the width, or a flick (30 px at 0.4 px/ms). */
  function swipeTurn(dx, ms, width) {
    const fast = Math.abs(dx) >= 30 && Math.abs(dx) / Math.max(1, ms) >= 0.4;
    if (Math.abs(dx) < width / 5 && !fast) return 0;
    return dx < 0 ? 1 : -1;
  }

  /** A tap on the page: the outer fifth of either edge turns, the middle does not. */
  function tapZone(x, width) {
    if (x < width / 5) return 'prev';
    if (x > width * 4 / 5) return 'next';
    return 'middle';
  }

  /** The keys that turn a page (pedals send arrows or Page Up/Down): 1, -1, 'first', 'last', or 0. */
  function keyTurn(key, shift) {
    if (key === 'ArrowRight' || key === 'ArrowDown' || key === 'PageDown') return 1;
    if (key === 'ArrowLeft' || key === 'ArrowUp' || key === 'PageUp') return -1;
    if (key === ' ' || key === 'Spacebar') return shift ? -1 : 1;
    if (key === 'Home') return 'first';
    if (key === 'End') return 'last';
    return 0;
  }

  /** "12 of 140", or "12–13 of 140" for a spread. */
  function pageLabel(page, per, count) {
    const a = page + 1;
    const b = Math.min(count, page + per);
    return b > a ? `${a}–${b} of ${count}` : `${a} of ${count}`;
  }

  /** Positions kept per script: newest first, at most `keep`. */
  function remember(store, scriptID, entry, keep = 60) {
    const out = { [scriptID]: { ...((store || {})[scriptID] || {}), ...entry } };
    for (const [k, v] of Object.entries(store || {})) if (k !== scriptID && Object.keys(out).length < keep) out[k] = v;
    return out;
  }

  /**
   * A line as printed runs: `{ kind, text, at }`. A speech's pieces are `say` (the words) or
   * `aside` (a printed direction inside it); a block's text is `plain`, with its `_italic_` marks
   * drawn as `em` and never shown. `at` is the run's offset into PlaysCore.lineText(line), the
   * string a mark anchors to (line id, start, end; Decision 076 S5), so a selection maps back.
   */
  function runsOf(line) {
    const runs = [];
    /** One printed piece, its `_italic_` marks toggling the face: said words turn italic, an aside turns roman. */
    const split = (text, at, piece, said, base, flipped) => {
      let on = false;
      for (const seg of text.split('_')) {
        if (seg) runs.push({ kind: on ? flipped : base, text: seg, at, piece, said });
        at += seg.length + 1;
        on = !on;
      }
    };
    if (line.kind === 'speech' && Array.isArray(line.parts)) {
      let at = 0;
      line.parts.forEach((piece, i) => {
        const key = Object.keys(piece)[0];
        const text = piece[key] || '';
        if (i) at += 1;
        if (key === 'say') split(text, at, i, true, 'say', 'em');
        else split(text, at, i, false, 'aside', 'plain');
        at += text.length;
      });
      return runs;
    }
    split(line.source || '', 0, 0, false, 'plain', 'em');
    return runs;
  }

  /** Whether a space is drawn before a printed piece: not before closing punctuation, not after an opening one. */
  const spaceBetween = (before, after) => !/^[.,;:!?)\]’”…—-]/.test(after) && !/[(\[“‘—-]$/.test(before);

  /*
   * The Ear Drama page (docs/research/design/R2-play-typography.md, PLAYS-DESIGN §2.7 rule 10): how a
   * line is set, as plain data. Every run keeps its offset into lineText, so marks still anchor; a
   * character the page leaves out (a printed speaker label's period, a direction's enclosing bracket)
   * is simply not drawn, and a line break inside prose is drawn as the space it stands for.
   */

  /** A said row may begin with quotes, a dash, a bracket or an italic mark before its capital. */
  const ROW_START = /^[\s'"‘’“”(\[_—–-]*(\S)/;
  /**
   * Whether a speech's printed line breaks are verse (kept) or a transcriber's wrapping (reflowed):
   * verse when the speech has a break and every row after a break begins with a capital, and its rows
   * are not mostly as long as a wrapped prose line (60 characters and more).
   */
  function isVerse(texts) {
    const rows = [];
    let after = [];
    for (const t of texts) {
      const parts = String(t || '').split('\n');
      parts.forEach((p, i) => { rows.push(p); if (i) after.push(p); });
    }
    after = after.filter(r => r.trim());
    if (!after.length) return false;
    for (const r of after) {
      const m = ROW_START.exec(r);
      if (!m || m[1] === m[1].toLowerCase() || !/\p{L}/u.test(m[1])) return false;
    }
    const full = rows.map(r => r.trim()).filter(Boolean);
    const body = full.slice(0, -1);
    const long = body.filter(r => r.length >= 60).length;
    if (body.length && long / body.length >= 0.7) return false;
    return full.length >= 3 || (full[0] || '').length < 50;
  }

  /** An aside whose words begin "sound of", "noise of" or "music" is a cue, whatever the parser called it. */
  const CUE_WORDS = /^[\s(\[_]*(?:(?:sounds?|noises?) of\b|music\b)/i;

  /**
   * How a line is set. A speech gives `speeches`: one, or more when the printed text runs a second
   * speaker's speech into the first ("Why not?\nGRACE" then ". Never mind why.", a parser miss the page
   * still attributes); each `{ role, name, rows }`, `name` null for the line's own role (drawn from
   * line.role, outside the printed words) or the printed name run; each row `{ cue, indent, runs }`.
   * Verse keeps a row per printed line (`indent` when the printed line was indented); prose is one row,
   * broken only by a cue (a sound piece, or an aside that is a sound or music). A block gives one row,
   * its enclosing brackets left undrawn. `roles` is the script's role names.
   */
  function layoutOf(line, roles) {
    const runs = runsOf(line);
    // A direction printed wholly in italic marks ("[_Exeunt._]") is italic, not turned roman: the
    // marks set it apart from speech, which the page already does.
    const lettered = (rs) => rs.filter(r => /\p{L}/u.test(r.text));
    // A word or three printed in italics between said words that run on in lowercase ("in which _I_
    // have been") is the speaker's emphasis the parser took for a direction: drawn as said, in italic.
    if (line.kind === 'speech' && Array.isArray(line.parts)) {
      const key = (p) => Object.keys(p || {})[0];
      const stressed = new Set();
      line.parts.forEach((p, i) => {
        const prev = line.parts[i - 1], next = line.parts[i + 1];
        if (key(p) !== 'direction' || key(prev) !== 'say' || key(next) !== 'say') return;
        const words = String(p.direction || '').replace(/_/g, '').trim().split(/\s+/);
        if (words.length <= 3 && /^\s*\p{Ll}/u.test(next.say || '') && !/[.!?]["’”]?\s*$/.test(prev.say || '')) stressed.add(i);
      });
      // The parser's own emphasis (catalog `em`: the said parts printed in italics, 2026-11-14).
      for (const i of Array.isArray(line.em) ? line.em : []) stressed.add(i);
      for (const r of runs) if (stressed.has(r.piece)) { r.said = true; r.kind = 'em'; }
    }
    const byPiece = new Map();
    for (const r of runs) if (!r.said) (byPiece.get(r.piece) || byPiece.set(r.piece, []).get(r.piece)).push(r);
    for (const rs of byPiece.values()) {
      const lt = lettered(rs);
      const turned = line.kind === 'speech' ? 'plain' : 'em';
      if (lt.length && lt.every(r => r.kind === turned)) for (const r of rs) r.kind = line.kind === 'speech' ? 'aside' : 'plain';
    }
    if (!(line.kind === 'speech' && Array.isArray(line.parts))) {
      const out = runs.map(r => ({ ...r, text: r.text.replace(/\n\s*/g, (m) => ' '.padEnd(m.length)) }));
      const first = out[0], last = out[out.length - 1];
      const src = (line.source || '').replace(/_/g, '');
      const opens = /^\s*[\[(]/.test(src);
      const closes = /[\])]\s*$/.test(src);
      const bracketed = opens && (closes || !/[\])]/.test(src));
      if (first && bracketed) {
        const m = /^\s*[\[(]\s*/.exec(first.text);
        if (m) { first.text = first.text.slice(m[0].length); first.at += m[0].length; }
      }
      if (last && bracketed && closes) last.text = last.text.replace(/\s*[\])]\s*$/, '');
      const cue = line.kind !== 'direction';
      return { rows: [{ cue, indent: false, runs: out.filter(r => r.text) }] };
    }
    const keyOf = (i) => Object.keys(line.parts[i] || {})[0];
    const textOf = (i) => { const p = line.parts[i] || {}; return p[Object.keys(p)[0]] || ''; };
    const isCue = (i) => keyOf(i) === 'sound' || (keyOf(i) === 'direction' && CUE_WORDS.test(textOf(i)));
    const names = [...(roles || [])].filter(n => n && n.length >= 2).sort((a, b) => b.length - a.length);
    const runIn = (text, k) => {
      for (const n of names) {
        if (!text.startsWith(n, k + 1)) continue;
        const rest = text.slice(k + 1 + n.length);
        if (/^\s*$/.test(rest) || /^[.:]\s/.test(rest)) return n;
      }
      return null;
    };
    // A run-in speaker's break is not a verse break.
    const said = line.parts.filter(p => Object.keys(p)[0] === 'say').map(p => {
      let t = p.say || '';
      for (let k = t.indexOf('\n'); k >= 0; k = t.indexOf('\n', k + 1)) if (runIn(t, k)) t = `${t.slice(0, k)} ${t.slice(k + 1)}`;
      return t;
    });
    const verse = isVerse(said);
    const speeches = [];
    let sp, row, label = false;
    const start = (role, name) => { sp = { role, name, rows: [] }; speeches.push(sp); row = null; };
    const rowNow = (key) => {
      if (!row || row.key !== key) { row = { cue: !!key, indent: false, runs: [], key }; sp.rows.push(row); }
      return row;
    };
    const push = (r, text, at) => { if (text) rowNow(false).runs.push({ ...r, text, at }); };
    start(line.role || '', null);
    for (const r of runs) {
      if (isCue(r.piece)) {
        const cr = rowNow(`p${r.piece}`);
        cr.runs.push({ ...r, text: r.text.replace(/\n\s*/g, (m) => ' '.padEnd(m.length)) });
        continue;
      }
      if (row && row.cue) row = null;
      if (!r.said) { push(r, r.text.replace(/\n\s*/g, (m) => ' '.padEnd(m.length)), r.at); continue; }
      let text = r.text, at = r.at;
      if (label) {
        const m = /^\s*[.:]?\s*/.exec(text);
        text = text.slice(m[0].length); at += m[0].length;
        if (!text) continue;
        label = false;
      }
      // A second speaker run in: "\nNAME" at the end of the words, or "\nNAME. " before more.
      for (;;) {
        let hit = null;
        for (let k = text.indexOf('\n'); k >= 0 && !hit; k = text.indexOf('\n', k + 1)) {
          const n = runIn(text, k);
          if (n) hit = { k, n };
        }
        if (!hit) break;
        emit(r, text.slice(0, hit.k), at);
        start(hit.n, { ...r, kind: 'name', text: hit.n, at: at + hit.k + 1, said: false });
        const after = text.slice(hit.k + 1 + hit.n.length);
        const m = /^[.:]?\s*/.exec(after);
        at += hit.k + 1 + hit.n.length + m[0].length;
        text = after.slice(m[0].length);
        if (!text) { label = true; break; }
      }
      if (text) emit(r, text, at);
    }
    function emit(r, text, at) {
      if (!verse) { push(r, text.replace(/\n/g, ' '), at); return; }
      const segs = text.split('\n');
      segs.forEach((seg, i) => {
        if (i) { row = { cue: false, indent: false, runs: [], key: false }; sp.rows.push(row); }
        if (i || !row || !row.runs.length) {
          const lead = /^\s*/.exec(seg)[0].length;
          if (i && lead >= 2) row = Object.assign(rowNow(false), { indent: true });
          seg = seg.slice(lead); at += lead;
        }
        push(r, seg, at);
        at += seg.length + 1;
      });
    }
    for (const s of speeches) {
      s.rows = s.rows.filter(rw => rw.runs.length);
      for (const rw of s.rows) delete rw.key;
    }
    return { verse, speeches };
  }

  /** The last words of a speech a cue is heard on: from the last sentence break, at most the whole text. */
  function cueTail(text) {
    const t = String(text || '');
    const re = /[.!?;:—](?:['"’”)\]]*)\s+(?=\S)/g;
    let at = 0, m;
    while ((m = re.exec(t))) if (m.index + m[0].length < t.trimEnd().length - 2) at = m.index + m[0].length;
    return at;
  }

  /** Where Close goes: back when the reader was opened from inside the app, else the play's page (or the production). */
  function closeTo(inApp, studio, production, id) {
    if (inApp) return 'back';
    return studio ? `?production=${encodeURIComponent(production)}` : `?play=${encodeURIComponent(id)}`;
  }

  /** J and K (either case) move to my next and previous line: +1, -1, else 0. */
  const myLineStep = (key) => (key === 'j' || key === 'J' ? 1 : key === 'k' || key === 'K' ? -1 : 0);

  /* ---- The read-along (PLAYS-DESIGN §2.11): the script follows the listen-through ---- */

  /** The line the listen plan's entry `index` speaks; null past either end. */
  const alongLine = (plan, index) => (index >= 0 && index < plan.length ? plan[index].lineID : null);

  /**
   * The line a rendered mix is speaking at `seconds`: the last placement that has begun, and
   * null once the last has ended. A gap between lines keeps the line before it.
   */
  function alongLineAt(placements, rate, seconds) {
    const f = seconds * rate;
    let at = null;
    for (const p of placements) {
      if (p.start <= f) at = p; else break;
    }
    if (!at) return null;
    const last = at === placements[placements.length - 1];
    return last && f >= at.start + at.frames ? null : at.lineID;
  }

  /**
   * Whether the reader turns itself to the line heard. A swipe, tap or scroll (`away`) stops it
   * and offers "Back to the line" while something plays; `back` returns the line now heard and
   * follows again.
   */
  function alongFollow() {
    let following = true;
    let now = null;
    const out = () => ({ turn: following && now !== null, back: !following && now !== null });
    return {
      line(id) { now = id; return out(); },
      away() { following = false; },
      back() { following = true; return now; },
      get following() { return following; },
    };
  }

  /** The TV panel's three lines: the one before, the one heard, the one after (null at an end). */
  function alongPanel(script, lineID) {
    const i = script.lines.findIndex(l => l.id === lineID);
    if (i < 0) return [null, null, null];
    return [script.lines[i - 1] || null, script.lines[i], script.lines[i + 1] || null];
  }

  return { alongLine, alongLineAt, alongFollow, alongPanel, closeTo, myLineStep, SIZES, DEFAULT_SIZE, SPACING, LAYOUTS, SPREAD_MIN, GUTTER_MIN_EM, normalizePrefs, perSpread, pageAt, pageCount, lineAtPage,
           spreadStart, turn, swipeTurn, tapZone, keyTurn, pageLabel, remember, runsOf, spaceBetween, isVerse, layoutOf, cueTail };
})();
