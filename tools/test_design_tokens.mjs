#!/usr/bin/env node
// The look is chosen once, in design-tokens.json, and every platform's token
// file is written from it by tools/design_tokens.mjs. This test fails when:
//   1. any platform's file differs from what the generator would write
//      (someone edited a generated file by hand, or forgot to run it);
//   2. a text pair in either mode falls below WCAG 2.2 AA contrast;
//   3. a target stops depending on the JSON (the negative control: change
//      every color in memory and every target must change with it);
//   4. a tvOS type level maps to a system style under the 29 pt body floor
//      (AGENTS.md; tvOS-DESIGN §7.1), with its own negative control.
//
//   node tools/test_design_tokens.mjs

import { plan, loadTokens, colors, contrast, ROOT } from './design_tokens.mjs';

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

console.log(failed ? `${failed} design-token check(s) FAILED` : `all ${results.length} token files match; contrast holds in light and dark`);
process.exit(failed ? 1 : 0);
