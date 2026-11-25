/**
 * Own scripts (Decision 088.3; docs/research/design/R4-record-anything.md): a script a person pastes
 * or opens, and a transcript they cast by ear, as plain functions of plain data. No DOM, no storage,
 * no audio, no other file, so js/own-core.test.js runs this file as shipped and OwnScript.swift and
 * OwnScript.kt mirror it function for function (docs/research/design/R4-core-port-brief.md). The
 * golden cases every stack runs: catalog/tests/golden/own_script_parse.json, own_script_ops.json,
 * ear_cast_lines.json.
 *
 * Three jobs:
 *   parse(text)          the ten-rule grammar: proposes who says what (R4 §2.2)
 *   apply(doc, op, env)  the parts page: assign, split, join, rename, edit, leave out, add, undo
 *   fromCues(cues)       a transcript as sentence lines with times, cast by tapping (R4 §2.4)
 * and toScript(doc, meta): the castable shape the reader and the recorder already read.
 *
 * NOTHING HERE WRITES A WORD. Every line's text is a slice of the normalized text (rows joined by
 * one line break), and only a person's own Edit words changes it.
 *
 * OFFSETS ARE UTF-16 CODE UNITS of the line's `text`, as a mark's are of lineText (PLAYS-DESIGN
 * §2.10): JavaScript's and Kotlin's own index, Swift's `utf16` view. A cut never lands inside a
 * character a person sees (cutAt). NAME LENGTHS count code points; BYTES are UTF-8.
 *
 * No regular expression decides a rule: labels, cues, headings, brackets and sentences are read by
 * the character, so three regex dialects cannot disagree and no text can make one backtrack. The
 * only patterns are single character classes (\p{Lu}, \p{L}, ...), tested one code point at a time.
 */
const OwnCore = (() => {
  'use strict';

  /* ---- Caps ---- */

  /** A pasted text, and a shared script's canonical lines, in UTF-8 bytes. */
  const MAX_BYTES = 400000;
  const MAX_LINES = 6000;
  /** The Worker's name gate (worker/src/plays-names.js MAX_NAME), in UTF-16 units as it counts. */
  const MAX_PART_NAME = 40;
  /** worker/src/plays-manifest.js validRow. */
  const MAX_TITLE = 300;
  const OWN_ID = /^own-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const LINE_ID = /^L[0-9]{4}[a-z]*$/;

  /* ---- Characters, one code point at a time ---- */

  const cache = new Map();
  /** A bit set of what a code point is, so a character class is asked of it once. */
  const UPPER = 1, LOWER = 2, LETTER = 4, MARK = 8, DIGIT = 16;
  function classOf(cp) {
    let c = cache.get(cp);
    if (c !== undefined) return c;
    const ch = String.fromCodePoint(cp);
    c = 0;
    if (/^[\p{Lu}\p{Lt}]$/u.test(ch)) c |= UPPER;
    if (/^\p{Ll}$/u.test(ch)) c |= LOWER;
    if (/^\p{L}$/u.test(ch)) c |= LETTER;
    if (/^\p{M}$/u.test(ch)) c |= MARK;
    if (/^\p{Nd}$/u.test(ch)) c |= DIGIT;
    cache.set(cp, c);
    return c;
  }
  const is = (cp, mask) => cp !== undefined && (classOf(cp) & mask) !== 0;
  const width = (cp) => (cp > 0xffff ? 2 : 1);
  const SPACE = 32, TAB = 9;
  const isGap = (u) => u === SPACE || u === TAB;
  const isBlankUnit = (u) => u === SPACE || u === TAB || u === 10;
  function trim(s) {
    let a = 0, b = s.length;
    while (a < b && isBlankUnit(s.charCodeAt(a))) a += 1;
    while (b > a && isBlankUnit(s.charCodeAt(b - 1))) b -= 1;
    return s.slice(a, b);
  }
  const skipGap = (s, p) => { while (p < s.length && isGap(s.charCodeAt(p))) p += 1; return p; };
  /** Words between runs of spaces, tabs and line breaks. */
  function wordsOf(s) {
    const out = [];
    let at = -1;
    for (let i = 0; i <= s.length; i++) {
      const gap = i === s.length || isBlankUnit(s.charCodeAt(i));
      if (!gap && at < 0) at = i;
      else if (gap && at >= 0) { out.push(s.slice(at, i)); at = -1; }
    }
    return out;
  }
  function utf8Length(s) {
    let n = 0;
    for (let i = 0; i < s.length; i++) {
      const u = s.charCodeAt(i);
      if (u < 0x80) n += 1;
      else if (u < 0x800) n += 2;
      else if (u >= 0xd800 && u <= 0xdbff && i + 1 < s.length) { n += 4; i += 1; } else n += 3;
    }
    return n;
  }

  /* ---- Normalizing a text ---- */

  /** Dropped: a BOM, soft hyphens, zero-width spaces, direction marks, controls. ZWJ and ZWNJ stay (they shape words and emoji). */
  const dropped = (u) => u < 9 || u === 14 || u === 15 || (u > 15 && u < 32) || (u >= 0x7f && u <= 0x9f && u !== 0x85)
    || u === 0xad || u === 0x200b || u === 0x200e || u === 0x200f || u === 0x2060 || u === 0xfeff
    || (u >= 0x202a && u <= 0x202e) || (u >= 0x2066 && u <= 0x2069);
  const newline = (u) => u === 10 || u === 11 || u === 12 || u === 13 || u === 0x85 || u === 0x2028 || u === 0x2029;
  const wideSpace = (u) => u === 0xa0 || u === 0x1680 || (u >= 0x2000 && u <= 0x200a) || u === 0x202f || u === 0x205f || u === 0x3000;

  /**
   * The text every rule reads and every line slices: line ends one `\n`, every other space one
   * U+0020 (a tab stays), unseen characters dropped, a lone surrogate U+FFFD, NFC, then the pairs
   * that mark italics and bold dropped (`_so_`, `**so**`). Quotes, dashes and words are untouched.
   */
  function normalize(raw) {
    const t = String(raw === undefined || raw === null ? '' : raw);
    let out = '';
    let from = 0;
    const put = (i, s) => { out += t.slice(from, i) + s; from = i + 1; };
    for (let i = 0; i < t.length; i++) {
      const u = t.charCodeAt(i);
      if (u >= 32 && u < 0x7f) continue;
      if (u >= 0xd800 && u <= 0xdbff) {
        const v = i + 1 < t.length ? t.charCodeAt(i + 1) : 0;
        if (v >= 0xdc00 && v <= 0xdfff) i += 1; else put(i, '�');
      } else if (u >= 0xdc00 && u <= 0xdfff) put(i, '�');
      else if (newline(u)) put(i, u === 13 && i + 1 < t.length && t.charCodeAt(i + 1) === 10 ? '' : '\n');
      else if (wideSpace(u)) put(i, ' ');
      else if (dropped(u)) put(i, '');
    }
    out += t.slice(from);
    return unmark(out.normalize('NFC'));
  }

  const asciiWord = (u) => (u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
  /**
   * Drops the marks around a span: one `_` that does not join two letters (`snake_case` keeps it),
   * and `**`. A run of any other length is the writer's own (`____` to fill in, `* * *`).
   */
  function unmark(t) {
    let out = '', from = 0, i = 0;
    while (i < t.length) {
      const u = t.charCodeAt(i);
      if (u !== 95 && u !== 42) { i += 1; continue; }
      let j = i + 1;
      while (j < t.length && t.charCodeAt(j) === u) j += 1;
      const n = j - i;
      const inner = i > 0 && j < t.length && asciiWord(t.charCodeAt(i - 1)) && asciiWord(t.charCodeAt(j));
      if ((u === 95 && n === 1 && !inner) || (u === 42 && n === 2)) { out += t.slice(from, i); from = j; }
      i = j;
    }
    return out + t.slice(from);
  }

  /* ---- Names ---- */

  const set = (words) => new Set(words.split(' '));
  /** First words that head a list or a note, never a speaker (R4 §2.2). */
  const NOT_NAME = set('ACT SCENE SCENES NOTE NOTES CAST DATE TITLE BY AUTHOR WRITTEN SETTING TIME PLACE CHARACTERS COPYRIGHT END '
    + 'FINIS DRAMATIS PERSONS SYNOPSIS COSTUMES PROPERTIES SCENERY CURTAIN FADE CUT TRANSCRIBED SOURCE SERIES PROGRAM PRODUCTION '
    + 'HTTP HTTPS AT FOOTNOTE FOOTNOTES APPENDIX INDEX CONTENTS CHAPTER ILLUSTRATION TABLEAU ENTER EXIT EXEUNT');
  /** Words said on their own ("YES.", "Stop."): never a speaker, but before a colon. */
  const COMMON = set('NO YES OH AH O WELL AY AYE NAY YEA INDEED TRUE NEVER GOOD HUSH COME STOP WHY WHAT NOW SO THEN THERE HERE THIS '
    + 'THAT HOW WHERE WHEN WHO AGAIN NOTHING EVERYTHING PERHAPS EXACTLY CERTAINLY SURELY THANKS PLEASE SILENCE PAUSE');
  /** Those that are speakers when printed in capitals ("HE.", "SIR.") and only words in lower case. */
  const COMMON_MIXED = set('I IT HE SHE WE YOU THEY SIR MADAM PEACE MANET FLOURISH SENNET ALARUM ALARUMS');
  /** An abbreviated title is part of the name it opens ("MRS. AUSTIN."), so the period after it does not end the label. */
  const TITLES = set('MR MRS MS DR ST LT CAPT COL GEN SGT REV PROF MME MLLE M MM MESSRS');
  /** Words a name may hold in lower case ("Man in Black"). */
  const SMALL = set('of the and in with on at to a an de la le von van der du del');
  const WORD_NUMBERS = set('ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN FIRST SECOND THIRD FOURTH FIFTH SIXTH SEVENTH EIGHTH '
    + 'NINTH TENTH LAST PRIMUS SECUNDUS TERTIUS QUARTUS QUINTUS PRIMA SECUNDA TERTIA QUARTA QUINTA SEXTA SEPTIMA OCTAVA NONA DECIMA');
  /** I to XXXIX: an act's, scene's or stanza's number. (VIC and CIVIL are words.) */
  const ROMAN = new Set();
  for (const tens of ['', 'X', 'XX', 'XXX']) for (const ones of ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX']) if (tens + ones) ROMAN.add(tens + ones);
  const isRoman = (w) => ROMAN.has(w);

  /** ASCII letters to capitals, every other character as it is, so offsets never move. */
  function asciiUpper(s) {
    let out = '', from = 0;
    for (let i = 0; i < s.length; i++) {
      const u = s.charCodeAt(i);
      if (u >= 97 && u <= 122) { out += s.slice(from, i) + String.fromCharCode(u - 32); from = i + 1; }
    }
    return out + s.slice(from);
  }

  /** A part's name as stored: one space between words, straight apostrophes, capitals, no label punctuation at its ends. */
  function partName(raw) {
    const words = wordsOf(String(raw));
    let s = words.join(' ').replace(/[‘’]/g, "'");
    const edge = (c) => c === ' ' || c === '.' || c === ':' || c === '@' || c === '_' || c === '^' || c === '：';
    let a = 0, b = s.length;
    while (a < b && edge(s[a])) a += 1;
    while (b > a && edge(s[b - 1])) b -= 1;
    s = s.slice(a, b);
    return s.toUpperCase();
  }

  /** null when a part may be called this (already through partName), or why not: 'empty', 'too_long', 'bad_name'. */
  function partNameRefusal(name) {
    if (!name) return 'empty';
    if (name.length > MAX_PART_NAME) return 'too_long';
    // The Worker's own refusal (plays-names.js): controls, zero-width and direction characters.
    for (let i = 0; i < name.length; i++) {
      const u = name.charCodeAt(i);
      if (u < 32 || u === 127 || (u >= 0x200b && u <= 0x200f) || (u >= 0x2028 && u <= 0x202e)) return 'bad_name';
    }
    return null;
  }

  /** Whether a printed name is in capitals ("OLD MAN", "McCOY", "1ST MAN"): one capital at least, no small letter but Mc and Mac. */
  function isCaps(name) {
    let upper = false;
    for (const w of wordsOf(name)) {
      let s = w;
      for (const p of ['Mac', 'Mc']) if (s.startsWith(p) && s.length > p.length && is(s.codePointAt(p.length), UPPER)) { s = s.slice(p.length); break; }
      for (const ch of s) {
        const cp = ch.codePointAt(0);
        if (is(cp, LOWER)) return false;
        if (is(cp, UPPER)) upper = true;
      }
    }
    return upper;
  }
  /** Whether a name in capitals and lower case reads as one: every word opens with a capital, a letter without case, a digit or `#` (not a digit alone), or is a small word. */
  function isTitled(name) {
    const words = wordsOf(name);
    return words.length > 0 && words.every((w, i) => {
      const cp = w.codePointAt(0);
      if (is(cp, UPPER) || (is(cp, LETTER) && !is(cp, LOWER))) return true;
      if (i === 0) return words.length > 1 && is(cp, DIGIT);
      return (is(cp, DIGIT) || w[0] === '#' || w[0] === '&' || SMALL.has(w));
    });
  }
  function hasLower(s) {
    for (const ch of s) if (is(ch.codePointAt(0), LOWER)) return true;
    return false;
  }
  const MAX_NAME_POINTS = 30;
  /** Any name at all: four words, a letter, and not the head of a list. */
  function nameOK(name, maxWords = 4) {
    const key = partName(name);
    const words = wordsOf(key);
    if (!words.length || words.length > maxWords || key.length > MAX_PART_NAME) return false;
    // A period and a space inside a name follow a title or an initial ("MRS. SMITH", "J. FOX"), never a word ("YES. NO").
    for (let i = 0; i < words.length - 1; i++) {
      if (words[i].endsWith('.') && !TITLES.has(words[i].slice(0, -1)) && [...words[i]].length !== 2
        && words[i + 1] !== 'OF' && !is(words[i + 1].codePointAt(0), DIGIT)) return false;
    }
    let head = words[0];
    while (head.endsWith('.') || head.endsWith("'")) head = head.slice(0, -1);
    if (NOT_NAME.has(head) || key === 'THE END') return false;
    if (words[0] === 'PAGE' && words.length > 1 && is(words[1].codePointAt(0), DIGIT)) return false;
    for (const ch of key) if (is(ch.codePointAt(0), LETTER)) return true;
    return false;
  }

  /** The end (exclusive) of the bracket opening at `p`, counting nested ones of its kind, or -1. */
  function bracketEnd(s, p) {
    const open = s.charCodeAt(p);
    const close = open === 40 ? 41 : 93;
    let depth = 0;
    for (let i = p; i < s.length; i++) {
      const u = s.charCodeAt(i);
      if (u === open) depth += 1;
      else if (u === close) { depth -= 1; if (depth === 0) return i + 1; }
    }
    return -1;
  }
  const opensBracket = (s, p) => p < s.length && (s.charCodeAt(p) === 40 || s.charCodeAt(p) === 91);

  const FORMS = ['colon', 'dot', 'gap', 'alone', 'mixed'];
  const nameChar = (cp) => is(cp, LETTER | MARK | DIGIT) || cp === 46 || cp === 39 || cp === 0x2019 || cp === 0x2018
    || cp === 38 || cp === 35 || cp === 45 || cp === 47 || cp === 32 || cp === 0xfffd;
  const skipDash = (s, p) => {
    if (s.startsWith('--', p)) { while (s[p] === '-') p += 1; return p; }
    return s[p] === '—' || s[p] === '–' ? p + 1 : p;
  };

  /**
   * The label a row opens with, read every way a label is printed, best first:
   * `[{ form, name, key, label, text }]`. `form` is 'colon', 'dot', 'gap', 'alone' or 'mixed'; `label`
   * is the printed slice; `text` is what is said, a direction beside the name first; `bare` says no
   * words are beside it. `s` is trimmed.
   */
  function labels(s) {
    let i = 0;
    const forced = s[0] === '@';
    if (forced) i = 1;
    const first = s.codePointAt(i);
    if (first === undefined || !(is(first, LETTER | DIGIT) && !is(first, LOWER))) return [];
    const found = {};
    const held = {};
    let points = 0;
    let e = i;
    while (e < s.length && points < MAX_NAME_POINTS) {
      const cp = s.codePointAt(e);
      if (!nameChar(cp)) break;
      e += width(cp);
      points += 1;
      if (cp === SPACE) continue;
      ends(s, i, e, found, held);
    }
    const out = [];
    for (const store of [found, held]) for (const form of FORMS) if (store[form]) out.push(store[form]);
    return out;
  }

  /** Whether anything a label ends with stands after `e`: a colon, a period, a bracket, a tab, three spaces, the row's end. */
  function couldEnd(s, e) {
    const r = skipGap(s, e);
    const c = s[r];
    return c === undefined || c === ':' || c === '\uff1a' || c === '(' || c === '[' || c === '^' || s[e] === '.' || s[e] === ','
      || (c === '.' && r > e) || r - e >= 3 || s.slice(e, r).includes('\t');
  }
  /**
   * What a name ending at `e` could be, put in `found` (the first of each form stands) or, for a name
   * that is a title or an initial so far ("MRS.", "J."), in `held` (the last stands, when nothing is found).
   */
  function ends(s, i, e, found, held) {
    if (!couldEnd(s, e)) return;
    const name = s.slice(i, e);
    if (!nameOK(name)) return;
    const key = partName(name);
    const words = wordsOf(key);
    const caps = isCaps(name);
    const titled = !caps && isTitled(name);
    const numeral = isRoman(key);
    const last = words[words.length - 1];
    const maybe = TITLES.has(last) || [...last].length === 1;
    // A direction printed beside the name: "BOB (off)", "ALL, (but one)".
    let d = '', p = e;
    const q = skipGap(s, s[e] === ',' ? e + 1 : e);
    if (opensBracket(s, q)) {
      const end = bracketEnd(s, q);
      if (end > 0) { d = s.slice(q, end); p = end; }
    }
    const put = (store, form, at, rest) => {
      if (store === found && found[form]) return;
      const said = trim(rest);
      store[form] = { form, name, key, label: d ? name : trim(s.slice(0, at)), text: d ? (said ? d + ' ' + said : d) : said, bare: !said };
    };
    const r = skipGap(s, p);

    if (s[r] === ':' || s[r] === '\uff1a') {
      const rest = s.slice(r + 1);
      const ratio = r === e && is(s.codePointAt(e - 1), DIGIT) && is(rest.codePointAt(0), DIGIT);
      if (!rest.startsWith('//') && !ratio) put(found, 'colon', r + 1, rest);
    }
    if (numeral || COMMON.has(key)) return;

    if (caps || (titled && words.length <= 3 && !COMMON_MIXED.has(key))) {
      const form = caps ? 'dot' : 'mixed';
      if (s[p] === '.') {
        // "NAME. words", "NAME.--words", "NAME.[Sullenly.] words"
        const g = skipGap(s, p + 1);
        const t = skipDash(s, g);
        if (t < s.length && (t > p + 1 || opensBracket(s, t))) {
          if (!maybe || d) put(found, form, p + 1, s.slice(t));
          else if (caps || !TITLES.has(last)) put(held, form, p + 1, s.slice(t));
        }
      } else if (d && caps) {
        // "HODSON [hesitant] Is it", "BERTHA (rising)--What"
        const t = skipDash(s, r);
        if (t < s.length && s[t] !== ':' && s[t] !== '\uff1a' && s[t] !== '.') put(found, form, p, s.slice(t));
      }
    }
    if (r > p && r < s.length && s[r] !== ':' && s[r] !== '\uff1a') {
      const gap = s.slice(p, r);
      if ((caps || titled) && gap.includes('\t')) put(found, 'gap', r, s.slice(r));
      else if (caps && gap.length >= 3) put(found, 'gap', r, s.slice(r));
    }
    if (caps) {
      let z = r;
      if (s[z] === '.' || s[z] === ':' || s[z] === '\uff1a' || s[z] === '^') z = skipGap(s, z + 1);
      if (z === s.length) put(found, 'alone', z, '');
    }
  }

  /* ---- Rows ---- */

  const CUE_SOUND = ['SOUND EFFECTS', 'SOUND EFFECT', 'SOUND', 'SFX'];
  const CUE_MUSIC = ['MUSIC', 'THEME', 'ORCHESTRA'];
  const OPENERS = '([*#"“>- \t';
  const skipOpeners = (s) => { let p = 0; while (p < s.length && OPENERS.includes(s[p])) p += 1; return p; };
  /** 'sound', 'music' or null: rule 1. The word then a colon, however it is cased; in capitals, also a period, dash, bracket, or nothing. */
  function cueKind(s) {
    const p = skipOpeners(s);
    const up = asciiUpper(s);
    for (const [kind, words] of [['sound', CUE_SOUND], ['music', CUE_MUSIC]]) {
      for (const w of words) {
        if (!up.startsWith(w, p)) continue;
        const caps = s.startsWith(w, p);
        const r = skipGap(s, p + w.length);
        const c = s[r];
        if (c === ':' || c === '：') return kind;
        if (caps && (c === undefined || c === '.' || c === '(' || c === '[' || c === '-' || c === '—' || c === '–')) return kind;
        if (caps && (c === ')' || c === ']') && p > 0) return kind;
        // "MUSIC UP AND OUT", "SOUND OF A DOOR": three words or more, all in capitals.
        if (caps && r > p + w.length && !s.includes(':') && isCaps(s) && wordsOf(s).length >= 3) return kind;
      }
    }
    return null;
  }

  const HEADS = ['ACT', 'SCENE', 'PROLOGUE', 'EPILOGUE', 'INDUCTION', 'CURTAIN', 'TABLEAU', 'THE END', 'END OF', 'FINIS', 'FADE IN', 'FADE OUT', 'FADE TO', 'CUT TO',
    'INT.', 'EXT.', 'INT/EXT', 'DISSOLVE TO'];
  const HEADS_NUMBERED = ['ACT', 'SCENE', 'ACTUS', 'SCENA', 'SCOENA'];
  const wordEnds = (s, p) => p >= s.length || !(is(s.codePointAt(p), LETTER | MARK | DIGIT) || s[p] === "'" || s[p] === '’');
  /** Rule 2: a heading of the play or its staging. In capitals as printed, or "Act 2" and "Scene I" with their number. */
  function isHeading(s) {
    const p = skipOpeners(s);
    for (const h of HEADS) if (s.startsWith(h, p) && (h.endsWith('.') || wordEnds(s, p + h.length))) return true;
    const up = asciiUpper(s);
    if (up.startsWith('END OF ', p)) for (const w of wordsOf(up)) if (w.startsWith('ACT') || w.startsWith('SCENE') || w.startsWith('PLAY')) return true;
    for (const h of HEADS_NUMBERED) {
      if (!up.startsWith(h, p) || !wordEnds(s, p + h.length)) continue;
      let q = p + h.length;
      if (s[q] === '.') q += 1;
      const a = skipGap(s, q);
      if (a === q) continue;
      let b = a;
      while (b < s.length && is(s.codePointAt(b), LETTER | DIGIT)) b += width(s.codePointAt(b));
      const n = up.slice(a, b);
      if (n && (isRoman(n) || WORD_NUMBERS.has(n) || [...n].every(c => c >= '0' && c <= '9'))) return true;
    }
    return false;
  }

  /** A paragraph that opens with a printed entrance or exit ("Enter two Servants", "Exeunt all but Hamlet."). */
  function isEntrance(s) {
    for (const w of ['Enter', 'Re-enter', 'Reenter']) if (s.startsWith(w + ' ') && is(s.codePointAt(w.length + 1), LETTER)) return true;
    for (const w of ['Exit', 'Exeunt', 'Manet', 'Manent']) if (s.startsWith(w) && (s.length === w.length || s[w.length] === '.' || s[w.length] === ' ')) return true;
    return false;
  }
  /** Whether a row is nothing but an exit, as printed at the end of a speech. */
  const isExit = (s) => s === 'Exit' || s === 'Exit.' || s === 'Exeunt' || s === 'Exeunt.';

  /**
   * The last row (index) of a direction in brackets that opens row `i`'s paragraph, or -1 when the
   * bracket does not close with the paragraph's row (a period may follow it). `closes` is false when
   * the paragraph ends with the bracket still open.
   */
  function bracketRows(rows, i) {
    const open = rows[i].charCodeAt(0);
    const close = open === 40 ? 41 : 93;
    let depth = 0;
    for (let j = i; j < rows.length && rows[j]; j++) {
      const s = rows[j];
      for (let p = 0; p < s.length; p++) {
        const u = s.charCodeAt(p);
        if (u === open) depth += 1;
        else if (u === close) {
          depth -= 1;
          if (depth === 0) {
            const whole = p === s.length - 1 || (p === s.length - 2 && s[p + 1] === '.');
            return { last: whole ? j : -1, closes: true };
          }
        }
      }
    }
    return { last: -1, closes: false };
  }

  /* ---- A Project Gutenberg text's wrapping ---- */

  const WRAP_ENDS = ['*** END OF THE PROJECT GUTENBERG EBOOK', '*** END OF THIS PROJECT GUTENBERG EBOOK', '***END OF THE PROJECT GUTENBERG EBOOK',
    '***END OF THIS PROJECT GUTENBERG EBOOK', 'END OF PROJECT GUTENBERG', 'END OF THE PROJECT GUTENBERG'];
  const WRAP_STARTS = ['*** START OF THE PROJECT GUTENBERG EBOOK', '*** START OF THIS PROJECT GUTENBERG EBOOK', '***START OF THE PROJECT GUTENBERG EBOOK',
    '***START OF THIS PROJECT GUTENBERG EBOOK'];
  /** The older license, before its text or after it; normalizing has taken the `**` between its words. */
  const PRINT_START = '***STARTTHE SMALL PRINT!';
  const PRINT_ENDS = ['*END*THE SMALL PRINT!', '*END THE SMALL PRINT!'];
  const opens = (row, marks) => marks.some(m => row.startsWith(m));
  /**
   * The text between a Project Gutenberg file's own marker rows, and nothing else cut: its header to
   * the START row (and the rows its title runs on to), from the END row on, and the older small print.
   * A text with no marker, or with nothing between them, is as it was.
   */
  function unwrap(text) {
    if (!text.includes('PROJECT GUTENBERG') && !text.includes('Project Gutenberg') && !text.includes('SMALL PRINT!')) return text;
    const rows = text.split('\n');
    const trimmed = rows.map(trim);
    let out = [];
    let kept = [], off = false, started = false, cut = false;
    for (let i = 0; i < rows.length; i++) {
      const t = trimmed[i];
      const m = t[0] === '*' || t[0] === 'E' || t[0] === 'e' ? asciiUpper(t.slice(0, 80)) : '';
      if (opens(m, WRAP_STARTS)) {
        let last = i;
        if (!t.endsWith('***')) for (let j = i + 1; j <= i + 3 && j < rows.length && trimmed[j]; j++) if (trimmed[j].endsWith('***')) { last = j; break; }
        i = last;
        kept = []; off = false; started = true; cut = true;
      } else if (off) continue;
      else if (opens(m, PRINT_ENDS)) { kept = []; started = true; cut = true; } else if (opens(m, WRAP_ENDS) || (started && m.startsWith(PRINT_START))) {
        out = out.concat(kept);
        kept = []; off = true; started = false; cut = true;
      } else kept.push(rows[i]);
    }
    out = out.concat(kept);
    const body = out.join('\n');
    return cut && trim(body) ? body : text;
  }

  /**
   * The ten rules (R4 §2.2). `{ text, lines, parts }`: the normalized text, unwrapped; lines as a doc holds
   * them, `{ kind, role, text, label? }` (kind `open` is No part; `label` is the printed label a
   * speech's text leaves out); and each part's name with its count of lines, in order of appearance.
   */
  function parse(raw) {
    const text = unwrap(normalize(raw));
    const rows = text.split('\n').map(trim);
    const read = new Array(rows.length);
    const seen = new Map(), starting = new Map();
    const printed = { colon: new Map(), dot: new Map(), alone: new Map() };
    const add = (m, k) => m.set(k, (m.get(k) || 0) + 1);
    const opensParagraph = (i) => i === 0 || !rows[i - 1];

    // First the names: a label has to be printed again before it is one.
    for (let i = 0; i < rows.length; i++) {
      const s = rows[i];
      if (!s || cueKind(s) || isHeading(s)) continue;
      read[i] = labels(s);
      const m = read[i][0];
      if (!m) continue;
      if (printed[m.form]) add(printed[m.form], m.key);
      if (m.form === 'mixed') add(starting, m.key);
      else if (m.form !== 'alone' || rows[i + 1] || rows[i + 2]) add(seen, m.key);
    }
    /** Names printed twice and more in a form: two of them, and one printed once in it is a part too. */
    const established = {};
    for (const form of Object.keys(printed)) {
      let names = 0;
      for (const n of printed[form].values()) if (n >= 2) names += 1;
      established[form] = names >= 2;
    }
    const afterLabel = (i) => !!read[i - 1] && read[i - 1].length > 0 && read[i - 1][0].form === 'colon';
    const known = (m, i) => {
      const n = seen.get(m.key) || 0;
      if (m.form === 'mixed') return (n >= 2 && opensParagraph(i)) || (starting.get(m.key) || 0) >= 5;
      if (n >= 2) return true;
      // A part with one line: "OPERATOR: Go ahead.", "FIRST LORD. My liege!", "SOLDIER" over his words.
      if (!established[m.form]) return false;
      if (m.form === 'dot') return opensParagraph(i) && hasLower(m.text);
      if (m.form === 'alone') return opensParagraph(i) && !!rows[i + 1] && hasLower(rows[i + 1]);
      if (isCaps(m.name)) return opensParagraph(i) || afterLabel(i) || !!cueKind(rows[i - 1]);
      return opensParagraph(i) && isTitled(m.name) && wordsOf(m.name).length <= 2;
    };

    const out = [];
    let cur = null;        // the line a row below may go on with
    let blank = true;      // the row above was blank
    let awaiting = false;  // a label with no words yet, over them
    let resume = null;     // the part an exit printed inside a speech interrupted
    const push = (kind, role, t, label) => {
      cur = { kind, role, text: t };
      if (label) cur.label = label;
      out.push(cur);
      awaiting = false;
      resume = null;
    };
    const more = (s) => { cur.text = cur.text ? cur.text + '\n' + s : s; };
    for (let i = 0; i < rows.length; i++) {
      const s = rows[i];
      if (!s) { blank = true; continue; }
      const cue = cueKind(s);
      if (cue) push(cue, null, s);
      else if (isHeading(s)) push('direction', null, s);
      else {
        // Right under a name on its own row stand its words, though they open like a label ("Grace: you wrong me.").
        const m = (read[i] || []).find(x => known(x, i) && !(awaiting && !blank && !isCaps(x.name)));
        if (m) {
          push('speech', m.key, m.text, m.label);
          awaiting = m.bare;
        } else if (awaiting) {
          more(s);
          // A direction over the words, as Fountain prints one: still waiting for them.
          awaiting = opensBracket(s, 0) && bracketEnd(s, 0) === s.length;
        } else if (blank && opensBracket(s, 0)) {
          const b = bracketRows(rows, i);
          if (b.last >= 0) { push('direction', null, rows.slice(i, b.last + 1).join('\n')); i = b.last; }
          else push(s[0] === '[' && !b.closes ? 'direction' : 'open', null, s);
        } else if (blank && isEntrance(s)) push('direction', null, s);
        else if (!blank && cur.kind === 'speech' && isExit(s)) {
          const role = cur.role;
          push('direction', null, s);
          resume = role;
        } else if (!blank && resume) push('speech', resume, s);
        else if (!blank && cur) more(s);
        else push('open', null, s);
      }
      blank = false;
    }
    // A name with nothing under it is not a speech: it goes back as printed, with no part.
    for (const l of out) {
      if (l.kind === 'speech' && !l.text) { l.kind = 'open'; l.role = null; l.text = l.label; delete l.label; }
    }
    return { text, lines: out, parts: partsOf(out) };
  }

  /** Each part's name and its count of lines, in order of first appearance. */
  function partsOf(lines) {
    const m = new Map();
    for (const l of lines) if (l.kind === 'speech') m.set(l.role, (m.get(l.role) || 0) + 1);
    return [...m].map(([name, n]) => ({ name, lines: n }));
  }

  /* ---- A line's printed pieces ---- */

  /** Every bracket's partner in `s`, `( )` and `[ ]` each nested on its own: Map of opening index to the index after the closing one. */
  function matched(s) {
    const out = new Map();
    const round = [], square = [];
    for (let i = 0; i < s.length; i++) {
      const u = s.charCodeAt(i);
      if (u === 40) round.push(i);
      else if (u === 91) square.push(i);
      else if (u === 41 && round.length) out.set(round.pop(), i + 1);
      else if (u === 93 && square.length) out.set(square.pop(), i + 1);
    }
    return out;
  }
  /** The directions inside a speech's text: `[[start, end], ...]`, outermost brackets that hold something and do not join a word ("actor(s)"). */
  function spans(s) {
    const m = matched(s);
    const out = [];
    if (!m.size) return out;
    for (let i = 0; i < s.length; i++) {
      const end = m.get(i);
      if (end === undefined) continue;
      const u = i > 0 ? s.charCodeAt(i - 1) : 0;
      if (asciiWord(u) || u > 0x7f && is(codePointBefore(s, i), LETTER | MARK | DIGIT)) continue;
      if (!trim(s.slice(i + 1, end - 1))) continue;
      out.push([i, end]);
      i = end - 1;
    }
    return out;
  }
  /** A speech's text as the castable shape's parts: `{ say }` and `{ direction }`, each a slice of it. */
  function pieces(text) {
    const out = [];
    let at = 0;
    const say = (t) => { const w = trim(t); if (w) out.push({ say: w }); };
    for (const [a, b] of spans(text)) {
      say(text.slice(at, a));
      out.push({ direction: trim(text.slice(a + 1, b - 1)) });
      at = b;
    }
    say(text.slice(at));
    return out;
  }
  /** Whether every round bracket in `s` has its partner. */
  function evenRound(s) {
    let depth = 0;
    for (let i = 0; i < s.length; i++) {
      const u = s.charCodeAt(i);
      if (u === 40) depth += 1;
      else if (u === 41) { depth -= 1; if (depth < 0) return false; }
    }
    return depth === 0;
  }
  /** The text a speech's parts read from again: directions put back in brackets, round ones unless their words hold half a pair. */
  function textOf(parts) {
    return parts.map(p => {
      if (p.say !== undefined) return p.say;
      const d = p[Object.keys(p)[0]];
      return evenRound(d) ? '(' + d + ')' : '[' + d + ']';
    }).join(' ');
  }

  /* ---- Cutting a line ---- */

  function codePointBefore(s, i) {
    if (i <= 0) return undefined;
    const u = s.charCodeAt(i - 1);
    if (u >= 0xdc00 && u <= 0xdfff && i >= 2) return s.codePointAt(i - 2);
    return u;
  }
  const regional = (cp) => cp >= 0x1f1e6 && cp <= 0x1f1ff;
  /** Whether a cut at `at` would land inside a character a person sees: a surrogate pair, an accent, a joined emoji, a skin tone, a flag. */
  function insideCharacter(s, at) {
    const u = s.charCodeAt(at);
    if (u >= 0xdc00 && u <= 0xdfff) { const b = s.charCodeAt(at - 1); if (b >= 0xd800 && b <= 0xdbff) return true; }
    const cp = s.codePointAt(at);
    if (is(cp, MARK) || cp === 0x200d || (cp >= 0x1f3fb && cp <= 0x1f3ff)) return true;
    const before = codePointBefore(s, at);
    if (before === 0x200d) return true;
    if (regional(cp) && regional(before)) {
      let n = 0;
      for (let i = at; i >= 2 && regional(codePointBefore(s, i)); i -= 2) n += 1;
      return n % 2 === 1;
    }
    return false;
  }
  /** Where a cut asked for at `at` (UTF-16 units into `text`) goes: off a character it would break, out of a direction's brackets (to their start; to their end when they open the line). -1 when one side would have nothing. */
  function cutAt(text, at) {
    if (!Number.isInteger(at) || at <= 0 || at >= text.length) return -1;
    let p = at;
    while (p > 0 && insideCharacter(text, p)) p -= 1;
    for (const [a, b] of spans(text)) if (p > a && p < b) p = trim(text.slice(0, a)) ? a : b;
    return trim(text.slice(0, p)) && trim(text.slice(p)) ? p : -1;
  }

  /* ---- Ids ---- */

  const pad = (n) => String(n).padStart(4, '0');
  /** 1 is a, 26 is z, 27 is aa. */
  function letters(n) {
    let out = '';
    while (n > 0) { const r = (n - 1) % 26; out = String.fromCharCode(97 + r) + out; n = (n - 1 - r) / 26; }
    return out;
  }
  function lettersValue(w) {
    let n = 0;
    for (let i = 0; i < w.length; i++) n = n * 26 + (w.charCodeAt(i) - 96);
    return n;
  }
  /** "L0009" of "L0009a"; "L0000" of nothing above. */
  const baseOf = (id) => (id ? id.slice(0, 5) : 'L0000');

  /* ---- A script being corrected ---- */

  /*
   * A doc is plain data, never changed in place: `apply` returns a new one sharing the lines that
   * did not change. A line:
   *   { k, id, kind, role, text, label?, at?, mark? }
   *   k      its key while it is being edited, never reused
   *   id     null until done(), then given once (R4 §3.1)
   *   kind   'speech' | 'direction' | 'sound' | 'music' | 'open' (No part)
   *   role   a speech's part; null otherwise
   *   label  the printed label its text leaves out
   *   at     [start, end] in milliseconds, a cast transcript's
   *   mark   cast by ear: { role } or { out: true }, that line and those after it (castOf)
   * and the doc: lines, nextKey, letters (base id -> how many given), heard (keys), undo (lines before
   * each op, oldest first). Letters, keys and heard are never taken back, so no id is given twice.
   */

  /** A doc from parse()'s lines, or fromCues()'s. */
  function newDoc(lines) {
    return {
      lines: lines.map((l, i) => ({ k: i + 1, id: null, kind: l.kind, role: l.role || null, text: l.text,
        ...(l.label ? { label: l.label } : {}), ...(l.at ? { at: l.at } : {}) })),
      nextKey: lines.length + 1, letters: {}, heard: [], undo: [],
    };
  }

  const refuse = (doc, refusal) => ({ doc, refusal });
  const accept = (doc, lines, more) => ({ doc: { ...doc, ...(more || {}), lines, undo: [...doc.undo, doc.lines] }, refusal: null });

  /** The id a line put after `above` (a line, or null at the top) takes, and the letters after it: null before done(). */
  function nextID(doc, above, given) {
    if (!given) return { id: null, letters: doc.letters };
    const base = baseOf(above ? above.id : null);
    const n = (doc.letters[base] || 0) + 1;
    return { id: base + letters(n), letters: { ...doc.letters, [base]: n } };
  }

  /** The words of a text, letters and digits only: what tells a changed word from a changed comma. */
  function spoken(text) {
    let out = '', gap = false;
    for (const ch of pieces(text).filter(p => p.say !== undefined).map(p => p.say).join(' ')) {
      const cp = ch.codePointAt(0);
      if (is(cp, LETTER | MARK | DIGIT)) { if (gap && out) out += ' '; gap = false; out += ch; }
      else if (ch !== "'" && ch !== '’') gap = true;
    }
    return out.toLowerCase();
  }
  /** Whether more than punctuation and capitals changed between two versions of a line: its take reads Words changed. */
  const wordsChanged = (before, after) => spoken(before) !== spoken(after);

  /** Lines changed at `i - 1` and before: the line at `i` is marked to keep the cast it had by ear. */
  function holdCast(doc, lines, i) {
    const l = lines[i];
    if (!l || l.kind !== 'open' || l.mark || !doc.heard.length) return lines;
    const who = castOf(doc).get(l.k);
    if (who === null || who === undefined) return lines;
    const out = lines.slice();
    out[i] = { ...l, mark: who === OUT ? { out: true } : { role: who } };
    return out;
  }

  const KINDS = ['direction', 'sound', 'music', 'open'];

  /**
   * One change on the parts page. `env`: `{ takes: [line ids with a take], shared }`. Returns
   * `{ doc, refusal }`; refused, the doc is the one given. Ops (a line is named by its key):
   *   { op: 'assign', line, to: { role } | 'direction' | 'sound' | 'music' | 'open' }
   *   { op: 'split', line, at }        { op: 'join', line }  (to the line above)
   *   { op: 'words', line, text }      { op: 'leaveOut', line }
   *   { op: 'leaveOutAbove', line }    { op: 'leaveOutBelow', line }  (every line there, the line itself kept; one step)
   *   { op: 'add', after: key | 0, kind, role, text }
   *   { op: 'rename', part, to }       (a name already there: the two parts become one)
   *   { op: 'notPart', part }          (a name read by mistake: its words go back, with no part)
   *   { op: 'undo' }
   */
  function apply(doc, op, env = {}) {
    const takes = new Set(env.takes || []);
    const taken = (l) => !!l.id && takes.has(l.id);
    if (env.shared) return refuse(doc, 'shared');
    const lines = doc.lines;
    if (op.op === 'undo') {
      if (!doc.undo.length) return refuse(doc, 'nothing_to_undo');
      return { doc: { ...doc, lines: doc.undo[doc.undo.length - 1], undo: doc.undo.slice(0, -1) }, refusal: null };
    }
    const part = op.op === 'rename' || op.op === 'notPart' ? op.part : null;
    if (part !== null) {
      // While casting by ear a part is its marks, and the lines heard after them (castOf); renaming covers both.
      const marks = (l) => op.op === 'rename' && l.kind === 'open' && !!l.mark && l.mark.role === part;
      const mine = (l) => (l.kind === 'speech' && l.role === part) || marks(l);
      if (!lines.some(mine)) return refuse(doc, 'no_such_part');
      const to = op.op === 'rename' ? partName(normalize(op.to)) : null;
      if (op.op === 'rename') {
        const why = partNameRefusal(to);
        if (why) return refuse(doc, why);
        if (to === part) return { doc, refusal: null };
      }
      const cast = castOf(doc);
      if (lines.some(l => taken(l) && (op.op === 'rename' ? cast.get(l.k) === part : mine(l)))) return refuse(doc, 'part_has_take');
      return accept(doc, lines.map(l => {
        if (!mine(l)) return l;
        if (marks(l)) return { ...l, mark: { role: to } };
        if (op.op === 'rename') return { ...l, role: to };
        const { label, ...rest } = l;
        return { ...rest, kind: 'open', role: null, text: label ? label + ' ' + l.text : l.text };
      }));
    }

    const given = lines.some(l => l.id !== null);
    if (op.op === 'add') {
      const i = op.after === 0 ? 0 : lines.findIndex(l => l.k === op.after) + 1;
      if (op.after !== 0 && i === 0) return refuse(doc, 'no_such_line');
      if (lines.length >= MAX_LINES) return refuse(doc, 'too_many_lines');
      const text = trim(normalize(op.text));
      if (!text) return refuse(doc, 'empty');
      const speech = op.kind === 'speech';
      const role = speech ? partName(normalize(op.role)) : null;
      if (speech) { const why = partNameRefusal(role); if (why) return refuse(doc, why); }
      const n = nextID(doc, i > 0 ? lines[i - 1] : null, given);
      const line = { k: doc.nextKey, id: n.id, kind: speech || KINDS.includes(op.kind) ? op.kind : 'open', role, text };
      return accept(doc, [...lines.slice(0, i), line, ...lines.slice(i)], { nextKey: doc.nextKey + 1, letters: n.letters });
    }

    const i = lines.findIndex(l => l.k === op.line);
    if (i < 0) return refuse(doc, 'no_such_line');
    const l = lines[i];
    const put = (...now) => [...lines.slice(0, i), ...now, ...lines.slice(i + 1)];

    if (op.op === 'words') {
      const text = trim(normalize(op.text));
      if (!text) return refuse(doc, 'empty');
      return text === l.text ? { doc, refusal: null } : accept(doc, put({ ...l, text }));
    }
    if (op.op === 'assign') {
      const role = typeof op.to === 'object' ? partName(normalize(op.to.role)) : null;
      const kind = typeof op.to === 'object' ? 'speech' : op.to;
      if (kind !== 'speech' && !KINDS.includes(kind)) return refuse(doc, 'bad_kind');
      if (kind === 'speech') { const why = partNameRefusal(role); if (why) return refuse(doc, why); }
      if (l.kind === kind && l.role === role) return { doc, refusal: null };
      if (taken(l)) return refuse(doc, 'line_has_take');
      const { mark, ...rest } = l;
      return accept(doc, holdCast(doc, put({ ...rest, kind, role }), i + 1));
    }
    if (op.op === 'leaveOutAbove' || op.op === 'leaveOutBelow') {
      const above = op.op === 'leaveOutAbove';
      const gone = above ? lines.slice(0, i) : lines.slice(i + 1);
      if (!gone.length) return refuse(doc, above ? 'no_line_above' : 'no_line_below');
      if (gone.some(taken)) return refuse(doc, 'lines_have_take');
      return accept(doc, above ? holdCast(doc, lines.slice(i), 0) : lines.slice(0, i + 1));
    }
    if (taken(l)) return refuse(doc, 'line_has_take');
    if (op.op === 'leaveOut') return accept(doc, holdCast(doc, put(), i));
    if (op.op === 'split') {
      const p = cutAt(l.text, op.at);
      if (p < 0) return refuse(doc, 'empty');
      if (lines.length >= MAX_LINES) return refuse(doc, 'too_many_lines');
      const n = nextID(doc, l, given);
      const a = { ...l, text: trim(l.text.slice(0, p)) };
      const { label, mark, ...rest } = l;
      const b = { ...rest, k: doc.nextKey, id: n.id, text: trim(l.text.slice(p)) };
      if (l.at) {
        const t = timeAt(l.at, l.text.length, p);
        a.at = [l.at[0], t];
        b.at = [t, l.at[1]];
      }
      const heard = doc.heard.includes(l.k) ? [...doc.heard, b.k] : doc.heard;
      return accept(doc, put(a, b), { nextKey: doc.nextKey + 1, letters: n.letters, heard });
    }
    if (op.op === 'join') {
      if (i === 0) return refuse(doc, 'no_line_above');
      const above = lines[i - 1];
      if (taken(above)) return refuse(doc, 'line_has_take');
      const verse = above.text.includes('\n') || l.text.includes('\n');
      const one = { ...above, text: above.text + (verse ? '\n' : ' ') + l.text };
      if (above.at && l.at) one.at = [above.at[0], l.at[1]];
      return accept(doc, holdCast(doc, [...lines.slice(0, i - 1), one, ...lines.slice(i + 1)], i));
    }
    return refuse(doc, 'no_such_op');
  }

  /** The line above and the line below's speakers, nearest first, two at most, no name twice: one-tap answers for a line with no part. */
  function nearestParts(lines, i) {
    const out = [];
    for (let d = 1; d < lines.length && out.length < 2; d++) {
      for (const j of [i - d, i + d]) {
        const l = lines[j];
        if (l && l.kind === 'speech' && !out.includes(l.role) && out.length < 2) out.push(l.role);
      }
    }
    return out;
  }

  /**
   * Done: each line gets its id, once, and the steps before it can no longer be taken back. A line
   * with no part becomes a direction, unless `keepOpen` (a transcript still being cast).
   */
  function done(doc, { keepOpen = false } = {}) {
    let lines = doc.lines;
    if (!lines.some(l => l.id !== null)) lines = lines.map((l, i) => ({ ...l, id: 'L' + pad(i + 1) }));
    if (!keepOpen) lines = lines.map(l => (l.kind === 'open' && !l.mark ? { ...l, kind: 'direction' } : l));
    return { ...doc, lines, undo: [] };
  }

  /* ---- The castable shape ---- */

  /** Each part as the catalog counts it: name, lines, said words, in order of appearance. */
  function rolesOf(lines) {
    const m = new Map();
    for (const l of lines) {
      if (l.kind !== 'speech') continue;
      const r = m.get(l.role) || { name: l.role, lines: 0, words: 0 };
      r.lines += 1;
      for (const p of l.parts) if (p.say !== undefined) r.words += wordsOf(p.say).length;
      m.set(l.role, r);
    }
    return [...m.values()];
  }

  /**
   * A done doc as a castable script, its revision still to be sealed: `meta` is `{ id, title }`, and
   * for a cast transcript `{ episode: { id, url } }`. Lines marked by ear are theirs; left-out lines
   * are not in it; a line with no part is a direction.
   */
  function toScript(doc, meta) {
    const lines = settle(doc).lines.map(l => (l.kind === 'speech'
      ? { id: l.id, kind: 'speech', role: l.role, parts: pieces(l.text) }
      : { id: l.id, kind: l.kind === 'open' ? 'direction' : l.kind, source: l.text }));
    return {
      id: meta.id, revision: '', kind: 'own', title: trim(normalize(meta.title)), authors: [],
      source: meta.episode ? { name: 'Automatic transcript', url: meta.episode.url } : { name: 'Added by you', url: '' },
      ...(meta.episode ? { episode: meta.episode.id } : {}),
      rights: { bucket: 'own', evidence: [] },
      roles: rolesOf(lines),
      lines,
    };
  }

  /**
   * A doc over a script as it stands, for Edit a copy (which takes a new script id and keeps the
   * line ids). A script on its own device is corrected from its kept doc, not from this.
   */
  function fromScript(script) {
    const given = {};
    const lines = script.lines.map((l, i) => {
      const base = baseOf(l.id);
      given[base] = Math.max(given[base] || 0, lettersValue(l.id.slice(5)));
      return { k: i + 1, id: l.id, kind: l.kind, role: l.kind === 'speech' ? l.role : null, text: l.kind === 'speech' ? textOf(l.parts) : l.source };
    });
    const lettered = {};
    for (const base of Object.keys(given)) if (given[base]) lettered[base] = given[base];
    return { lines, nextKey: lines.length + 1, letters: lettered, heard: [], undo: [] };
  }
  /** A doc as it is kept: everything but the steps that can be taken back. Plain JSON. */
  const kept = (doc) => ({ ...doc, undo: [] });

  /* ---- The revision ---- */

  const HEX = '0123456789abcdef';
  /** A string as Python's json.dumps(ensure_ascii=False) writes it. */
  function jsonString(s) {
    let out = '"';
    for (let i = 0; i < s.length; i++) {
      const u = s.charCodeAt(i);
      if (u === 34) out += '\\"';
      else if (u === 92) out += '\\\\';
      else if (u === 10) out += '\\n';
      else if (u === 13) out += '\\r';
      else if (u === 9) out += '\\t';
      else if (u === 8) out += '\\b';
      else if (u === 12) out += '\\f';
      else if (u < 32) out += '\\u00' + HEX[u >> 4] + HEX[u & 15];
      else out += s[i];
    }
    return out + '"';
  }
  /** Canonical JSON: keys sorted, no spaces, nothing escaped that need not be (build_castable_scripts.py script_entry). */
  function canonical(v) {
    if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
    if (typeof v === 'string') return jsonString(v);
    if (v && typeof v === 'object') return '{' + Object.keys(v).sort().map(k => jsonString(k) + ':' + canonical(v[k])).join(',') + '}';
    return String(v);
  }
  /** The bytes that are hashed, and sent when a script is shared. */
  const canonicalLines = (lines) => canonical(lines);
  /** The catalog's revision: the first 12 hex digits of the SHA-256 of the canonical lines, UTF-8. */
  async function revisionOf(lines) {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonicalLines(lines)));
    return [...new Uint8Array(digest)].map(b => HEX[b >> 4] + HEX[b & 15]).join('').slice(0, 12);
  }
  const seal = async (script) => ({ ...script, revision: await revisionOf(script.lines) });

  /** null when `script` may be kept and shared, or the first thing wrong with it. */
  function refusalOf(script) {
    if (!script || typeof script.id !== 'string' || !OWN_ID.test(script.id)) return 'bad_id';
    if (typeof script.title !== 'string' || !trim(script.title)) return 'no_title';
    if (script.title.length > MAX_TITLE) return 'title_too_long';
    if (!Array.isArray(script.lines) || !script.lines.length) return 'no_lines';
    if (script.lines.length > MAX_LINES) return 'too_many_lines';
    const seen = new Set();
    for (const l of script.lines) {
      if (!l || typeof l.id !== 'string' || !LINE_ID.test(l.id) || seen.has(l.id)) return 'bad_line_id';
      seen.add(l.id);
      if (l.kind === 'speech') {
        if (typeof l.role !== 'string' || l.role !== partName(l.role) || partNameRefusal(l.role)) return 'bad_part';
        if (!Array.isArray(l.parts) || !l.parts.length) return 'bad_line';
        for (const p of l.parts) {
          const k = p && typeof p === 'object' ? Object.keys(p) : [];
          if (k.length !== 1 || (k[0] !== 'say' && k[0] !== 'direction') || typeof p[k[0]] !== 'string' || !p[k[0]]) return 'bad_line';
        }
      } else if (l.kind === 'direction' || l.kind === 'sound' || l.kind === 'music') {
        if (typeof l.source !== 'string' || !l.source) return 'bad_line';
      } else return 'bad_line';
    }
    if (!script.lines.some(l => l.kind === 'speech')) return 'no_parts';
    if (utf8Length(canonicalLines(script.lines)) > MAX_BYTES) return 'too_long';
    return null;
  }
  /** null, or why Done would refuse parse()'s `lines` whatever the person makes of them: 'too_many_lines', 'too_long'. Asked at Next, so no text is corrected that cannot be kept. */
  function builtRefusal(lines) {
    if (lines.length > MAX_LINES) return 'too_many_lines';
    return utf8Length(canonicalLines(toScript(done(newDoc(lines)), { id: '', title: '' }).lines)) > MAX_BYTES ? 'too_long' : null;
  }
  /** null when a text may be read, or why not: 'empty', 'too_long' ("That file is too long."). Asked before parse(). */
  function textRefusal(raw) {
    const t = String(raw === undefined || raw === null ? '' : raw);
    if (t.length > MAX_BYTES || utf8Length(t) > MAX_BYTES) return 'too_long';
    return trim(normalize(t)) ? null : 'empty';
  }

  /* ---- A transcript, cast by ear ---- */

  /** `start + (end - start) * at / length`, whole milliseconds, rounded down. */
  const timeAt = (span, length, at) => span[0] + Math.floor(((span[1] - span[0]) * at) / length);

  const digitsAt = (s, p, max) => { let n = 0; while (n < max && p + n < s.length && s.charCodeAt(p + n) >= 48 && s.charCodeAt(p + n) <= 57) n += 1; return n; };
  /** "00:01:02.345" or "01:02,345" from `p`: `{ ms, end }`, or null. */
  function clock(s, p) {
    const nums = [];
    let i = p;
    for (;;) {
      const n = digitsAt(s, i, 4);
      if (!n) return null;
      nums.push(Number(s.slice(i, i + n)));
      i += n;
      if (s[i] === ':' && nums.length < 3) { i += 1; continue; }
      break;
    }
    if (nums.length < 2 || (s[i] !== '.' && s[i] !== ',')) return null;
    const f = digitsAt(s, i + 1, 3);
    if (f !== 3) return null;
    const ms = Number(s.slice(i + 1, i + 4));
    const [sec, min, hour] = nums.reverse();
    if (sec > 59 || min > 59) return null;
    return { ms: (((hour || 0) * 60 + min) * 60 + sec) * 1000 + ms, end: i + 4 };
  }
  /** A cue's text: its tags dropped, `&amp;` and its kin read, spaces made one. */
  function cueText(s) {
    let out = '', last = s.lastIndexOf('>');
    for (let i = 0; i < s.length; i++) {
      if (s[i] === '<' && i < last) { i = s.indexOf('>', i); continue; }
      out += s[i];
    }
    // `&amp;` last, so "&amp;lt;" is "&lt;" and not "<".
    for (const [a, b] of [['&lt;', '<'], ['&gt;', '>'], ['&nbsp;', ' '], ['&quot;', '"'], ['&#39;', "'"], ['&amp;', '&']]) out = out.split(a).join(b);
    return wordsOf(out).join(' ');
  }
  /**
   * A transcript's cues, `[{ text, at: [start, end] | null }]`: WebVTT (or SRT) by its times; any other
   * text, one cue a row with no times. Headers, notes, styles and cues with no words or a backward
   * time are left out.
   */
  function parseCues(raw) {
    const rows = normalize(raw).split('\n').map(trim);
    const out = [];
    const timed = rows.some(r => r.includes('-->'));
    if (!timed) {
      for (const r of rows) { const t = cueText(r); if (t && r !== 'WEBVTT') out.push({ text: t, at: null }); }
      return out;
    }
    for (let i = 0; i < rows.length; i++) {
      const arrow = rows[i].indexOf('-->');
      if (arrow < 0) continue;
      const a = clock(rows[i], 0);
      const b = clock(rows[i], skipGap(rows[i], arrow + 3));
      let j = i + 1;
      const said = [];
      while (j < rows.length && rows[j] && !rows[j].includes('-->')) { said.push(rows[j]); j += 1; }
      const t = cueText(said.join(' '));
      if (a && b && b.ms >= a.ms && t) out.push({ text: t, at: [a.ms, b.ms] });
      i = j - 1;
    }
    return out;
  }

  /** Never cut after these and a period (R4 §2.4). */
  const ABBREVIATIONS = set('Mr Mrs Ms Dr St Col Capt Lt Gen Sgt Prof Rev');
  const closesQuote = (c) => c === '"' || c === "'" || c === '”' || c === '’';
  const opensQuote = (c) => c === '"' || c === "'" || c === '“' || c === '‘';
  /** Where a cue's text is cut into lines: the index after each sentence's end, when a space and a capital follow. */
  function sentenceCuts(t) {
    const out = [];
    for (let i = 0; i < t.length; i++) {
      const c = t[i];
      if (c !== '.' && c !== '?' && c !== '!') continue;
      let j = i + 1;
      while (j < t.length && closesQuote(t[j])) j += 1;
      if (t[j] !== ' ') continue;
      let n = j + 1;
      if (opensQuote(t[n])) n += 1;
      if (!is(t.codePointAt(n), UPPER)) continue;
      if (c === '.') {
        let w = i;
        while (w > 0 && asciiWord(t.charCodeAt(w - 1))) w -= 1;
        const before = w > 0 ? codePointBefore(t, w) : undefined;
        if (ABBREVIATIONS.has(t.slice(w, i)) && !is(before, LETTER | MARK)) continue;
      }
      out.push(j);
    }
    return out;
  }
  /** Cues as lines to cast, each a sentence of one cue with its share of the cue's time by UTF-16 units: a doc whose every line has no part. */
  function fromCues(cues) {
    const lines = [];
    for (const cue of cues) {
      let from = 0;
      const n = cue.text.length;
      for (const cut of [...sentenceCuts(cue.text), n]) {
        const text = trim(cue.text.slice(from, cut));
        const at = cue.at ? [timeAt(cue.at, n, from), timeAt(cue.at, n, cut === n ? n : cut + 1)] : null;
        if (text) lines.push({ kind: 'open', role: null, text, ...(at ? { at } : {}) });
        from = cut + 1;
      }
    }
    return newDoc(lines);
  }

  /** The line being said at `ms` (its key), or the last one begun; 0 before the first. */
  function lineAt(doc, ms) {
    let k = 0;
    for (const l of doc.lines) { if (!l.at) continue; if (l.at[0] > ms) break; k = l.k; }
    return k;
  }

  /**
   * Who each line is cast to, by key: a name, `OUT`, or null. A mark is that line's and every line
   * after it that was heard in a row, until the next mark (R4 §2.4 rule 3). A line given a part on
   * the parts page keeps it and carries to nothing.
   */
  const OUT = Symbol.for('own-core.out');
  function castOf(doc) {
    const heard = new Set(doc.heard);
    const out = new Map();
    let carry = null;
    for (const l of doc.lines) {
      if (l.kind !== 'open') { out.set(l.k, l.kind === 'speech' ? l.role : null); carry = null; continue; }
      if (l.mark) carry = l.mark.out ? OUT : l.mark.role;
      else if (!heard.has(l.k)) carry = null;
      out.set(l.k, carry);
    }
    return out;
  }

  /** The audio reached line `k`, coming from line `from` (0 after a seek): it and those between are heard. Never undone. */
  function hear(doc, k, from = 0) {
    const b = doc.lines.findIndex(l => l.k === k);
    if (b < 0) return doc;
    const a0 = from ? doc.lines.findIndex(l => l.k === from) : -1;
    const a = a0 >= 0 && a0 <= b ? a0 : b;
    const heard = new Set(doc.heard);
    const before = heard.size;
    for (let i = a; i <= b; i++) heard.add(doc.lines[i].k);
    return heard.size === before ? doc : { ...doc, heard: [...heard] };
  }

  /** A tap on a part (or Leave out) while line `k` is lit: `who` is `{ role }` or `{ out: true }`. `{ doc, refusal }`, undone by apply's undo. */
  function tap(doc, k, who, env = {}) {
    if (env.shared) return refuse(doc, 'shared');
    const i = doc.lines.findIndex(l => l.k === k);
    if (i < 0) return refuse(doc, 'no_such_line');
    let mark = { out: true };
    if (!who.out) {
      const role = partName(normalize(who.role));
      const why = partNameRefusal(role);
      if (why) return refuse(doc, why);
      mark = { role };
    }
    const lines = doc.lines.slice();
    lines[i] = { ...lines[i], kind: 'open', role: null, mark };
    return marked(doc, lines, env, [k]);
  }
  /** Leaves out one line and no other: the next keeps the cast it had. */
  function leaveOutHeard(doc, k, env = {}) {
    if (env.shared) return refuse(doc, 'shared');
    const i = doc.lines.findIndex(l => l.k === k);
    if (i < 0) return refuse(doc, 'no_such_line');
    const lines = doc.lines.slice();
    lines[i] = { ...lines[i], kind: 'open', role: null, mark: { out: true } };
    return marked(doc, holdCast(doc, lines, i + 1), env, [k]);
  }
  function marked(doc, lines, env, heardNow) {
    const heard = [...new Set([...doc.heard, ...heardNow])];
    const next = accept(doc, lines, { heard });
    const takes = new Set(env.takes || []);
    if (takes.size) {
      const was = castOf(doc), now = castOf(next.doc);
      if (doc.lines.some(l => l.id && takes.has(l.id) && was.get(l.k) !== now.get(l.k))) return refuse(doc, 'line_has_take');
    }
    return next;
  }

  /** "37 of 149 lines cast": lines given to a part or left out, of all of them. */
  function castCount(doc) {
    const cast = castOf(doc);
    let n = 0;
    for (const l of doc.lines) if (l.kind !== 'open' || cast.get(l.k) !== null) n += 1;
    return { cast: n, lines: doc.lines.length };
  }

  /** The marks made into the lines' own parts, left-out lines gone: what the parts page corrects and toScript keeps. */
  function settle(doc) {
    const cast = castOf(doc);
    const lines = [];
    for (const l of doc.lines) {
      if (l.kind !== 'open') { lines.push(l); continue; }
      const who = cast.get(l.k);
      if (who === OUT) continue;
      const { mark, ...rest } = l;
      lines.push(who === null ? rest : { ...rest, kind: 'speech', role: who });
    }
    return { ...doc, lines };
  }

  return {
    MAX_BYTES, MAX_LINES, MAX_PART_NAME, MAX_TITLE, OWN_ID, LINE_ID, OUT,
    normalize, trim, wordsOf, utf8Length, partName, partNameRefusal, textRefusal,
    labels, cueKind, isHeading, isEntrance, unwrap, parse, partsOf,
    pieces, textOf, cutAt, newDoc, apply, nearestParts, done, wordsChanged,
    toScript, fromScript, kept, rolesOf, canonicalLines, revisionOf, seal, refusalOf, builtRefusal,
    parseCues, sentenceCuts, fromCues, lineAt, castOf, hear, tap, leaveOutHeard, castCount, settle,
  };
})();
