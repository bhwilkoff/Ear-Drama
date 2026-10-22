/* Exercise the REAL tv.js focus engine in a minimal DOM shim.
   (The project's documented web verification pattern: run the real script in a
   Node DOM shim rather than trusting a headless browser's timer behavior.)

   Run from anywhere: files resolve against the repo root, not the cwd — it used
   to read 'tv.js' relative to the cwd and died with ENOENT when run from tools/.

   Deliberately NOT ported from the harness this descends from: source-shape
   assertions about one app's own surfaces (a hero slideshow, season chips,
   store-promo hiding, a TV transport readout, an on-screen diagnostics overlay,
   "arrival" focus on a primary action, programme-guide ordering). Add cases like
   them when YOUR app grows those surfaces — each one locked a real TV defect. */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');

let idc = 0;
class El {
  constructor(tag, rect, attrs = {}) {
    this.tagName = tag.toUpperCase();
    this.rect = rect;                 // {left, top, width, height}
    this.attrs = attrs;
    this.children = [];
    this.parent = null;
    this.classList = { add() {}, contains() { return false; } };
    this.style = {};
    this.name = attrs.name || `${tag}#${idc++}`;
    this.focusCount = 0;
  }
  getBoundingClientRect() {
    const r = this.rect;
    return { left: r.left, top: r.top, width: r.width, height: r.height,
             right: r.left + r.width, bottom: r.top + r.height };
  }
  focus() {
    this.focusCount++; doc.activeElement = this;
    // A real browser fires focusin; an engine that remembers focus per route
    // listens for it, and a shim that never dispatches it cannot test Back.
    focusinHandlers.forEach(h => h({ target: this }));
  }
  scrollIntoView() {}
  getAttribute(k) { return this.attrs[k] ?? null; }
  hasAttribute(k) { return k in this.attrs; }
  closest(sel) { return sel === '[hidden]' ? null : (matches(this, sel) ? this : null); }
  click() { this.clicked = true; }
  addEventListener() {}
}

/* The shim used to compare whole selector strings, so the day the engine added a
 * `:not([tabindex="-1"])` to its `a[href]` row every anchor silently stopped
 * matching and ten cases failed at once — a test that breaks on a selector it does
 * not understand, rather than on the behaviour it is checking. It now peels the
 * `:not(...)` clauses off and honours each one. */
function notClause(el, c) {
  if (c === '[disabled]') return 'disabled' in el.attrs;
  if (c === '[tabindex="-1"]') return el.attrs.tabindex === '-1';
  if (c.startsWith('.')) return (el.attrs.class || '').split(/\s+/).includes(c.slice(1));
  return false;
}

function matches(el, sel) {
  return sel.split(',').some(s => {
    s = s.trim();
    const nots = [...s.matchAll(/:not\(([^)]*)\)/g)].map(m => m[1]);
    const base = s.replace(/:not\([^)]*\)/g, '');
    let hit;
    if (base === 'a[href]') hit = el.tagName === 'A' && 'href' in el.attrs;
    else if (base === 'button') hit = el.tagName === 'BUTTON';
    else if (base === 'input') hit = el.tagName === 'INPUT';
    else if (base === 'select') hit = el.tagName === 'SELECT';
    else if (base === '[tabindex]') hit = 'tabindex' in el.attrs;
    else hit = false;
    if (!hit) return false;
    return !nots.some(c => notClause(el, c));
  });
}

const nodes = [];
const focusinHandlers = [];
const hashHandlers = [];
const doc = {
  activeElement: null,
  hidden: false,
  readyState: 'complete',
  documentElement: { classList: { add: (...c) => { doc._cls = (doc._cls||[]).concat(c); } } },
  body: { },
  querySelectorAll: (sel) => nodes.filter(n => matches(n, sel)),
  // A shim that omits a universal DOM method does not simplify the test, it just
  // moves the failure: the first engine code to call getElementById would throw
  // inside boot() and take every case in this file with it.
  getElementById: (id) => nodes.find(n => n.attrs && n.attrs.id === id) || null,
  querySelector: (sel) => nodes.find(n => matches(n, sel)) || null,
  addEventListener: (type, fn) => { if (type === 'focusin') focusinHandlers.push(fn); },
  createElement: () => new El('div', {left:0,top:0,width:0,height:0}),
};

const handlers = [];
global.document = doc;
global.window = {
  addEventListener: (type, fn) => {
    if (type === 'keydown') handlers.push(fn);
    if (type === 'hashchange') hashHandlers.push(fn);
  },
  close: () => {},
};
Object.defineProperty(global, 'navigator', { value: { userAgent: 'Mozilla/5.0 (SMART-TV; LINUX; Tizen 7.0) AppleWebKit' }, configurable: true });
global.location = { search: '', hash: '#/home' };
global.history = { back: () => { global._wentBack = true; } };
global.getComputedStyle = () => ({ visibility: 'visible', display: 'block' });
global.MutationObserver = class { observe() {} };
global.setTimeout = setTimeout;
global.clearTimeout = clearTimeout;
global.URLSearchParams = URLSearchParams;

// Build a realistic layout: a top nav, then two shelf rails of cards.
function card(name, left, top) {
  const e = new El('a', { left, top, width: 200, height: 340 }, { href: '#', name });
  nodes.push(e); return e;
}
const nav = [];
['Home','Browse','Search'].forEach((n, i) => {
  const e = new El('a', { left: 96 + i * 200, top: 54, width: 160, height: 50 }, { href: '#', name: 'nav-' + n });
  nodes.push(e); nav.push(e);
});
// Row A at y=200, Row B at y=600 — 5 cards each, 220px pitch.
const rowA = [], rowB = [];
for (let i = 0; i < 5; i++) rowA.push(card(`A${i}`, 96 + i * 220, 200));
for (let i = 0; i < 5; i++) rowB.push(card(`B${i}`, 96 + i * 220, 600));

// Load the real tv.js
const src = read('tv.js');
new Function(src)();

function press(keyCode) {
  const ev = { keyCode, preventDefault() {} };
  handlers.forEach(h => h(ev));
}
const K = { LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, BACK_WEBOS: 461, BACK_TIZEN: 10009 };

let pass = 0, fail = 0;
function check(label, got, want) {
  const ok = got === want;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}  (got ${got}, want ${want})`);
  ok ? pass++ : fail++;
}

// §3.1 — something is always focused after boot.
check('boot claims focus', doc.activeElement?.attrs.name, 'nav-Home');

// §3.5 — Right moves within the row.
doc.activeElement = rowA[0];
press(K.RIGHT);
check('right within rail', doc.activeElement.attrs.name, 'A1');

press(K.RIGHT);
check('right again', doc.activeElement.attrs.name, 'A2');

// §3.5 — Left comes back.
press(K.LEFT);
check('left within rail', doc.activeElement.attrs.name, 'A1');

// The critical grid property: Down from A1 must land on B1 (directly below),
// NOT B0 even though B0's centre is geometrically closer to some candidates.
doc.activeElement = rowA[1];
press(K.DOWN);
check('down keeps column', doc.activeElement.attrs.name, 'B1');

// Up returns to the same column.
press(K.UP);
check('up keeps column', doc.activeElement.attrs.name, 'A1');

// Up from the top row reaches the nav (nearest aligned item above).
doc.activeElement = rowA[0];
press(K.UP);
check('up from first row reaches nav', doc.activeElement.attrs.name, 'nav-Home');

// §3.4 — no dead ends: left from the leftmost card stays put, never strands.
doc.activeElement = rowA[0];
press(K.LEFT);
check('left at edge stays put', doc.activeElement.attrs.name, 'A0');

// §1.7 — Back navigates back on both platforms' key codes.
global._wentBack = false;
global.location.hash = '#/browse';
press(K.BACK_WEBOS);
check('webOS back (461) navigates', global._wentBack, true);

global._wentBack = false;
press(K.BACK_TIZEN);
check('Tizen back (10009) navigates', global._wentBack, true);

/* A FOCUSED <select> MUST OWN UP/DOWN. An engine that runs spatial navigation on
   every arrow without checking what has focus walks off the control, and its value
   can never change — filters that were reachable, looked right, and were dead on
   every TV. Left/Right must still navigate, or the viewer is trapped in a control
   they cannot leave, which is the bug a naive exemption introduces instead. */
{
  // Placed IN row A, right of the cards: at the left edge there is nothing to
  // navigate to, so a passing LEFT check would prove nothing.
  const sel = new El('select', { left: 96 + 5 * 220, top: 200, width: 180, height: 44 },
                     { name: 'filter-select' });
  nodes.push(sel);
  sel.focus();
  press(K.DOWN);
  check('DOWN on a focused select does not move focus', doc.activeElement?.attrs.name, 'filter-select');
  press(K.UP);
  check('UP likewise stays on the control', doc.activeElement?.attrs.name, 'filter-select');
  sel.focus();
  press(K.LEFT);
  check('LEFT still navigates away, so nobody is trapped',
        doc.activeElement?.attrs.name !== 'filter-select', true);
  // The exemption must be keyed on the ELEMENT, not the key: a card must still
  // move on Down, or the whole grid stops working.
  rowA[0].focus();
  press(K.DOWN);
  check('...and a normal card still moves on DOWN', doc.activeElement?.attrs.name, 'B0');
  nodes.pop();
}

/* tabindex="-1" TAKES AN ELEMENT OUT OF THE SPATIAL POOL — asserted BOTH WAYS. An
   element the engine must skip, and the same element without the attribute, which
   it must still reach. Without the control, "skipped" and "broken" look identical. */
{
  doc.activeElement = rowA[1];
  press(K.RIGHT);
  check('control: a plain card is reached on RIGHT', doc.activeElement.attrs.name, 'A2');

  rowA[2].attrs.tabindex = '-1';
  doc.activeElement = rowA[1];
  press(K.RIGHT);
  check('...and tabindex="-1" takes it out of the spatial pool', doc.activeElement.attrs.name, 'A3');
  delete rowA[2].attrs.tabindex;
}
check('FOCUSABLE honours tabindex="-1" on every row, not just the last',
      (src.match(/:not\(\[tabindex="-1"\]\)/g) || []).length >= 5, true);

/* MODERN CSS UNITS NEED AN OLDER-UNIT FALLBACK. Container-query units (cqi/cqw/cqh)
   and dvh/svh/lvh do not exist before Chromium 105/108 — every 2022-and-older
   Samsung TV — where an unsupported unit drops the WHOLE declaration and the
   property falls back to nothing (`height: 100dvh` on <body> collapses the layout).
   Rule: within a block, a declaration using a modern unit must be PRECEDED by one
   for the same property that does not. Parse declarations, not lines — reading one
   line back reported four false positives on multi-declaration lines. */
{
  const unfallbacked = [];
  for (const f of ['css/styles.css', 'tv.css']) {
    if (!fs.existsSync(path.join(ROOT, f))) continue;
    const css = read(f).replace(/\/\*[\s\S]*?\*\//g, '');
    const MODERN = /\d(?:cq[iwhb]|cqmin|cqmax|dvh|dvw|svh|svw|lvh|lvw)\b/;
    for (const m of css.matchAll(/\{([^{}]*)\}/g)) {
      const seen = new Set();
      for (const decl of m[1].split(';')) {
        const i = decl.indexOf(':');
        if (i < 0) continue;
        const prop = decl.slice(0, i).trim();
        if (!prop) continue;
        if (!MODERN.test(decl)) { seen.add(prop); continue; }
        if (!seen.has(prop)) unfallbacked.push(`${f} ${prop}: ${decl.slice(i + 1).trim().slice(0, 34)}`);
      }
    }
  }
  check('every container-query / dvh declaration has an older-unit fallback',
        unfallbacked.length ? unfallbacked.join(' | ') : 0, 0);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
