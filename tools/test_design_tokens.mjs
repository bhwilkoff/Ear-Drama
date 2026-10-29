#!/usr/bin/env node
// The look is chosen once, in design-tokens.json, and every platform's token
// file is written from it by tools/design_tokens.mjs. This test fails when:
//   1. any platform's file differs from what the generator would write
//      (someone edited a generated file by hand, or forgot to run it);
//   2. a text pair in either mode falls below WCAG 2.2 AA contrast;
//   3. a target stops depending on the JSON (the negative control: change
//      every color in memory and every target must change with it);
//   4. a tvOS type level maps to a system style under the 29 pt body floor
//      (AGENTS.md; tvOS-DESIGN §7.1), with its own negative control;
//   5. color.genre stops naming exactly the catalog's genre keys, or a genre
//      mark drops below 3:1 on background, surface, or surfaceAlt in either
//      mode (Decision 064), with its own negative control;
//   5b. color.onGenre stops naming the same keys as color.genre, or text on a
//      genre board drops below 4.5:1 in either mode (D2b-3), with its own
//      negative control.
//
//   node tools/test_design_tokens.mjs

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { plan, loadTokens, colors, genres, onGenres, boards, onBoards, oklch, apca, deltaE, contrast, webFonts, ROOT } from './design_tokens.mjs';

let failed = 0;
const ok = (cond, msg) => { console.log(`  ${cond ? 'ok  ' : 'FAIL'}  ${msg}`); if (!cond) failed++; };

// 1. Every platform matches the JSON.
const tokens = loadTokens();
let results;
try { results = plan(ROOT, tokens); } catch (e) { ok(false, e.message); results = []; }
for (const r of results) ok(r.current === r.expected, `${r.path} matches design-tokens.json`);

// 2. Contrast, both modes. Text needs 4.5:1; a primary fill against the page needs 3:1.
const c = tokens.color.brand, s = tokens.color.semantic;
const pairs = [
  ['text', c.text, 'background', c.background, 4.5],
  ['text', c.text, 'surface', c.surface, 4.5],
  ['text', c.text, 'surfaceAlt', c.surfaceAlt, 4.5],
  ['textMuted', c.textMuted, 'background', c.background, 4.5],
  ['textMuted', c.textMuted, 'surface', c.surface, 4.5],
  ['onPrimary', c.onPrimary, 'primary', c.primary, 4.5],
  ['primary', c.primary, 'background', c.background, 3],
  ['error', s.error, 'errorSurface', s.errorSurface, 4.5],
  ['error', s.error, 'background', c.background, 4.5],
  ['success', s.success, 'background', c.background, 4.5],
  ['warning', s.warning, 'background', c.background, 4.5],
  ...(c.secondary ? [
    ['onSecondary', c.onSecondary, 'secondary', c.secondary, 4.5],
    ['secondary', c.secondary, 'background', c.background, 3],
  ] : []),
  ...(c.record ? [
    ['onRecord', c.onRecord, 'record', c.record, 4.5],
    ['record', c.record, 'background', c.background, 3],
    ['record', c.record, 'surface', c.surface, 3],
  ] : []),
  ...(c.link ? [
    ['link', c.link, 'background', c.background, 4.5],
    ['link', c.link, 'surface', c.surface, 4.5],
  ] : []),
];
for (const mode of ['light', 'dark']) {
  for (const [fa, a, fb, b, min] of pairs) {
    const r = contrast(a[mode], b[mode]);
    ok(r >= min, `${mode}: ${fa} on ${fb} is ${r.toFixed(2)}:1 (needs ${min}:1)`);
  }
}

// 3. Negative control: a test that cannot fail is not a test. Change every
//    value in memory; every target must come out different.
const altered = structuredClone(tokens);
for (const kind of ['brand', 'semantic']) {
  for (const v of Object.values(altered.color[kind])) { v.light = '#123456'; v.dark = '#654321'; }
}
for (const l of altered.type) l.size += 1;
for (const k of Object.keys(altered.space)) altered.space[k] += 1;
for (const k of Object.keys(altered.radius)) altered.radius[k] += 1;
const after = plan(ROOT, altered);
for (const r of after) ok(r.expected !== r.current, `${r.path} changes when the tokens change`);
ok(colors(tokens).length > 0, 'the palette is not empty');

// 4. The tvOS floor. Point sizes of tvOS's text styles (HIG, Typography).
const TVOS_POINTS = { title: 76, title2: 57, title3: 48, headline: 38, callout: 31, body: 29,
  caption: 25, caption2: 23, footnote: 23 };
const underFloor = (levels) => levels.filter((l) => !((TVOS_POINTS[l.tvos] ?? 0) >= 29)).map((l) => l.id);
ok(underFloor(tokens.type).length === 0, `every tvOS type level is at least 29 pt (under: ${underFloor(tokens.type).join(', ') || 'none'})`);
const shrunk = structuredClone(tokens);
shrunk.type.find((l) => l.id === 'caption').tvos = 'caption';
ok(underFloor(shrunk.type).includes('caption'), 'the floor check catches a tvOS caption at 25 pt');

// 5. Genre marks (Decision 064): one per catalog genre key, each a 3:1 mark on
//    every ground it sits on, in both modes, with a negative control.
const catalogGenres = (() => {
  const m = /^GENRES = \(([^)]*)\)/m.exec(readFileSync(join(ROOT, 'catalog/tools/genres.py'), 'utf8'));
  return m ? [...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]) : [];
})();
const gs = genres(tokens);
ok(catalogGenres.length > 0 && JSON.stringify(gs.map((g) => g.name).sort()) === JSON.stringify([...catalogGenres].sort()),
  `color.genre names exactly the catalog's genres (${catalogGenres.join(', ')})`);
const GROUNDS = ['background', 'surface', 'surfaceAlt'];
const weakMarks = (t) => {
  const out = [];
  for (const g of genres(t)) for (const mode of ['light', 'dark']) for (const ground of GROUNDS) {
    const r = contrast(g[mode], t.color.brand[ground][mode]);
    if (r < 3) out.push(`${mode} ${g.name} on ${ground} ${r.toFixed(2)}:1`);
  }
  return out;
};
let lowest = Infinity;
for (const g of gs) for (const mode of ['light', 'dark']) for (const ground of GROUNDS) {
  lowest = Math.min(lowest, contrast(g[mode], tokens.color.brand[ground][mode]));
}
ok(weakMarks(tokens).length === 0, `every genre mark holds 3:1 on background, surface, surfaceAlt (lowest ${lowest.toFixed(2)}:1; under: ${weakMarks(tokens).join('; ') || 'none'})`);
const faded = structuredClone(tokens);
faded.color.genre.drama.light = '#E0E0E4';
ok(weakMarks(faded).some((w) => w.startsWith('light drama')), 'the genre check catches a pale light-mode drama mark');

// 5b. Text on a genre mark used as a fill (a part's initial): 4.5:1 on its own
//     hue, both modes (D2b-3; D2c-1 moved the board text to color.onBoard).
const weakBoards = (t) => {
  const hue = Object.fromEntries(genres(t).map((g) => [g.name, g]));
  const out = [];
  for (const g of onGenres(t)) for (const mode of ['light', 'dark']) {
    if (!hue[g.name]) { out.push(`${g.name} has no genre`); continue; }
    const r = contrast(g[mode], hue[g.name][mode]);
    if (r < 4.5) out.push(`${mode} ${g.name} ${r.toFixed(2)}:1`);
  }
  return out;
};
ok(JSON.stringify(onGenres(tokens).map((g) => g.name).sort()) === JSON.stringify(gs.map((g) => g.name).sort()), 'color.onGenre names the same keys as color.genre');
let lowestBoard = Infinity;
for (const g of onGenres(tokens)) for (const mode of ['light', 'dark']) lowestBoard = Math.min(lowestBoard, contrast(g[mode], tokens.color.genre[g.name][mode]));
ok(weakBoards(tokens).length === 0, `text on every genre mark holds 4.5:1 (lowest ${lowestBoard.toFixed(2)}:1; under: ${weakBoards(tokens).join('; ') || 'none'})`);
const inkSerial = structuredClone(tokens);
inkSerial.color.onGenre.serial.dark = '#F2F2F4';
ok(weakBoards(inkSerial).some((w) => w.startsWith('dark serial')), 'the mark check catches light text on the dark serials mark');

// 5c. The boards (D2c-1, Decision 064; docs/research/palette/surfaces.md). Per mode:
//   - every board takes ONE text color, at 4.5:1 and APCA Lc 75 or more;
//   - every board sits in one OKLCH lightness band (spread at most 0.04), so a
//     grid of boards reads as one set and none outshines its neighbor;
//   - in dark mode a board stays a surface, never a lamp: APCA Lc 30 or less
//     against background and surface (D2b-3's full-hue boards read Lc 39 to 84);
//   - the drama board and mark stay 20 CIEDE2000 from recording red, and no
//     board comes within 15 of it (red means recording).
//   Each rule has its own negative control below.
const boardProblems = (t) => {
  const out = [];
  const bs = boards(t), ons = Object.fromEntries(onBoards(t).map((g) => [g.name, g]));
  const gnames = genres(t).map((g) => g.name).sort();
  if (JSON.stringify(bs.map((g) => g.name).sort()) !== JSON.stringify(gnames)) out.push('color.board does not name the genre keys');
  if (JSON.stringify(Object.keys(ons).sort()) !== JSON.stringify(gnames)) out.push('color.onBoard does not name the genre keys');
  const br = t.color.brand;
  for (const mode of ['light', 'dark']) {
    const texts = new Set(bs.map((g) => ons[g.name] && ons[g.name][mode]));
    if (texts.size !== 1) out.push(`${mode}: ${texts.size} text colors on the boards`);
    const Ls = bs.map((g) => oklch(g[mode]).L);
    const spread = Math.max(...Ls) - Math.min(...Ls);
    if (spread > 0.04) out.push(`${mode}: board lightness spread ${spread.toFixed(3)} > 0.04`);
    for (const g of bs) {
      const on = ons[g.name] && ons[g.name][mode];
      if (!on) continue;
      const r = contrast(on, g[mode]), lc = apca(on, g[mode]);
      if (r < 4.5 || lc < 75) out.push(`${mode} ${g.name}: text ${r.toFixed(2)}:1, Lc ${lc.toFixed(1)} (needs 4.5:1, Lc 75)`);
      if (mode === 'dark') for (const ground of ['background', 'surface']) {
        const glare = apca(g[mode], br[ground][mode]);
        if (glare > 30) out.push(`dark ${g.name} glares on ${ground}: Lc ${glare.toFixed(1)} > 30`);
      }
      if (br.record) {
        const e = deltaE(g[mode], br.record[mode]), need = g.name === 'drama' ? 20 : 15;
        if (e < need) out.push(`${mode} ${g.name} board is ${e.toFixed(1)} from record (needs ${need})`);
      }
    }
    if (br.record && t.color.genre.drama) {
      const e = deltaE(t.color.genre.drama[mode], br.record[mode]);
      if (e < 20) out.push(`${mode} drama mark is ${e.toFixed(1)} from record (needs 20)`);
    }
  }
  return out;
};
const bp = boardProblems(tokens);
ok(bp.length === 0, `the boards hold: one text color per mode at Lc 75, one lightness band, no dark glare, drama apart from red (problems: ${bp.join('; ') || 'none'})`);
const neg = (name, edit, expect) => {
  const t = structuredClone(tokens); edit(t);
  ok(boardProblems(t).some((p) => p.includes(expect)), `the board check catches ${name}`);
};
neg("D2b-3's full-hue dark drama board", (t) => { t.color.board.drama.dark = '#FF91C3'; }, 'dark drama glares');
neg('a lighter board breaking the band', (t) => { t.color.board.comedy.light = '#8D8300'; }, 'board lightness spread');
neg('a second text color on the boards', (t) => { t.color.onBoard.comedy.light = '#131316'; }, 'text colors on the boards');
neg('a drama board in recording red', (t) => { t.color.board.drama.light = '#B0152F'; }, 'drama board is');
neg('white text on a pale board', (t) => { t.color.board.news.light = '#CECEC0'; }, 'light news: text');

// 6. Every face the tokens name is a file the platform ships (Decision 060),
//    and only the display levels set the display face, with a negative control.
const missingFonts = (t) => {
  const want = [
    ...webFonts(t).map((f) => `fonts/${f.src}`),
    ...(t.font.display?.apple ? [`apple/Resources/Fonts/${t.font.display.apple}.ttf`] : []),
    ...(t.font.display?.android ? [`android/app/src/main/res/font/${t.font.display.android}.ttf`] : []),
  ];
  return want.filter((p) => !existsSync(join(ROOT, p)));
};
ok(missingFonts(tokens).length === 0, `every named font file exists (missing: ${missingFonts(tokens).join(', ') || 'none'})`);
const renamed = structuredClone(tokens);
renamed.font.display.apple = 'NoSuchFace-Bold';
ok(missingFonts(renamed).includes('apple/Resources/Fonts/NoSuchFace-Bold.ttf'), 'the font check catches a face with no file');
const displayIds = tokens.type.filter((l) => l.face === 'display').map((l) => l.id);
ok(JSON.stringify(displayIds) === JSON.stringify(['pageTitle', 'sectionHeader']), `the display face sets L1 and L2 only (${displayIds.join(', ')})`);

// The Cast receiver colors its error code with the error token, never the brand ink.
const castErrorUsesToken = (html) => /#error code \{[^}]*color: var\(--color-error\)/.test(html);
const castHtml = readFileSync(join(ROOT, 'cast/index.html'), 'utf8');
ok(castErrorUsesToken(castHtml), 'the Cast error code takes the error token');
ok(!castErrorUsesToken(castHtml.replace('color: var(--color-error); font-size: 1.8vh', 'color: var(--brand-primary); font-size: 1.8vh')), 'the Cast check catches the brand ink');

console.log(failed ? `${failed} design-token check(s) FAILED` : `all ${results.length} token files match; contrast holds in light and dark`);
process.exit(failed ? 1 : 0);
