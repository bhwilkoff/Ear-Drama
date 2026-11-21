/**
 * The neutral age question (Decision 084): a birth year, only "under 13 or not" kept on the device.
 * Runs the SHIPPED js/age-gate.js.
 *
 *   node js/age-gate.test.js
 */
'use strict';
const fs = require('node:fs');
const assert = require('node:assert');

const mem = new Map();
Object.defineProperty(globalThis, 'localStorage', {
  value: { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => { mem.set(k, String(v)); } },
  configurable: true, writable: true,
});
const AgeGate = require('./age-gate.js');

// The year a 12-year-old may share with a 13-year-old counts as under 13.
assert.strictEqual(AgeGate.isUnder13(2013, 2026), true, 'born 2013: may be 12 in 2026');
assert.strictEqual(AgeGate.isUnder13(2012, 2026), false, 'born 2012: 13 or 14 in 2026');
assert.strictEqual(AgeGate.isUnder13(2020, 2026), true);
assert.strictEqual(AgeGate.isUnder13(1960, 2026), false);
assert.strictEqual(AgeGate.stored(), null, 'nothing kept before the question');
mem.set(AgeGate.KEY, '0');
assert.strictEqual(AgeGate.stored(), false);
mem.set(AgeGate.KEY, '1');
assert.strictEqual(AgeGate.stored(), true);
// Only the boolean is ever kept: the source writes no year.
const src = fs.readFileSync(`${__dirname}/age-gate.js`, 'utf-8');
assert.ok(!/setItem\([^)]*sel\.value/.test(src), 'the birth year is never stored');
assert.ok(!/API\./.test(src), 'the answer is never sent');
console.log('age-gate: PASS');
