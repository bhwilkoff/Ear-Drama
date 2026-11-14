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
  const SPREAD_MIN = 900;

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

  return { SIZES, DEFAULT_SIZE, SPACING, LAYOUTS, SPREAD_MIN, normalizePrefs, perSpread, pageAt, pageCount, lineAtPage,
           spreadStart, turn, swipeTurn, tapZone, keyTurn, pageLabel, remember, runsOf, spaceBetween };
})();
