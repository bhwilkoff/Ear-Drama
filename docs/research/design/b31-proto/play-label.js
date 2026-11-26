/* B31 prototype: the play's label (not product code). A pure spec from the library row's own facts, then an SVG.
 *
 *   playLabelSpec({title, form, hue, era, cast, surname, years}, sizePx) -> spec
 *   playLabelSVG(spec, theme) -> '<svg>...'
 *
 * The object is the printed page, not the disc: a stage play was never broadcast (Decision 081), and the disc is
 * what it becomes when someone records it, when the cast strip rolls into the ear drama's rim of part hues.
 * Marks, all facts: board = form where the record names one (subject heading or the book's own title), else the
 * neutral board; era ruler = seven fixed buckets, the playwright's active years lit (none when undated); monogram =
 * API.monogram (the name is never drawn twice, WEB-DESIGN 6.4b); cast strip = one segment per speaking part, largest
 * first, width by share of the lines, up to 7 (4 at S) and the rest as one dimmer segment. At L a rim-like line:
 * SURNAME · LIFE YEARS (the record's own, never a derived decade). Tiers as the shows': S under 96 px, M from 96, L from 320.
 */
(function (g) {
  const BOARD = {
    drama: ['#86426F', '#5F2A4D'], mystery: ['#375C9B', '#223F6F'], scifi: ['#006A79', '#004854'],
    western: ['#8B492A', '#623018'], comedy: ['#795700', '#543B00'], news: ['#615D53', '#424038'],
    documentary: ['#296E38', '#154C22'], serial: ['#684D92', '#473368'],
  };
  const ON = ['#FFFFFF', '#F2F2F4'];
  const NONE = { ground: ['#E8E8EB', '#232327'], on: ['#131316', '#F2F2F4'] };   // brand.surfaceAlt, brand.text
  const ERAS = ['Antiquity', 'Medieval', '1500s', '1600s', '1700s', '1800s', '1900-1930'];
  const STOP = new Set(['the', 'a', 'an', 'of', 'and', 'in', 'on', 'to', 'for', 'el', 'la', 'le', 'de', 'der', 'die']);
  const W = { M: 0.76, W: 0.78, J: 0.45, I: 0.27, 1: 0.27 };

  function monogram(name) {
    const words = String(name || '').split(/[\s\-–/]+/).map((w) => w.replace(/^[^\p{L}\p{N}]+/u, '')).filter(Boolean);
    const m = words.filter((w) => /^\p{L}/u.test(w) && !STOP.has(w.toLowerCase())).slice(0, 2).map((w) => w[0].toUpperCase()).join('');
    return m || ((String(name || '').match(/[\p{L}\p{N}]/u) || [''])[0].toUpperCase());
  }
  const emOf = (s) => [...s].reduce((a, c) => a + (W[c] ?? 0.5) + 0.02, 0);
  const tierOf = (px) => (px >= 320 ? 'L' : px >= 96 ? 'M' : 'S');
  const r2 = (v) => Math.round(v * 100) / 100;

  function playLabelSpec(it, px) {
    const tier = tierOf(px);
    const x0 = 9, span = 82;
    const spec = { tier, hue: it.hue || null, mono: monogram(it.title), ruler: null, cols: null, rim: null };
    // Monogram: Big Shoulders Bold capitals, left at 9, as large as the width allows, in the top half.
    const em = emOf(spec.mono);
    const cap = tier === 'S' ? 40 : tier === 'M' ? 34 : 30;
    spec.monoSize = r2(Math.min(cap / 0.8, span / em));
    spec.monoY = tier === 'S' ? 47 : tier === 'M' ? 46 : 50;
    // Era ruler (M, L) at the foot, so the top right corner stays clear for Read: seven equal cells on one
    // baseline, the playwright's cell lit; the baseline alone when undated (the run strip's rule). None at S.
    if (tier !== 'S') {
      const cell = span / ERAS.length, i = ERAS.indexOf(it.era);
      spec.ruler = { y: 92, x0, span, cell: r2(cell), lit: i, h: tier === 'L' ? 2.2 : 3 };
    }
    // The cast: a column per speaking part, largest first from the left, height by its lines over the largest
    // part's (at least 8%), equal widths up to a cap so a two-hander is two slabs; past the count, one dimmer
    // column for the rest. The tile's strip slot keeps the horizontal fingerprint (6.4b), so the two never repeat.
    const cast = (it.cast || []).filter((n) => n > 0);
    if (cast.length) {
      const max = tier === 'S' ? 6 : tier === 'M' ? 10 : 12;
      const gap = tier === 'S' ? 3 : tier === 'M' ? 2.2 : 1.6;
      const base = tier === 'S' ? 88 : 82, H = tier === 'S' ? 32 : 26;
      const more = cast.length > max;
      const shown = more ? cast.slice(0, max - 1) : cast;
      const n = shown.length + (more ? 1 : 0);
      const w = Math.min(tier === 'S' ? 16 : 13, (span - gap * (n - 1)) / n);
      const cols = shown.map((v, i) => ({ v, rest: false, i }));
      if (more) cols.push({ v: cast[max - 1], rest: true, i: shown.length });
      spec.cols = { base, cols: cols.map((c) => { const h = Math.max(0.08, c.v / cast[0]) * H; return { x: r2(x0 + c.i * (w + gap)), y: r2(base - h), w: r2(w), h: r2(h), rest: c.rest }; }) };
    }
    if (tier === 'L') spec.rim = [it.surname ? String(it.surname).toUpperCase() : null, it.years].filter(Boolean).join(' · ') || null;
    return spec;
  }

  function playLabelSVG(spec, theme, px) {
    const d = theme === 'dark' ? 1 : 0;
    const ground = spec.hue ? BOARD[spec.hue][d] : NONE.ground[d];
    const on = spec.hue ? ON[d] : NONE.on[d];
    const o = [];
    o.push(`<rect width="100" height="100" fill="${ground}"/>`);
    if (spec.ruler) {
      const R = spec.ruler;
      o.push(`<line x1="${R.x0}" x2="${R.x0 + R.span}" y1="${R.y}" y2="${R.y}" stroke="${on}" stroke-opacity=".38" stroke-width=".6"/>`);
      for (let i = 0; i <= 7; i++) {
        const x = r2(R.x0 + i * R.cell);
        o.push(`<line x1="${x}" x2="${x}" y1="${R.y - 1.6}" y2="${R.y + 1.6}" stroke="${on}" stroke-opacity=".38" stroke-width=".6"/>`);
      }
      if (R.lit >= 0) o.push(`<rect x="${r2(R.x0 + R.lit * R.cell + 0.8)}" y="${r2(R.y - R.h / 2)}" width="${r2(R.cell - 1.6)}" height="${R.h}" rx="${R.h / 2}" fill="${on}"/>`);
    }
    if (spec.rim) o.push(`<text x="9" y="15" font-family="Public Sans" font-weight="700" font-size="3.6" letter-spacing=".5" fill="${on}" fill-opacity=".85">${spec.rim}</text>`);
    o.push(`<text x="8.4" y="${spec.monoY}" font-family="Big Shoulders" font-weight="700" font-size="${spec.monoSize}" letter-spacing="${r2(spec.monoSize * 0.02)}" fill="${on}">${spec.mono}</text>`);
    if (spec.cols) for (const c of spec.cols.cols) o.push(`<rect x="${c.x}" y="${c.y}" width="${c.w}" height="${c.h}" fill="${on}" fill-opacity="${c.rest ? 0.42 : 1}"/>`);
    return `<svg viewBox="0 0 100 100" width="${px}" height="${px}" role="img" xmlns="http://www.w3.org/2000/svg">${o.join('')}</svg>`;
  }

  g.PlayLabel = { playLabelSpec, playLabelSVG, monogram, BOARD, NONE, ON, ERAS };
})(window);
