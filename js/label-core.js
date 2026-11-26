/**
 * The label (Decision 081, WEB-DESIGN §6.4r, R3a §3.4): the drawn art of anything without a picture,
 * as a pure spec with no DOM, so js/label.test.js runs this file as shipped and js/label.js draws what
 * it decides. Every mark is a fact the item's published fields hold; nothing is hashed or random, and
 * an undated show draws no arc. The geometry is design-tokens.json `art.label` (the block below is
 * written by tools/design_tokens.mjs); the golden cases every stack runs are
 * catalog/tests/golden/label_spec.json.
 *
 * labelSpec(item, size): `size` is the window's side in CSS points (it picks the tier); `item` is one of
 *   { kind: 'series',  name, genre, first, last, network, tickYear? }
 *   { kind: 'episode', name (the show's), genre, first, last, network, date, num }
 *   { kind: 'station', name?, genre, tickYear }
 *   { kind: 'drama',   name, parts: [{ lines, hue }] (largest first), finished ('YYYY-MM[-DD]') }
 *   { kind: 'person',  name, genre?, first?, last? (credit years, drawn at L only) }
 *   { kind: 'play',    voices, opening? (true when the caller sets the opening's speeches as text), cast ([lines], largest first) }
 *   { kind: 'play',    name, author?, hue?, era?, life? ({born, died}), cast } (the play's page label, B31 2.1)
 * Angles are degrees, 0 at three o'clock, counterclockwise positive (the dial runs clockwise, so an
 * arc's `from` is larger than its `to`). Colors are token references (board.mystery, brand.text).
 */
const LabelCore = (() => {
  'use strict';

  /* BEGIN design-tokens:label. Generated from design-tokens.json by tools/design_tokens.mjs. Do not edit by hand. */
  const T = {
    "viewBox": 100,
    "tiers": {
      "M": 96,
      "L": 320
    },
    "dial": {
      "from": 1930,
      "to": 1962,
      "startDeg": 210,
      "sweepDeg": 240,
      "ticks": [
        1930,
        1940,
        1950,
        1960
      ]
    },
    "disc": {
      "r": 47,
      "opacity": 0.1
    },
    "grooves": {
      "from": 21,
      "to": {
        "M": 39.5,
        "L": 34
      },
      "step": {
        "M": 3.1,
        "L": 1.6
      },
      "width": 0.35,
      "opacity": 0.32
    },
    "ticks": {
      "r0": 40,
      "r1": 42.5,
      "width": 0.9,
      "opacity": 0.75
    },
    "arc": {
      "r": {
        "S": 43.5,
        "M": 44.75,
        "L": 44.75
      },
      "width": {
        "S": 7,
        "M": 4,
        "L": 3.5
      }
    },
    "evening": {
      "r0": {
        "S": 35,
        "M": 35,
        "L": 40
      },
      "r1": 47,
      "width": {
        "S": 3.2,
        "M": 1.8,
        "L": 1.4
      }
    },
    "label": {
      "r": {
        "S": 27,
        "M": 21,
        "L": 19
      },
      "fitW": 0.76,
      "fitH": 0.6,
      "small": 0.34,
      "lead": 0.55
    },
    "rim": {
      "r": 36.5,
      "size": 3.4,
      "tracking": 0.14,
      "opacity": 0.85,
      "maxSweepDeg": 150
    },
    "parts": {
      "r": {
        "S": 43.5,
        "M": 44.75,
        "L": 44.75
      },
      "width": {
        "S": 6,
        "M": 4,
        "L": 3.5
      },
      "backing": 1.4,
      "gapDeg": 4,
      "startDeg": 90
    },
    "person": {
      "ring": {
        "r": 40,
        "width": {
          "S": 2.6,
          "M": 1.6,
          "L": 1.2
        },
        "opacity": 0.55
      },
      "fitR": 25,
      "arc": {
        "r": 45,
        "width": 3
      }
    },
    "play": {
      "bands": [
        2,
        4,
        8
      ],
      "rule": {
        "x0": 8,
        "y": 93,
        "len": 9,
        "gap": 3,
        "width": 2.2,
        "opacity": 0.55,
        "foot": 86
      },
      "cast": {
        "x": 12,
        "w": 76,
        "h": 7,
        "hFirst": 11,
        "gap": 6,
        "max": 7,
        "minW": 10,
        "more": {
          "size": 10,
          "x": 92,
          "y": 94
        }
      },
      "board": "drama",
      "page": {
        "x0": 9,
        "span": 82,
        "mono": {
          "x": 8.4,
          "cap": {
            "S": 40,
            "M": 34,
            "L": 30
          },
          "y": {
            "S": 47,
            "M": 46,
            "L": 50
          }
        },
        "cols": {
          "max": {
            "S": 6,
            "M": 10,
            "L": 12
          },
          "gap": {
            "S": 3,
            "M": 2.2,
            "L": 1.6
          },
          "base": {
            "S": 88,
            "M": 82,
            "L": 82
          },
          "h": {
            "S": 32,
            "M": 26,
            "L": 26
          },
          "maxW": {
            "S": 16,
            "M": 13,
            "L": 13
          },
          "min": 0.08,
          "restOpacity": 0.42
        },
        "ruler": {
          "y": 92,
          "h": {
            "M": 3,
            "L": 2.2
          },
          "tick": 1.6,
          "width": 0.6,
          "opacity": 0.38,
          "inset": 0.8
        },
        "rim": {
          "x": 9,
          "y": 15,
          "size": 3.6,
          "tracking": 0.14,
          "opacity": 0.85
        },
        "eras": [
          "Antiquity",
          "Medieval",
          "1500s",
          "1600s",
          "1700s",
          "1800s",
          "1900-1930"
        ]
      }
    },
    "colors": {
      "groundNone": "brand.surfaceAlt",
      "onNone": "brand.text",
      "partNone": "brand.textMuted",
      "partsBacking": "brand.background",
      "playGround": "print.ground",
      "playInk": "brand.text"
    },
    "glyphs": {
      "tracking": 0.02,
      "display": {
        "1": 0.27,
        "cap": 0.8,
        "default": 0.5,
        "M": 0.76,
        "W": 0.78,
        "I": 0.27,
        ".": 0.25,
        "’": 0.25,
        " ": 0.22,
        "·": 0.2
      },
      "body": {
        "1": 0.43,
        "cap": 0.73,
        "default": 0.73,
        "M": 0.92,
        "W": 0.97,
        "G": 0.76,
        "H": 0.77,
        "N": 0.79,
        "O": 0.77,
        "Q": 0.78,
        "I": 0.31,
        "J": 0.41,
        ".": 0.27,
        "’": 0.27,
        " ": 0.23,
        "·": 0.26
      }
    }
  };
  const GENRES = ["drama","mystery","scifi","western","comedy","news","documentary","serial"];
  /* END design-tokens:label */

  const r2 = (v) => Math.round(v * 100) / 100 + 0;
  const tierOf = (size) => (size >= T.tiers.L ? 'L' : size >= T.tiers.M ? 'M' : 'S');
  const at = (v, tier) => (v !== null && typeof v === 'object' ? v[tier] : v);
  const yearOf = (d) => (d !== null && d !== undefined && /^\d{4}/.test(String(d)) ? +String(d).slice(0, 4) : null);
  const known = (g) => GENRES.includes(g);
  const groundOf = (g) => (known(g) ? `board.${g}` : T.colors.groundNone);
  const onOf = (g) => (known(g) ? `onBoard.${g}` : T.colors.onNone);
  const mono = (name) => (typeof API !== 'undefined' && API.monogram ? API.monogram(name) : '');

  /* ---- The dial: a year is one slot of sweepDeg / (to - from + 1) degrees, clockwise from startDeg ---- */
  const SLOT = T.dial.sweepDeg / (T.dial.to - T.dial.from + 1);
  const yearDeg = (y) => T.dial.startDeg - (y - T.dial.from) * SLOT;
  const clampYear = (y) => Math.min(T.dial.to, Math.max(T.dial.from, y));
  const offDial = (y) => y < T.dial.from || y > T.dial.to;

  /** The run arc from the first year's slot to the end of the last's; a year off the dial is held at its end with a butt cap. */
  function runArc(first, last, r, width) {
    const a = yearOf(first);
    if (a === null) return null;
    let b = yearOf(last);
    if (b === null || b < a) b = a;
    return { r, width, from: r2(yearDeg(clampYear(a))), to: r2(yearDeg(clampYear(b) + 1)),
             capFrom: offDial(a) ? 'butt' : 'round', capTo: offDial(b) ? 'butt' : 'round' };
  }

  /* ---- Text: a line's width from the glyph table, so every stack fits the same size ---- */
  const em = (s, face) => [...s].reduce((w, ch) => w + (T.glyphs[face][ch] ?? T.glyphs[face].default) + T.glyphs.tracking, 0);
  const fit = (s, face, maxW, maxCap) => Math.min(maxCap / T.glyphs[face].cap, maxW / Math.max(em(s, face), 0.01));

  /** One line or two (a small body-face line over a big display line), centered on (50, 50) inside a box. */
  function centered(lines, boxW, boxH, fill) {
    const ls = lines.filter((l) => l && l.s);
    if (!ls.length) return [];
    if (ls.length === 1) {
      const { s, face } = ls[0];
      const size = fit(s, face, boxW, boxH);
      return [{ s, face, size: r2(size), x: 50, y: r2(50 + (size * T.glyphs[face].cap) / 2), anchor: 'middle', fill }];
    }
    const [sm, bg] = ls;
    const sSize = Math.min(boxH * T.label.small, boxW / Math.max(em(sm.s, sm.face), 0.01));
    const hs = sSize * T.glyphs[sm.face].cap, gap = hs * T.label.lead;
    const bSize = fit(bg.s, bg.face, boxW, boxH - hs - gap);
    const hb = bSize * T.glyphs[bg.face].cap;
    const top = 50 - (hs + gap + hb) / 2;
    return [{ s: sm.s, face: sm.face, size: r2(sSize), x: 50, y: r2(top + hs), anchor: 'middle', fill },
            { s: bg.s, face: bg.face, size: r2(bSize), x: 50, y: r2(top + hs + gap + hb), anchor: 'middle', fill }];
  }

  const MON = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  /** An episode's label lines: the date block's own text (DEC ’42 / 22; ’42 / DEC; 1942; No. / 7), one line at S. */
  function episodeLines(date, num, tier) {
    const m = /^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?/.exec(date || '');
    const y = m ? m[1] : null, mo = m && m[2] ? +m[2] : 0, day = m && m[3] ? +m[3] : 0;
    const yy = y ? `’${y.slice(2)}` : '';
    const hasNum = num !== null && num !== undefined && String(num) !== '';
    if (y && tier === 'S') return [{ s: yy, face: 'display' }];
    if (y && mo >= 1 && mo <= 12 && day) return [{ s: `${MON[mo - 1]} ${yy}`, face: 'body' }, { s: String(day), face: 'display' }];
    if (y && mo >= 1 && mo <= 12) return [{ s: yy, face: 'body' }, { s: MON[mo - 1], face: 'display' }];
    if (y) return [{ s: y, face: 'display' }];
    if (hasNum && tier === 'S') return [{ s: `No.${num}`, face: 'display' }];
    if (hasNum) return [{ s: 'No.', face: 'body' }, { s: String(num), face: 'display' }];
    return null;
  }

  /** The rim's words at L, in capitals on the top of the disc, sized down to fit its sweep. */
  function rimOf(text) {
    if (!text) return null;
    const maxLen = (Math.PI * T.rim.r * T.rim.maxSweepDeg) / 180;
    const perEm = em(text, 'body') + text.length * T.rim.tracking;
    return { text, r: T.rim.r, size: r2(Math.min(T.rim.size, maxLen / perEm)), tracking: T.rim.tracking, opacity: T.rim.opacity, centerDeg: 90 };
  }
  const decadeOf = (first) => { const y = yearOf(first); return y === null ? null : `${Math.floor(y / 10) * 10}s`; };

  function grooves(tier) {
    if (tier === 'S') return null;
    const to = at(T.grooves.to, tier), step = at(T.grooves.step, tier), radii = [];
    for (let i = 0; T.grooves.from + i * step <= to + 1e-9; i++) radii.push(r2(T.grooves.from + i * step));
    return { radii, width: T.grooves.width, opacity: T.grooves.opacity };
  }

  function disc(it, tier, kind) {
    const g = known(it.genre) ? it.genre : kind === 'drama' ? 'drama' : '';
    const labelR = at(T.label.r, tier);
    const spec = { kind, shape: 'square', tier, viewBox: T.viewBox, ground: groundOf(g), on: onOf(g),
                   disc: { r: T.disc.r, opacity: T.disc.opacity }, grooves: grooves(tier), ticks: null, arc: null,
                   evening: null, parts: null, ring: null, label: { r: labelR }, text: [], rim: null, rules: null, cast: null };
    const dialed = kind !== 'drama';
    if (dialed && tier !== 'S') {
      spec.ticks = { r0: T.ticks.r0, r1: T.ticks.r1, width: T.ticks.width, opacity: T.ticks.opacity,
                     deg: T.dial.ticks.map((y) => r2(yearDeg(y))) };
    }
    if (kind === 'series' || kind === 'episode') spec.arc = runArc(it.first, it.last, at(T.arc.r, tier), at(T.arc.width, tier));
    const ty = yearOf(it.tickYear);
    if (dialed && ty !== null) {
      spec.evening = { deg: r2(yearDeg(clampYear(ty)) - SLOT / 2), r0: at(T.evening.r0, tier), r1: T.evening.r1, width: at(T.evening.width, tier) };
    }
    if (kind === 'drama') {
      const ps = (it.parts || []).filter((p) => p && p.lines > 0);
      const total = ps.reduce((a, p) => a + p.lines, 0);
      if (ps.length) {
        const w = at(T.parts.width, tier), gap = ps.length > 1 ? T.parts.gapDeg : 0;
        let a = T.parts.startDeg;
        spec.parts = { r: at(T.parts.r, tier), width: w, backing: { color: T.colors.partsBacking, width: r2(w + T.parts.backing) },
                       segments: ps.map((p) => {
                         const d = (p.lines / total) * 360;
                         const seg = { from: r2(a), to: r2(a - Math.max(d - gap, d / 2)), color: known(p.hue) ? `genre.${p.hue}` : T.colors.partNone };
                         a -= d;
                         return seg;
                       }) };
      }
    }
    const box = 2 * labelR;
    let lines = kind === 'episode' ? episodeLines(it.date, it.num, tier) : null;
    if (!lines) lines = kind === 'station' && !it.name ? [] : [{ s: mono(it.name), face: 'display' }];
    spec.text = centered(lines, box * T.label.fitW, box * T.label.fitH, 'ground');
    if (tier === 'L') {
      if (kind === 'drama') {
        const m = /^(\d{4})-(\d{2})/.exec(it.finished || '');
        spec.rim = rimOf(m && +m[2] >= 1 && +m[2] <= 12 ? `RECORDED · ${MON[+m[2] - 1]} ${m[1]}` : null);
      } else if (kind !== 'station') {
        spec.rim = rimOf([it.network ? String(it.network).toUpperCase() : null, decadeOf(it.first)].filter(Boolean).join(' · '));
      }
    }
    return spec;
  }

  function person(it, tier) {
    const g = known(it.genre) ? it.genre : '';
    const box = 2 * T.person.fitR;
    return { kind: 'person', shape: 'circle', tier, viewBox: T.viewBox, ground: groundOf(g), on: onOf(g),
             disc: null, grooves: null, ticks: null,
             arc: tier === 'L' ? runArc(it.first, it.last, T.person.arc.r, T.person.arc.width) : null,
             evening: null, parts: null,
             ring: { r: T.person.ring.r, width: at(T.person.ring.width, tier), opacity: T.person.ring.opacity },
             label: null, text: centered([{ s: mono(it.name), face: 'display' }], box * T.label.fitW, box * T.label.fitH, 'on'),
             rim: null, rules: null, cast: null };
  }

  /** A stage play was never broadcast, so it is not a disc. With its opening at hand (`opening`: the caller
      sets the speeches as text on the print ground) it adds its voice band as 1 to 4 rules at the page's
      foot; without, it draws its cast on the drama board, a bar per speaking part, largest first. */
  function play(it, tier) {
    const base = { kind: 'play', shape: 'square', tier, viewBox: T.viewBox, disc: null, grooves: null, ticks: null, arc: null,
                   evening: null, parts: null, ring: null, label: null, text: [], rim: null, rules: null, cast: null };
    if (it.opening) {
      const v = Number(it.voices) || 0;
      const [b1, b2, b3] = T.play.bands;
      const count = v <= 0 ? 0 : v <= b1 ? 1 : v <= b2 ? 2 : v <= b3 ? 3 : 4;
      const R = T.play.rule;
      return { ...base, ground: T.colors.playGround, on: T.colors.playInk,
               rules: count ? { count, x0: R.x0, y: R.y, len: R.len, gap: R.gap, width: R.width, opacity: R.opacity, foot: R.foot } : null };
    }
    const C = T.play.cast, g = T.play.board;
    const all = (it.cast || []).map(Number).filter((n) => n > 0);
    const shown = all.slice(0, C.max), most = shown[0] || 1;
    const total = shown.length ? C.hFirst + (shown.length - 1) * (C.h + C.gap) : 0;
    let y = 50 - total / 2;
    const more = all.length - shown.length;
    const share = (n) => Math.max(C.minW, Math.round((100 * n) / most)) / 100;
    // "+N" stands at the last bar's end. Every bar is drawn to the same shorter scale when that one would reach it.
    const room = more > 0 ? C.more.x - C.more.size * em(`+${more}`, 'body') - C.gap - C.x : C.w;
    const w = shown.length ? Math.min(C.w, Math.max(0, room) / share(shown[shown.length - 1])) : C.w;
    const bars = shown.map((n, i) => {
      const h = i ? C.h : C.hFirst;
      const bar = { x: C.x, y: r2(y), w: r2(w * share(n)), h };
      y += h + C.gap;
      return bar;
    });
    return { ...base, ground: groundOf(g), on: onOf(g), cast: bars.length ? { bars } : null,
             text: more > 0 ? [{ s: `+${more}`, face: 'body', size: C.more.size, x: C.more.x, y: C.more.y, anchor: 'end', fill: 'on' }] : [] };
  }

  /** The surname the page's top line names: the display name's last word, a parenthesis and a Jr. or III dropped. */
  function surnameOf(author) {
    const words = String(author || '').replace(/\([^)]*\)/g, ' ').split(/[\s,]+/).filter(Boolean);
    while (words.length > 1 && /^(jr|sr|ii|iii|iv)\.?$/i.test(words[words.length - 1])) words.pop();
    return words.length ? words[words.length - 1].toUpperCase() : '';
  }
  /** Life years as the record has them: 1856-1950, 496-407 BCE (both before the era), 30 BCE-17 (across it). */
  function lifeOf(life) {
    if (!life || typeof life !== 'object') return '';
    const b = Number.isFinite(life.born) ? life.born : null, d = Number.isFinite(life.died) ? life.died : null;
    if (b === null || d === null) return '';
    if (b < 0 && d < 0) return `${-b}-${-d} BCE`;
    if (b < 0) return `${-b} BCE-${d}`;
    return `${b}-${d}`;
  }

  /** The play's label (B31 2.1, WEB-DESIGN 6.4r): a printed page, not a disc. The board is the form's (`hue`, the
      catalog's) or the neutral one; the monogram from the left in the top half; a column per speaking part,
      largest first, its height its lines over the largest part's; the era ruler at the foot (M, L); at L the
      line "SURNAME · LIFE YEARS". The top right corner stays clear for Read. */
  function playPage(it, tier) {
    const P = T.play.page, g = known(it.hue) ? it.hue : '';
    const spec = { kind: 'play', shape: 'square', tier, viewBox: T.viewBox, ground: groundOf(g), on: onOf(g),
                   disc: null, grooves: null, ticks: null, arc: null, evening: null, parts: null, ring: null, label: null,
                   text: [], rim: null, rules: null, cast: null, cols: null, ruler: null };
    const m = mono(it.name);
    if (m) {
      const size = Math.min(at(P.mono.cap, tier) / T.glyphs.display.cap, P.span / Math.max(em(m, 'display'), 0.01));
      spec.text.push({ s: m, face: 'display', size: r2(size), x: P.mono.x, y: at(P.mono.y, tier), anchor: 'start', fill: 'on' });
    }
    if (tier !== 'S') {
      const cell = P.span / P.eras.length;
      spec.ruler = { y: P.ruler.y, x0: P.x0, span: P.span, cell: r2(cell), lit: P.eras.indexOf(it.era), h: at(P.ruler.h, tier),
                     tick: P.ruler.tick, width: P.ruler.width, opacity: P.ruler.opacity, inset: P.ruler.inset };
    }
    const cast = (it.cast || []).map(Number).filter((n) => n > 0);
    if (cast.length) {
      const C = P.cols, max = at(C.max, tier), gap = at(C.gap, tier), base = at(C.base, tier), H = at(C.h, tier);
      const more = cast.length > max;
      const shown = more ? cast.slice(0, max - 1) : cast;
      const n = shown.length + (more ? 1 : 0);
      const w = Math.min(at(C.maxW, tier), (P.span - gap * (n - 1)) / n);
      const col = (v, i, rest) => { const h = Math.max(C.min, v / cast[0]) * H;
        return { x: r2(P.x0 + i * (w + gap)), y: r2(base - h), w: r2(w), h: r2(h), rest }; };
      const bars = shown.map((v, i) => col(v, i, false));
      if (more) bars.push(col(cast[max - 1], shown.length, true));
      spec.cols = { restOpacity: C.restOpacity, bars };
    }
    if (tier === 'L') {
      const line = [surnameOf(it.author), lifeOf(it.life)].filter(Boolean).join(' · ');
      const fitted = r2(Math.min(P.rim.size, P.span / Math.max(em(line, 'body') + [...line].length * P.rim.tracking, 0.01)));
      if (line) spec.text.unshift({ s: line, face: 'body', size: fitted, x: P.rim.x, y: P.rim.y, anchor: 'start', fill: 'on',
                                    tracking: P.rim.tracking, opacity: P.rim.opacity });
    }
    return spec;
  }

  function labelSpec(item, size) {
    const it = item || {};
    const tier = tierOf(Number(size) || 0);
    const kind = ['series', 'episode', 'station', 'drama', 'person', 'play'].includes(it.kind) ? it.kind : 'series';
    if (kind === 'person') return person(it, tier);
    // A play row's label carries its name (B31); the nameless form is the R4-2c bars the shared golden `cases`
    // still hold until Swift and Kotlin take the page (A1, D1).
    if (kind === 'play') return !it.opening && it.name !== undefined ? playPage(it, tier) : play(it, tier);
    return disc(it, tier, kind);
  }

  return { labelSpec, tierOf, yearDeg, surnameOf, lifeOf, SLOT, T, GENRES };
})();
