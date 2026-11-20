/**
 * The label (Decision 081, WEB-DESIGN §6.4r), run against the SHIPPED js/api.js and js/label-core.js:
 * the golden cases every stack runs (catalog/tests/golden/label_spec.json), the tiers from the tokens,
 * no chance in the spec (no hash, no Math.random, the same answer twice), the honest blanks (an undated
 * show draws no arc; red never appears), and a negative control: the same goldens over a copy of
 * label-core.js with one token changed must fail.
 *   node js/label.test.js
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.resolve(__dirname, '..');
const API_SRC = fs.readFileSync(path.join(__dirname, 'api.js'), 'utf8');
const CORE_SRC = fs.readFileSync(path.join(__dirname, 'label-core.js'), 'utf8');
const golden = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'tests', 'golden', 'label_spec.json'), 'utf8'));
const tokens = JSON.parse(fs.readFileSync(path.join(ROOT, 'design-tokens.json'), 'utf8'));

/** A fresh context holding API and a LabelCore built from `core` (the shipped source, or a mutant). */
function load(core) {
  const ctx = vm.createContext({ console, URL, URLSearchParams, setTimeout, clearTimeout });
  vm.runInContext(API_SRC, ctx, { filename: 'api.js' });
  vm.runInContext(core, ctx, { filename: 'label-core.js' });
  return vm.runInContext('LabelCore', ctx);
}
const L = load(CORE_SRC);

let passes = 0, failures = 0;
function test(name, fn) {
  try { fn(); passes += 1; console.log(`  ok    ${name}`); }
  catch (e) { failures += 1; console.log(`  FAIL  ${name}\n        ${e.message}`); }
}
function ok(v, msg) { if (!v) throw new Error(msg); }

/** The first difference between `got` and `want` (numbers within tol), or null. */
function diff(got, want, tol, at = '') {
  if (typeof want === 'number') return typeof got === 'number' && Math.abs(got - want) <= tol ? null : `${at}: got ${got}, want ${want}`;
  if (want === null || typeof want !== 'object') return got === want ? null : `${at}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`;
  if (Array.isArray(want)) {
    if (!Array.isArray(got) || got.length !== want.length) return `${at}: got ${JSON.stringify(got)}, want ${want.length} items`;
    for (let i = 0; i < want.length; i++) { const d = diff(got[i], want[i], tol, `${at}[${i}]`); if (d) return d; }
    return null;
  }
  if (!got || typeof got !== 'object') return `${at}: got ${JSON.stringify(got)}, want an object`;
  const keys = new Set([...Object.keys(want), ...Object.keys(got)]);
  for (const k of keys) { const d = diff(got[k], want[k], tol, `${at}.${k}`); if (d) return d; }
  return null;
}
const goldenFailures = (core) => golden.cases.map(c => { const d = diff(core.labelSpec(c.item, c.size), c.want, golden.tolerance); return d ? `${c.name}${d}` : null; }).filter(Boolean);

test('golden: every case in catalog/tests/golden/label_spec.json (every stack runs these)', () => {
  ok(golden.cases.length >= 30, `the golden file has its cases (${golden.cases.length})`);
  const bad = goldenFailures(L);
  ok(!bad.length, bad.slice(0, 3).join('\n        '));
});

test('golden: the cases cover every kind and every tier', () => {
  const seen = new Set(golden.cases.map(c => `${c.want.kind}/${c.want.tier}`));
  for (const k of ['series/S', 'series/M', 'series/L', 'episode/S', 'episode/M', 'episode/L', 'station/M', 'drama/S', 'drama/M', 'drama/L', 'person/S', 'person/L', 'play/S', 'play/M']) ok(seen.has(k), `no case for ${k}`);
});

test('negative control: one token changed (the dial starts a degree later) fails the goldens', () => {
  const mutant = CORE_SRC.replace('"startDeg": 210', '"startDeg": 211');
  ok(mutant !== CORE_SRC, 'the mutation applied');
  ok(goldenFailures(load(mutant)).length > 0, 'a changed dial passed every golden');
});

test('negative control: the S tier keeping its grooves fails the goldens', () => {
  const mutant = CORE_SRC.replace("if (tier === 'S') return null;", "if (tier === 'X') return null;");
  ok(mutant !== CORE_SRC, 'the mutation applied');
  ok(goldenFailures(load(mutant)).length > 0, 'grooves at S passed every golden');
});

test('the generated block is the tokens: tiers, dial and genres', () => {
  ok(L.T.tiers.M === tokens.art.label.tiers.M && L.T.tiers.L === tokens.art.label.tiers.L, 'tiers match design-tokens.json');
  ok(L.tierOf(tokens.art.label.tiers.M - 1) === 'S' && L.tierOf(tokens.art.label.tiers.M) === 'M' && L.tierOf(tokens.art.label.tiers.L) === 'L', 'tier thresholds');
  ok(JSON.stringify(L.GENRES.slice().sort()) === JSON.stringify(Object.keys(tokens.color.board).filter(k => !k.startsWith('$')).sort()), 'genres are the boards');
  ok(Math.abs(L.yearDeg(1930) - 210) < 1e-9 && Math.abs(L.yearDeg(1963) - (210 - 240)) < 1e-9, 'the dial spans 1930 to the end of 1962 over 240 degrees');
});

test('no chance: no hash or random in the spec, and the same answer twice', () => {
  ok(!/Math\.random|hash|fnv|crypto/i.test(CORE_SRC.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, '')), 'label-core.js uses no randomness or hashing');
  for (const c of golden.cases) ok(JSON.stringify(L.labelSpec(c.item, c.size)) === JSON.stringify(L.labelSpec(JSON.parse(JSON.stringify(c.item)), c.size)), `two answers for ${c.name}`);
});

test('honest blanks: undated draws no arc; an arc runs clockwise; no red anywhere', () => {
  for (const it of [{ kind: 'series', name: 'X' }, { kind: 'series', name: 'X', first: 'unknown' }, { kind: 'episode', name: 'X', num: 3 }]) {
    ok(L.labelSpec(it, 200).arc === null, `an arc for ${JSON.stringify(it)}`);
  }
  for (const c of golden.cases) {
    const s = c.want;
    if (s.arc) ok(s.arc.from > s.arc.to, `${c.name}: the arc does not run clockwise`);
    ok(!/record|error/i.test(JSON.stringify(s).replace(/RECORDED/g, '')), `${c.name}: a reserved color`);
  }
});

test('every disc kind with a name draws text inside its label', () => {
  for (const kind of ['series', 'episode', 'drama', 'person']) {
    for (const size of [32, 56, 128, 360, 1920]) {
      const s = L.labelSpec({ kind, name: 'The Whistler Mystery', genre: 'mystery' }, size);
      ok(s.text.length && s.text.every(t => t.s && t.size > 0), `${kind} at ${size} has no text`);
      const r = s.label ? s.label.r : L.T.person.fitR;
      for (const t of s.text) ok(t.y > 50 - r && t.y < 50 + r, `${kind} at ${size}: text outside its label (y ${t.y})`);
    }
  }
});

console.log(`${failures ? 'FAIL' : 'PASS'}: ${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
