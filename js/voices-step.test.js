/**
 * Better voices at first launch (PLAYS-DESIGN §2.8 rule 13, Decision 090), run against the SHIPPED js/voices-step.js
 * with fake voices and a fake sheet: nothing is drawn or downloaded.
 *   node js/voices-step.test.js
 *
 * Seen to fail, 2026-11-26, with decide() mutated to ignore the stage at launch ("first launch shows once": shown
 * twice), with the onChange write removed ("never after a download": offered at first use), and with the forced
 * door writing its stage ("the door reads and writes nothing").
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

vm.runInThisContext(fs.readFileSync(path.join(__dirname, 'voices-step.js'), 'utf8'), { filename: 'voices-step.js' });
const VoicesStep = vm.runInThisContext('VoicesStep');

let passes = 0, failures = 0;
const results = [];
function ok(cond, name) { if (cond) passes++; else { failures++; console.log(`FAIL ${name}`); } }
function eq(a, b, name) {
  const pass = JSON.stringify(a) === JSON.stringify(b);
  ok(pass, pass ? name : `${name}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
const test = (name, fn) => results.push([name, fn]);
function memory() { const m = new Map(); return { m, getItem: k => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: k => m.delete(k) }; }

/** Fake Voices: `status` drives offered(); `emit()` tells listeners a state changed. */
function fakeVoices(status = 'absent') {
  const fns = new Set();
  const v = {
    st: status,
    status: () => v.st,
    offered: () => ['probing', 'absent', 'failed'].includes(v.st),
    whenStarted: async () => false,
    probe: async () => v.st !== 'unsupported',
    onChange(fn) { fns.add(fn); return () => fns.delete(fn); },
    set(s) { v.st = s; fns.forEach(f => f()); },
  };
  return v;
}
/** One page load over a kept storage: each page counts its own sheets. */
function page(storage, voices, search = '', extra = {}) {
  const shown = [];
  const step = VoicesStep.create({ storage, search, voices, present: () => shown.push(1), ...extra });
  return { step, shown };
}

test('first launch shows once; the next launch does not', async () => {
  const s = memory();
  const a = page(s, fakeVoices());
  eq(await a.step.launch(), true, 'first launch: shown');
  eq(a.shown.length, 1, 'one sheet');
  eq(a.step.stage(), 1, 'recorded as offered at launch');
  const b = page(s, fakeVoices());
  eq(await b.step.launch(), false, 'second launch: not shown');
});

test('a skip is remembered, then the first read offers it once more, and never again', async () => {
  const s = memory();
  await page(s, fakeVoices()).step.launch();
  const b = page(s, fakeVoices());
  eq(await b.step.launch(), false, 'skipped: not at the next launch');
  eq(await b.step.firstUse(), true, 'first read: offered again');
  eq(b.step.stage(), 2, 'done');
  const c = page(s, fakeVoices());
  eq([await c.step.launch(), await c.step.firstUse()], [false, false], 'never after that');
});

test('one sheet per page, even when the first page is a script', async () => {
  const s = memory();
  const a = page(s, fakeVoices());
  const r = [await a.step.firstUse(), await a.step.launch()];
  eq(r, [true, false], 'the read shows it; the launch that follows does not');
  eq(a.shown.length, 1, 'one sheet');
});

test('never after a download', async () => {
  const s = memory();
  const v = fakeVoices();
  const a = page(s, v);
  await a.step.launch();
  v.set('downloading');
  eq(a.step.stage(), 2, 'a download begun ends the offers');
  v.set('failed');
  eq(await page(s, v).step.firstUse(), false, 'not even after it failed');
  const fresh = memory();
  const here = fakeVoices('ready');
  eq(await page(fresh, here).step.launch(), false, 'voices already here: no sheet at launch');
  eq(await page(fresh, here).step.firstUse(), false, 'nor at first use');
  const lib = memory();
  const lv = fakeVoices();
  page(lib, lv);
  lv.set('downloading');
  eq(VoicesStep.stageOf(lib), 2, 'a download from Library counts too');
});

test('what this device cannot run is never offered, and the chance is kept', async () => {
  const s = memory();
  eq(await page(s, fakeVoices('unsupported')).step.launch(), false, 'no WebGPU: no sheet');
  eq(VoicesStep.stageOf(s), 0, 'nothing recorded');
  eq(await page(s, fakeVoices()).step.firstUse(), true, 'a later page that can run them offers at first use');
  eq(await page(memory(), fakeVoices(), '', { tv: true }).step.launch(), false, 'never on a TV');
});

test('the doors: ?onboard=0 shows nothing; ?voices_step=1 shows at launch and reads and writes nothing', async () => {
  const s = memory();
  eq(await page(s, fakeVoices(), '?onboard=0').step.launch(), false, 'skip door: no sheet');
  s.setItem(VoicesStep.KEY, '2');
  const f = page(s, fakeVoices('ready'), '?voices_step=1');
  eq(await f.step.launch(), true, 'forced: shown though done and downloaded');
  eq(await f.step.firstUse(), false, 'one sheet only');
  eq(s.getItem(VoicesStep.KEY), '2', 'the record is untouched');
  const g = memory();
  const gv = fakeVoices();
  await page(g, gv, '?voices_step=1').step.launch();
  gv.set('downloading');
  eq(g.m.size, 0, 'a forced session writes nothing, even on a download');
});

test('decide() is the rule as written', () => {
  eq(VoicesStep.decide({ moment: 'launch', stage: 0, eligible: true }), { show: true, next: 1 }, 'launch, never offered');
  eq(VoicesStep.decide({ moment: 'launch', stage: 1, eligible: true }), { show: false, next: 1 }, 'launch, offered');
  eq(VoicesStep.decide({ moment: 'use', stage: 1, eligible: true }), { show: true, next: 2 }, 'use, skipped');
  eq(VoicesStep.decide({ moment: 'use', stage: 2, eligible: true }), { show: false, next: 2 }, 'use, done');
  eq(VoicesStep.decide({ moment: 'use', stage: 0, eligible: false }), { show: false, next: 0 }, 'nothing to offer');
});

(async () => {
  for (const [name, fn] of results) {
    try { await fn(); } catch (e) { failures++; console.log(`FAIL ${name}: ${e && e.stack}`); }
  }
  console.log(failures ? `FAIL: ${failures} failing, ${passes} passing` : `PASS: ${passes} checks`);
  process.exit(failures ? 1 : 0);
})();
